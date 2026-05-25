# Plan 01 — Profile feature group

Status: revised after Codex review (v2)
Spec: [`../spec.md`](../spec.md)

---

## Revision log

**v2 — addressed Codex review of 2026-05-25.** Key changes:

- **§4.1 / §4.2 (top blocker):** `ProfilePort.profile_for/1` replaced with
  `profile_for/2 (subject, viewer)` and a new `own_profile_for/1`. Private-recognition
  and given-list filtering is now enforced at the context/port boundary, not in
  `PeopleLive`. `§4.3` updated to remove the caller-patch pattern and preserve
  `Recognitions.received_by/1` for Today's use.
- **§4.2 (time-dependency):** `count_this_month/1` now accepts an explicit `Date.t()`
  argument so unit tests are deterministic and not sensitive to month boundaries.
- **§2.2 / §6.1 / §7 (icons):** `RewardItem.glyph` replaced with `RewardItem.icon
  :: String.t()`. Template renders `<.icon name={item.icon} />` with Heroicon names
  (`hero-sparkles`, `hero-clock`, `hero-gift`, `hero-heart`) instead of Unicode glyphs.
- **§6.3 (desktop shell):** Corrected the false claim that `Layouts.app` provides the
  desktop side-rail automatically. `ProfileLive` and `PeopleLive :show` must call
  `FoyerComponents.desktop_rail/1` themselves, matching `TodayLive` / `HouseLive`.
- **§5.3 (PeopleLive):** `apply_show/2` now calls `profile_for(target, scope.user)`
  and relies on the context boundary — no post-hoc `Enum.filter` on the card.
- **§8 (tests):** Added unit test asserting context filters private recognitions for
  non-recipient viewer. Route smoke tests noted as `async: false` when sharing sandbox
  state. Stats-row assertion uses element ID, not broad text matching.
- **§5.1 / §9 (settings links):** Inert settings links changed from `<a href="#">`
  to `<button type="button" aria-disabled="true">` per nit.
- **§2.2 (RewardItem):** `cost` type changed from `integer()` to `non_neg_integer()`.
- **§10 (open questions resolved):** OQ1–OQ5 resolved in-line as concrete decisions
  rather than open questions. `points_earned` labelled as bonus-point earnings only
  with unreconciled-balance note. `inserted_at` confirmed for timestamps.
- **Cross-group (memberships):** Decided that `Profile.Card` does NOT host channel
  memberships. `PeopleLive :show` loads them separately via `Channels.list_for_user/1`.
  Added Cross-group dependencies note.

---

## 1. Goal & non-goals

### Goal

Deliver the Profile surface as a read-only orchestrator page that makes recognition
tangible for each staff member. The page at `/me` renders the current user's `Card`
DTO showing identity, recognition history (received and given), Foyer points balance
with an earnings breakdown, and a static rewards catalog with "coming soon"
affordances. The `profile_card` component already exists in scaffold form; this plan
fills in every stubbed or incomplete element to match the three design files:

- `designs/profile/mobile-maya-okafor.html` — line staff mobile view (Today context,
  not the Profile page itself; confirms identity and on-shift indicator)
- `designs/profile/mobile-recognitions-received.html` — the full Profile page on
  mobile; the primary target design
- `designs/profile/desktop-charlotte-voss.html` — desktop shell (Chat surface shown,
  but the profile card rendered via `PeopleLive :show` for Maya confirms desktop
  column layout and the side-rail)

### Non-goals

- **Rewards redemption.** Catalog items render with a "Coming soon" label; no submit
  handler, no form, no backend write.
- **Profile editing.** No name, language, or preference updates in v1. Settings links
  in the mobile design (Notifications & alerts, Languages & translation, Shift
  availability, Sign out) are rendered as inert links or explicitly marked "coming
  soon."
- **Acknowledgement analytics.** The "Ack on time" stat tile renders the literal `—`
  placeholder.
- **Viewing other users' given recognitions.** The `Given` section is own-profile-only
  (`/me`); `PeopleLive :show` suppresses it.
- **Points ledger writes.** Points accumulate through Recognition events; no direct
  points mutation from Profile.
- **Notification delivery rules / push.** Out of scope for v1 per FOYER.md.

---

## 2. Schemas

Profile owns **no Ecto schemas**. It is a read-only orchestrator over Accounts,
Recognitions, and Shifts.

### 2.1 `Foyer.Profile.Card` — typed_struct DTO (additions required)

Current shape (`lib/foyer/profile/card.ex`):

```elixir
typedstruct enforce: true do
  field :user,      User.t()
  field :received,  [Recognition.t()]
  field :given,     [Recognition.t()]
  field :points,    integer()
  field :on_shift?, boolean()
end
```

**Required additions** to match the spec:

| New field | Type | Source | Rationale |
|-----------|------|--------|-----------|
| `received_this_month` | `integer()` | derived from `:received` | F.Profile.9 "Recognitions this month" stat |
| `points_earned` | `[Recognition.t()]` | subset of `:received` where `bonus_points > 0` | F.Profile.12 points breakdown |

`received_this_month` is computed inside `Foyer.Profile`'s private `build_card/2` by
calling `count_this_month(received, Date.utc_today())`. It does not need a separate
DB query. (v2: explicit date arg for deterministic tests.)

`points_earned` is likewise computed by filtering `:received` where
`r.bonus_points > 0` — no additional query.

Both are derivable from the data already fetched; computing them in `build_card/2`
keeps the LiveView slim.

### 2.2 `Foyer.Profile.RewardItem` — typed_struct (new, optional)

The scaffold stores the rewards catalog as a module-level `@rewards` list of bare maps
in `ProfileLive`. Per ARCHITECTURE.md's "no bare maps" rule, this should be a
typed_struct.

```elixir
defmodule Foyer.Profile.RewardItem do
  use TypedStruct

  typedstruct enforce: true do
    field :title,       String.t()
    field :description, String.t()
    field :cost,        non_neg_integer()
    field :icon,        String.t()   # Heroicon name, e.g. "hero-sparkles", "hero-gift"
  end
end
```

The catalog is stored as a **module constant** in `Foyer.Profile` (see §7). This
keeps it close to the context (not in the LiveView) and makes it testable in
isolation. `ProfileLive` calls `Foyer.Profile.rewards_catalog/0` to get the list.

---

## 3. Migrations

**None required.** All fields (`points_balance`, `languages`, `title`, `role`,
`department`) already exist on `Accounts.User`. The `recognitions` table already
carries `bonus_points`, `public`, `values`, and `inserted_at`. No new columns.

If a future iteration needs to persist recognitions-this-month or a points-history
view, that is a Recognitions group concern, not Profile.

---

## 4. Context API

### 4.1 `Foyer.ProfilePort` — additions (v2 delta)

The original `profile_for/1` is replaced with a viewer-aware two-argument callback.
A `own_profile_for/1` convenience is also added. **v2 change:** the port now enforces
the F.Profile.6 privacy boundary — callers cannot accidentally expose private
recognitions.

```elixir
defmodule Foyer.ProfilePort do
  alias Foyer.Accounts.User
  alias Foyer.Profile.Card
  alias Foyer.Profile.RewardItem

  @callback profile_for(subject :: User.t(), viewer :: User.t()) :: Card.t()
  @callback own_profile_for(User.t()) :: Card.t()
  @callback rewards_catalog() :: [RewardItem.t()]
end
```

`rewards_catalog/0` is a pure function returning a module-level constant list. It
belongs on the port so the LiveView can be tested with a mock that returns a controlled
list.

### 4.2 `Foyer.Profile` — implementation additions (v2 delta)

```elixir
# Viewer-aware boundary. Enforces F.Profile.6 and F.Profile.8 at the context level.
@spec profile_for(User.t(), User.t()) :: Card.t()
def profile_for(%User{id: id} = subject, %User{id: id}) do
  # Same user — own-profile view. All recognitions visible.
  build_card(subject, :self)
end

def profile_for(%User{} = subject, %User{}) do
  # Colleague view — strip private recognitions and given list at the boundary.
  subject
  |> build_card(:other)
  |> then(fn card ->
    %{card | received: Enum.filter(card.received, & &1.public), given: []}
  end)
end

# Convenience wrapper for ProfileLive (/me path).
@spec own_profile_for(User.t()) :: Card.t()
def own_profile_for(%User{} = user), do: build_card(user, :self)

@spec rewards_catalog() :: [RewardItem.t()]
def rewards_catalog, do: @rewards_catalog

# private helpers

defp build_card(%User{} = user, _viewer_kind) do
  received = Recognitions.received_by(user)
  given    = Recognitions.given_by(user)
  today    = Date.utc_today()

  %Card{
    user: user,
    received: received,
    given: given,
    points: user.points_balance || 0,
    on_shift?: not is_nil(Shifts.current_shift_for(user)),
    received_this_month: count_this_month(received, today),
    points_earned: Enum.filter(received, &(&1.bonus_points > 0))
  }
end

# Accepts an explicit Date so tests are deterministic and not sensitive to
# month boundaries or UTC timezone. v1 uses UTC; a future iteration may pass
# the property timezone from runtime config.
defp count_this_month(recognitions, %Date{year: year, month: month}) do
  Enum.count(recognitions, fn r ->
    date = DateTime.to_date(r.inserted_at)
    date.year == year and date.month == month
  end)
end
```

`@rewards_catalog` is a module attribute defined once at compile time — see §7.

### 4.3 `Foyer.Recognitions` — no changes required

`received_by/1` already fetches all recognitions (public and private) for the
recipient and preloads `:sender` and `:recipient`. It is intentionally public-and-private
so Today can use it to count private recognitions held for an off-shift user (OQ5 /
F.Today). **Profile must not change this function's semantics.** The visibility
filtering for F.Profile.6 is now enforced in `Foyer.Profile.profile_for/2` at the
context boundary — not in the LiveView.

**v2 change from original plan:** The caller-patch pattern in `PeopleLive.apply_show/2`
(`Enum.filter(card.received, & &1.public)`) is removed. The context now handles it.

### 4.4 `Foyer.Accounts` — no changes required

`User.languages` is already `{:array, :string}`. `User.title` is already a string.
The `property` display (e.g. `LDN·MAY`) is a **compile-time constant** — the POC
has one property ("The Linden, Mayfair London"). Property codes are not stored per
user; they are rendered from application config. The executing agent should introduce
a small `Foyer.Property` module or a config key `Application.get_env(:foyer,
:property_code, "LDN·MAY")` rather than hard-coding in the template. This is a
minor gap in the scaffold.

---

## 5. LiveView

### 5.1 Routes (no changes)

```elixir
live "/me",          ProfileLive, :me     # own profile
live "/people/:id",  PeopleLive,  :show   # colleague profile (reuses profile_card)
```

Both are inside `live_session :authenticated_on_shift` — off-shift users are
redirected to `/today` by the `:ensure_on_shift` on_mount hook (F.Profile.18).

### 5.2 `FoyerWeb.ProfileLive` — `/me`

#### mount/3 (keep cheap)
Assign `card: nil`, `rewards: []`, `page_title: "Me"`. No DB calls.

#### handle_params/3 (data load)
```elixir
def handle_params(_params, _uri, socket) do
  scope   = socket.assigns.current_scope
  profile = FoyerWeb.LiveDeps.profile()
  card    = profile.own_profile_for(scope.user)
  rewards = profile.rewards_catalog()

  {:noreply,
   socket
   |> assign(:card, card)
   |> assign(:rewards, rewards)}
end
```

#### render/1
Delegates to `FoyerComponents.profile_card/1` with `card={@card}`,
`rewards={@rewards}`, and `viewer={:self}` (a new atom attr — see §6).

The render template must include the desktop side-rail explicitly (confirmed from
code: `ProfileLive` already calls `FoyerComponents.desktop_rail/1` directly, matching
`TodayLive` and `HouseLive`). `Layouts.app/1` only renders the inner block and flash
group; it does not inject the rail.

### 5.3 `FoyerWeb.PeopleLive` — `:show` (delta from scaffold, v2)

**v2 change:** `apply_show/2` now calls `profile_for(target, scope.user)` and relies
on the context boundary to enforce F.Profile.6. No post-hoc `Enum.filter` in the
LiveView. The context returns a Card already stripped of private recognitions and the
given list.

```elixir
defp apply_show(socket, %{"id" => id}) do
  scope  = socket.assigns.current_scope
  target = FoyerWeb.LiveDeps.accounts().get_user!(id)
  # profile_for/2 enforces F.Profile.6 at the boundary: private recognitions
  # and the given list are stripped when viewer != subject.
  card   = FoyerWeb.LiveDeps.profile().profile_for(target, scope.user)

  {:noreply,
   socket
   |> assign(:card, card)
   |> assign(:page_title, target.name)}
rescue
  Ecto.NoResultsError ->
    {:noreply,
     socket
     |> put_flash(:error, "Unknown user.")
     |> push_navigate(to: ~p"/people")}
end
```

The `:rewards` assign for `profile_card` is omitted on the colleague view — the
component uses `default: []` for `:rewards`, so the catalog is suppressed without
explicit change. The `viewer` attr (`:self` vs `:other`) controls whether the "Given"
section and points breakdown render.

**Note on memberships (cross-group decision — see §11):** `apply_show/2` must also
call `FoyerWeb.LiveDeps.channels().list_for_user(target)` and assign the result to
`:memberships`. This is Channels-owned data and must NOT be loaded through
`Profile.Card`. The Channels group owns the membership pills in `PeopleLive :show`.

---

## 6. Mobile + desktop rendering plan

### 6.1 `FoyerComponents.profile_card/1` — updated component contract

New attrs:

| Attr | Type | Default | Purpose |
|------|------|---------|---------|
| `viewer` | `:atom` (`:self` or `:other`) | `:other` | Controls visibility of "Given" section and rewards catalog |
| `rewards` | `[RewardItem.t()]` | `[]` | Rewards catalog items; empty = catalog hidden |

Updated rendering logic:

1. **Identity header** (all viewers)
   - Large avatar (`foyer-avatar lg`) with initials
   - Name in `foyer-serif text-3xl`
   - Title in `foyer-mono`
   - Property code line (e.g. `LDN·MAY · Member since 2023`) — property code from
     application config; "Member since" derived from `user.inserted_at.year`
   - Languages: `EN · FR · YO` formatted with ` · ` separator
   - On-shift tag: `foyer-tag moss` with `foyer-pulse` when `card.on_shift?`

2. **Stats row** (all viewers)
   - Two-column grid
   - Tile 1: "Recognitions this month" / `card.received_this_month`
   - Tile 2: "Ack on time" / literal `—`

3. **Received section** (all viewers)
   - Section label `RECOGNITION RECEIVED`
   - Tab-like count badge (e.g. `2` in a pill) when the list is non-empty
   - Each recognition card: body in serif, sender avatar + name, house value tags
     (each value in a `foyer-tag outline`), bonus points badge (`foyer-tag forest`
     with `+N pts`), relative timestamp in `foyer-mono`
   - Empty state: "No recognitions yet" message

4. **Given section** (`:viewer == :self` only — F.Profile.7, F.Profile.8)
   - Section label `GIVEN` with count badge
   - Same recognition card layout as Received but showing recipient name
   - Hidden entirely when `viewer == :other`

5. **Points section** (all viewers for balance; breakdown only when `viewer == :self`)
   - `foyer-tag` with brass star glyph + "Foyer points · balance"
   - Balance: `foyer-serif text-3xl` with point total
   - Subtitle: "Earned through recognition. Trade for time, meals, the spa, or pass
     it on as a donation."
   - "How you earned them" disclosure list (`:viewer == :self`): renders
     `card.points_earned` list — each row shows sender initials avatar + body snippet
     + points amount. If list is empty, the disclosure is hidden.

6. **Rewards catalog** (`:viewer == :self` and `rewards != []` only — F.Profile.13,
   F.Profile.14, F.Profile.15)
   - Section label `TRADE YOUR POINTS`
   - Grid of reward items (2-column on mobile, up to 3-column on desktop)
   - Each item: icon rendered via `<.icon name={item.icon} class="size-5" />` (Heroicon
     name from `RewardItem.icon`), cost in `foyer-mono` (e.g. `75 pts`), title in
     `foyer-serif`, description line. **No Unicode glyphs.** Use Heroicon names such
     as `hero-sparkles`, `hero-clock`, `hero-gift`, `hero-heart` (v2 change).
   - Insufficient-points styling: when `item.cost > card.points`, apply
     `opacity-50` or `text-[var(--foyer-ink-soft)]` on the item (F.Profile.15)
   - **No redeem button.** A `foyer-mono` label reading "Coming soon" replaces any
     action (F.Profile.14)
   - Bottom note: "Redemptions are confirmed by your department head within 24 hours."
     rendered in `foyer-mono` with dimmed color

7. **Settings links** (`:viewer == :self`, mobile only — from `mobile-recognitions-received.html`)
   - Render as `<button type="button" aria-disabled="true">` styled with
     `foyer-btn ghost` — not `<a href="#">` which causes scroll/focus side-effects.
     These features are out of scope for v1. Include: Notifications & alerts,
     Languages & translation, Shift availability, Sign out. (v2 change from nit.)

### 6.2 Mobile (≤ 640 px)
Single-column `foyer-scroll` container. Fixed `foyer-bottom-nav` (Today / House /
Chat / Me) with `active={:me}`. Matches `mobile-recognitions-received.html`.

### 6.3 Desktop (≥ 768 px)

**v2 correction:** `Layouts.app/1` renders only the inner block and flash group — it
does NOT inject `FoyerComponents.desktop_rail/1` automatically. Both `ProfileLive`
and `PeopleLive :show` must include the rail directly in their templates, using the
same pattern as `TodayLive` and `HouseLive`:

```heex
<Layouts.app flash={@flash} current_scope={@current_scope}>
  <main class="foyer-shell">
    <FoyerComponents.desktop_rail active={:me} current_scope={@current_scope} />
    <div class="foyer-content">
      <div class="foyer-scroll md:max-w-xl md:mx-auto" id="profile">
        <FoyerComponents.profile_card card={@card} rewards={@rewards} viewer={:self} />
        <FoyerComponents.bottom_nav active={:me} current_scope={@current_scope} />
      </div>
    </div>
  </main>
</Layouts.app>
```

Bottom nav is hidden on desktop via `md:hidden` class applied inside
`FoyerComponents.bottom_nav/1`. Profile content column fills `max-w-xl` centered
main area (F.Profile.17). This is already confirmed in the scaffold: `ProfileLive`
calls `FoyerComponents.desktop_rail active={:me}` directly — the spec clause
F.Profile.17 requires verifying this wiring is complete.

---

## 7. Rewards catalog content source

**Decision: hard-coded module constant in `Foyer.Profile`.**

Rationale:
1. Rewards catalog content does not change between demo sessions — seeding it would
   add complexity (a migration, fixtures, and a schema) for data that is static POC
   content.
2. The designs show six to nine reward items with specific titles and point costs.
   These are fixed for the POC and change by code edit, not by data entry.
3. FOYER.md v1 explicitly defers redemption; the catalog is illustrative, not
   operational. Storing illustrative copy in a DB table adds no value until the
   redemption flow exists.
4. A `typed_struct` list is still typed and testable in isolation — the port callback
   `rewards_catalog/0` lets tests swap in a controlled list.

The module constant in `Foyer.Profile` uses Heroicon names (v2 change — no Unicode
glyphs per project icon guidance):

```elixir
@rewards_catalog [
  %RewardItem{icon: "hero-sparkles", title: "Staff meal at the Cellar Chef's tasting",
              description: "Any Tuesday", cost: 75},
  %RewardItem{icon: "hero-clock", title: "1 hour early dismissal",
              description: "Banked, redeemable any shift", cost: 100},
  %RewardItem{icon: "hero-heart", title: "Spa treatment",
              description: "60-min massage or facial", cost: 200},
  %RewardItem{icon: "hero-gift", title: "Donate to the staff fund",
              description: "Supports colleagues in need", cost: 100},
  %RewardItem{icon: "hero-sun", title: "One extra paid day off",
              description: "Use within six months", cost: 400},
  %RewardItem{icon: "hero-building-office", title: "A night at a sister property",
              description: "Linden Group · Europe", cost: 900}
]
```

Render with `<.icon name={item.icon} class="size-5" />`. Values match
`mobile-recognitions-received.html` catalog for titles and costs.

---

## 8. Test strategy

Per TESTING_GUIDE.md: isolated LiveView tests for UI state; route smoke tests for
wiring; unit tests for context logic.

### 8.1 Unit tests — `test/foyer/profile_test.exs`

- `profile_for/2` with viewer == subject: assert `Card.received` includes private
  recognitions (`public: false`) and `Card.given` is populated (use `@tag :integration`).
- `profile_for/2` with viewer != subject: assert `Card.received` contains only
  recognitions with `public: true`, and `Card.given` is `[]`. This is the critical
  boundary test for F.Profile.6. (v2 — was missing in original plan.)
- `own_profile_for/1` with a seeded user: assert `Card.received_this_month` count is
  correct (use `@tag :integration`).
- `received_this_month` calculation: inject recognitions spanning two months and pass
  an explicit `%Date{}` — assert only items from the given month are counted. Unit
  test, no DB. (v2 — explicit date arg makes the test deterministic.)
- `points_earned` filter: assert only recognitions with `bonus_points > 0` are
  included. Unit test, no DB.
- `rewards_catalog/0`: assert it returns a non-empty list of `RewardItem` structs with
  required fields. Pure unit test, instant.

### 8.2 Scenario modules — `test/support/scenarios/profile_scenarios.ex`

Define scenario modules implementing `Foyer.ProfilePort`:

```
ProfileScenarios.Empty        — user with no recognitions, 0 points
ProfileScenarios.LineStaff    — Maya: 2 received (1 public, 1 private), 1 given, 245 pts
ProfileScenarios.Manager      — Charlotte: 0 received, 2 given, 0 pts
ProfileScenarios.OffShift     — on_shift?: false (tests F.Profile.3, F.Profile.18)
```

Scenario modules for any collaborator contexts needed (e.g. `AccountsScenarios`
already exist or will be added by the Accounts group).

### 8.3 Isolated LiveView tests — `test/foyer_web/live/profile_live_test.exs`

Use `live_isolated/3` + `Mox.stub_with/2`. Cover:

| Test | Clause(s) |
|------|-----------|
| renders identity header with name, title, languages | F.Profile.1 |
| shows on-shift tag when on_shift? true | F.Profile.2 |
| hides on-shift tag when on_shift? false | F.Profile.3 |
| renders received recognition cards | F.Profile.4 |
| private recognition appears on own profile | F.Profile.5 |
| renders given section on own profile | F.Profile.7 |
| stats row shows received_this_month count | F.Profile.9 |
| stats row shows `—` for ack on time | F.Profile.10 |
| renders points balance | F.Profile.11 |
| renders points breakdown when points_earned non-empty | F.Profile.12 |
| renders rewards catalog items | F.Profile.13 |
| no redeem button on reward items, shows "Coming soon" | F.Profile.14 |
| reward items with cost > points show dimmed styling | F.Profile.15 |
| empty received state renders empty message | F.Profile.20 |
| house value tags render on recognition cards | F.Profile.21 |
| bonus points badge renders when bonus_points > 0 | F.Profile.22 |

### 8.4 PeopleLive isolated tests — `test/foyer_web/live/people_live_test.exs` (additions)

| Test | Clause(s) |
|------|-----------|
| colleague profile shows only public recognitions (boundary enforced by context) | F.Profile.6 |
| colleague profile hides Given section | F.Profile.8 |
| colleague profile hides rewards catalog | F.Profile.19 |

The F.Profile.6 test asserts on the rendered HTML, not on the `Card` struct — it
verifies the full stack from `profile_for/2` through the component. Assert by element
ID (e.g. `#recognition-<id>` absent) rather than broad text matching.

### 8.5 Route smoke tests — `test/foyer_web/smoke_test.exs` (additions)

Add assertions to the existing smoke test (or a new `profile_smoke_test.exs`):

- `/me` loads for an on-shift user, renders the name "Maya Okafor" and "Foyer points"
  (happy path, F.Profile.1, F.Profile.11). Assert by element ID where possible
  (e.g. `#stats-recognitions-this-month`).
- `/me` redirects an off-shift user to `/today` (F.Profile.18) — assert
  `{:error, {:redirect, %{to: "/today"}}}`.
- `/people/:id` loads for a valid colleague id and renders the colleague's name
  (F.Profile.19, F.Profile.6).

**Sandbox note (v2):** Route smoke tests that seed DB records are database-backed and
must be tagged `async: false`. Add a short comment explaining why: they share the
PostgreSQL sandbox and cannot run in parallel with other DB-touching tests.

---

## 9. Step-by-step execution order

1. **Add `RewardItem` typed_struct** — create `lib/foyer/profile/reward_item.ex`.

2. **Extend `Foyer.Profile.Card`** — add `received_this_month: integer()` and
   `points_earned: [Recognition.t()]` fields. Keep `enforce: true`.

3. **Update `Foyer.ProfilePort`** — replace `@callback profile_for(User.t()) :: Card.t()`
   with `@callback profile_for(User.t(), User.t()) :: Card.t()` and add
   `@callback own_profile_for(User.t()) :: Card.t()` and
   `@callback rewards_catalog() :: [RewardItem.t()]`. (v2 change.)

4. **Update `Foyer.Profile`** — implement `profile_for/2` (viewer-aware), `own_profile_for/1`,
   `build_card/2` private helper, `count_this_month/2` with explicit `Date.t()` arg, and
   `rewards_catalog/0` with `@rewards_catalog` module attribute. (v2 change.)

5. **Wire `LiveDeps` / config** — `rewards_catalog/0` is on the profile port so no
   new context accessor is needed. Verify `config/dev.exs` and `config/test.exs`
   point at `Foyer.Profile` and `Foyer.ProfileMock` respectively (already done by
   scaffold; confirm only).

6. **Add `Foyer.Profile.RewardItem` alias** to `Foyer.Profile.Card` module if needed;
   ensure `@type t` in Card is updated.

7. **Update `FoyerComponents.profile_card/1`** — add `viewer` attr (`:self` | `:other`,
   default `:other`); add `rewards` attr typed as `[Foyer.Profile.RewardItem.t()]` (or
   `:list` to avoid circular deps); implement the full rendering from §6.1 including:
   - property code + member-since line in the header
   - language formatting (`EN · FR · YO`)
   - stats row with `received_this_month`
   - recognition cards with house value tags, bonus points badge, relative timestamp
   - given section conditional on `viewer == :self`
   - points breakdown conditional on `viewer == :self`
   - rewards catalog with "Coming soon" and insufficient-points styling
   - settings links (coming soon, own profile only)

8. **Update `FoyerWeb.ProfileLive`** — call `own_profile_for(scope.user)` instead of
   `profile_for(scope.user)` in `handle_params/3`; pass `viewer={:self}` to
   `profile_card`; call `rewards_catalog/0`. Confirm `desktop_rail` is present in
   template (it already is per scaffold).

9. **Update `FoyerWeb.PeopleLive :show`** — call `profile_for(target, scope.user)`
   (v2: viewer-aware, no post-hoc filter); pass `viewer={:other}` (default). Do NOT
   remove the `memberships` assign that Channels adds — Profile and Channels both touch
   `apply_show/2`; coordinate.

10. **Write unit tests** — `test/foyer/profile_test.exs` per §8.1.

11. **Write scenario modules** — `test/support/scenarios/profile_scenarios.ex` per
    §8.2. Update `test/test_helper.exs` to add
    `Mox.defmock(Foyer.ProfileMock, for: Foyer.ProfilePort)` if not already present
    (confirm: scaffold may have added it already).

12. **Write isolated LiveView tests** — `test/foyer_web/live/profile_live_test.exs`
    per §8.3 and additions to `test/foyer_web/live/people_live_test.exs` per §8.4.

13. **Write / extend route smoke test** — assertions per §8.5.

14. **Run `mix format && mix credo --strict`** — fix any style issues.

15. **Run `mix dialyzer`** — fix any type warnings in the new Card fields and
    RewardItem struct.

16. **Run `mix test`** — all tests green.

---

## 10. Risks, trade-offs, and resolved decisions

### Risks

**R1 — `received_this_month` uses UTC for the month boundary.**
`count_this_month/2` accepts an explicit `Date.t()` (v2 fix). The caller passes
`Date.utc_today()`. For the POC this is acceptable; a real product would read the
property timezone from runtime config. Add a code comment noting the UTC assumption.

**R2 — Private recognitions at the boundary.**
v2 moves the F.Profile.6 filter into `profile_for/2`. The context unit test in §8.1
explicitly asserts non-recipient viewers receive `received: []` for private
recognitions. The Verify phase checks F.Profile.6 against the rendered page.

**R3 — `profile_for/2` makes two separate DB queries (received_by + given_by).**
For the POC with a small staff this is fine. If the list grows, a single joined query
would be better. Add a `# TODO: consider a single joined query` comment.

**R4 — Rewards catalog is hard-coded in the context.**
If product wants to A/B test catalog content, a DB-backed catalog would be needed.
For the POC this is correct — the plan explicitly argues for a module constant in §7.

### Trade-offs

**T1 — `viewer` atom vs separate component functions.**
An alternative is `profile_card_self/1` and `profile_card_other/1` as separate
components. The `viewer` attr approach is preferred because the layouts are ~90%
identical and keeping one component reduces template duplication.

**T2 — Property code from application config vs User schema.**
The User schema has no `property_code` or `property` column beyond the `department`
string. The design shows `LDN·MAY · Member since 2023`. In the POC there is one
property, so a config constant is correct. Adding a `property_code` column to User
is a future concern.

**T3 — Rewards catalog stored in `Foyer.Profile` not `ProfileLive`.**
The scaffold put `@rewards` in the LiveView. Moving it to the context is architecturally
cleaner (it is business data, not view configuration) and enables testing through the
port.

### Resolved decisions (v2 — from original OQs)

**OQ1 resolved — `/people/:own-id`:** No redirect for v1. When a viewer navigates to
their own `/people/:id` entry, `profile_for(subject, viewer)` will match the
`same-user` clause and build a full own-profile Card. The component will receive
`viewer={:other}` (no Given or rewards shown) because the URL is a colleague-profile
route. This is acceptable and slightly unusual; document as a v2 UX enhancement.

**OQ2 resolved — `points_earned` is bonus-point earnings only:** `points_earned` lists
recognitions where `bonus_points > 0` (manager-awarded bonus points only). It does NOT
fully explain `points_balance`, which is seeded directly on the user record and may
differ from the sum of `bonus_points` across recognitions. The UI label should say
"How you earned bonus points" or include a note. Do not imply this breakdown reconciles
with `points_balance`. The Recognitions group should implement base accrual in v2.

**OQ3 resolved — "Ack on time" denominator:** Render the `—` em-dash placeholder
only. No computation. This is correct for v1 per the spec (F.Profile.10).

**OQ4 resolved — `inserted_at` for timestamps:** Use `inserted_at` for relative
timestamp display ("Yesterday", "Wed 22 Apr"). No dedicated `sent_at` field. No code
change needed.

**OQ5 resolved — `Recognitions.received_by/1` stability:** Profile must NOT change
`received_by/1` to return public-only recognitions. Today's off-shift count query
depends on it returning all recognitions (including private) for the recipient. Today
should use a separate `Recognitions.private_received_since/2` helper if needed.

---

## 11. Cross-group dependencies

### Memberships in `PeopleLive :show` — Profile does NOT own this

The Channels group plan (§5.1) and `F.Channels.22` state that channel membership
pills on the colleague detail view (`/people/:id`) must be loaded via
`Channels.list_for_user/1` and must NOT come from `Foyer.Profile.Card` or accidental
preloads through `Profile.profile_for`.

**Decision (v2):** `Profile.Card` does not expose a `memberships` field. Profile is an
orchestrator of Accounts + Recognitions + Shifts data only. `PeopleLive :show` loads
memberships separately as a Channels-owned assign:

```elixir
# in apply_show/2 — Channels group adds this line; Profile must not remove it
memberships = FoyerWeb.LiveDeps.channels().list_for_user(target)
socket |> assign(:memberships, memberships)
```

This respects the cousin-calling discipline: `PeopleLive` is a shared surface that
both Profile and Channels contribute to, but each context loads only its own data.

**Coordination note:** Both the Profile and Channels groups edit `PeopleLive :show`.
Profile must not remove or hide any Channels-owned membership assign; Channels must not
widen `Profile.Card` without Profile's explicit agreement. The executing agent should
open `apply_show/2` once and include both the Profile assigns and the Channels
membership assign in the same update.

### `Recognitions.received_by/1` must remain public-and-private

Today depends on `Recognitions.received_by/1` returning all recognitions (including
private) so it can count private recognitions held for an off-shift user. Profile must
not change this function. The private-visibility rule lives in
`Foyer.Profile.profile_for/2` at the Profile context boundary.

### `ProfileMock` must be updated atomically

Changing `ProfilePort.profile_for/1` to `profile_for/2` means all existing
`ProfileMock` stubs, `Mox.stub_with/2` calls, and isolated LiveView tests across
Profile and Channels that mock `ProfilePort` must be updated in the same execution
window. The executing agent should grep for `ProfileMock` and `profile_for` across
`test/` before finishing.

---

### Scaffold stubs to finish

The following scaffold items are explicitly flagged as incomplete and are this group's
responsibility:

- `FoyerComponents.profile_card/1` — the stats row shows total received count, not
  current-month count. Fix: use `card.received_this_month`.
- `FoyerComponents.profile_card/1` — recognition cards have no house value tags,
  no relative timestamp, and no points badge (only a raw points number if > 0).
  Fix: implement per §6.1.
- `FoyerComponents.profile_card/1` — rewards catalog items are bare maps with only
  `:title` and `:cost`. Fix: migrate to `RewardItem` structs with glyph +
  description + coming-soon label.
- `FoyerWeb.ProfileLive` — `@rewards` is a module-level list of bare maps. Move to
  `Foyer.Profile.rewards_catalog/0`.
- `FoyerWeb.PeopleLive :show` — calls `profile_for(target)` with one arg; no
  visibility filtering. Fix: change to `profile_for(target, scope.user)` — the context
  boundary now handles F.Profile.6.
- `Foyer.Profile.Card` — missing `received_this_month` and `points_earned` fields.
- `Foyer.Profile` — `profile_for/1` does not populate new Card fields and uses an
  implicit `DateTime.utc_now()` call. Fix: implement `profile_for/2`, `own_profile_for/1`,
  and `count_this_month/2` with explicit `Date.t()` arg per §4.2.
- Property code (`LDN·MAY`) is hard-coded in the design but absent from the scaffold
  entirely. Fix: add an application config key and render in the identity header.
