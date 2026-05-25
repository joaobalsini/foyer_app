# Plan 01 — Today briefing

Status: revised after Codex review (v2)
Scope: Today feature group — briefing surface, shift start/end, off-shift gate, acknowledgement
flow, waiting counts, mobile rendering across all four design variants  
Spec: [`../spec.md`](../spec.md)
Review: [`01-today-briefing-review.md`](./01-today-briefing-review.md)

---

## Revision log

**v2 — addressed Codex review of 2026-05-25.** Key changes (see review doc for full rationale):

- **Stubbed helpers removed from execution steps.** Step 2 no longer adds stub implementations
  for `House.authored_by`, `House.unacked_since`, `Chat.unread_since`,
  `Recognitions.private_received_since`, and `Shifts.last_ended_shift_for`. These are real
  implementations owned by their respective feature groups. A new **Cross-group dependencies**
  section (§4.4) replaces the stub hand-wringing with a sequencing contract.
- **Shift-complete transient state fixed.** The plan no longer proposes setting a Plug session key
  from a LiveView event. Replaced with a query-param approach:
  `push_navigate(to: ~p"/today?state=shift_complete")` and consumption in `handle_params/3`.
- **Announcement route pinned.** The stale `/house/:id` language is removed. All links are pinned
  to `~p"/announcements/#{a.id}"` per the real router.
- **`recent_recognition` renamed to `recent_recognitions`** (plural) in the Briefing DTO, matching
  the list type, as a v2 delta.
- **Briefing DTO change fully spelled out** in §2 with `typed_struct` fields.
- **`Chat.unread_since/2` query contract defined** in §4.4 with the full exclusion rules.
- **`F.Today.14` constrained** to published announcements ordered newest-first (spec updated).
- **Spec gaps addressed:** F.Today.20 (unread message semantics) and F.Today.21 (handoff card
  quieter behaviour) added to the spec. The handoff "fades to background" clause is resolved as
  UI-only de-emphasis in v1 (no read-state schema).
- **Stable IDs** added for the channel picker and "Skip · clock out" control in §5.
- **Risks section** updated with sequencing dependency note.
- **Open questions resolved** in-line; the open-questions section below is retired.

---

## 1. Goal & non-goals

### Goal

Bring the Today surface from its scaffold stub into a fully-working briefing surface that satisfies
all nineteen spec clauses. Concretely:

- The four design variants (off-shift, on-shift staff, end-shift handoff, manager) all render their
  designed content from real data.
- The `Briefing` DTO carries accurate waiting counts broken down by announcement acks, unread
  messages, and private recognitions, not just a single opaque integer.
- Acknowledged announcements disappear from Today on the next surface load.
- The end-shift flow renders a channel picker so the user can target their handoff note.
- Recognition cards render with sender name, body, and house values.
- The route gate (`F.Today.2`) is exercised by an integration test.
- All four design variants have isolated tests with scenario modules.

### Non-goals (explicit)

- **No PubSub in v1.** Today does not subscribe to any topic. It refreshes on page load, shift
  start, shift end, and surface re-entry only. This is a deliberate product choice documented in
  `F.Today.15` and in FOYER.md v1/Today. Adding PubSub requires changes to this plan.
- **Today is read-only except for shift start/end and acknowledgement navigation.** Composing
  announcements, giving recognition, or sending messages are write paths that belong to their own
  feature groups; Today only navigates to those surfaces.
- **Shift scheduling.** Foyer does not infer shifts from a schedule. One open shift per user,
  controlled by the worker.
- **Notification delivery rules.** Waiting counts are displayed; actual queued delivery is a v2
  concern.
- **Desktop layout variants.** The scaffold renders Today at all widths with the mobile bottom-nav;
  a desktop side-rail variant for Today is out of scope for this plan.

---

## 2. Schemas

Today owns no new Ecto schemas. All data comes from schemas defined by Shifts, House, Recognitions,
and Chat.

### Foyer.Today.Briefing (existing DTO, v2 field changes)

Current scaffold definition at `lib/foyer/today/briefing.ex`:

```
field :user,               User.t()
field :shift,              Shift.t() | nil
field :on_shift?,          boolean()
field :handoff,            Shift.t() | nil
field :needs_ack,          [Announcement.t()]
field :recent_recognition, [Recognition.t()]
field :waiting_count,      non_neg_integer()
```

**v2 delta** (driven by `F.Today.1`, `F.Today.16`, and the Codex review):

Replace the single `waiting_count` integer with three granular fields and keep a derived total for
the off-shift summary line. Rename `recent_recognition` (singular) to `recent_recognitions`
(plural, breaking change — update all callers and templates). Add `own_announcements` for the
manager live-posts section. The full v2 typed_struct definition:

```elixir
defmodule Foyer.Today.Briefing do
  @moduledoc """
  Aggregated morning-briefing read-model. Returned by `Foyer.Today.brief_for/1`.
  Typed DTO (per ARCHITECTURE.md "no bare maps").
  """
  use TypedStruct

  alias Foyer.Accounts.User
  alias Foyer.House.Announcement
  alias Foyer.Recognitions.Recognition
  alias Foyer.Shifts.Shift

  typedstruct enforce: true do
    field :user,                  User.t()
    field :shift,                 Shift.t() | nil
    field :on_shift?,             boolean()
    field :handoff,               Shift.t() | nil
    field :needs_ack,             [Announcement.t()]
    field :recent_recognitions,   [Recognition.t()]
    field :own_announcements,     [Announcement.t()]
    field :waiting_announcements, non_neg_integer()
    field :waiting_messages,      non_neg_integer()
    field :waiting_recognitions,  non_neg_integer()
    field :last_shift_ended_at,   DateTime.t() | nil
  end

  @spec waiting_total(t()) :: non_neg_integer()
  def waiting_total(%__MODULE__{} = b),
    do: b.waiting_announcements + b.waiting_messages + b.waiting_recognitions
end
```

Field notes:
- `recent_recognitions` — renamed from `recent_recognition`; list of up to three recognitions
  received by the user, preloaded with `:sender`. On-shift only; `[]` when off-shift.
- `own_announcements` — manager's own published announcements (non-nil `published_at`), ordered
  `published_at desc`. `[]` for staff and for managers who have no published posts.
- `waiting_announcements` — count of unacknowledged ack obligations since `last_shift_ended_at`.
- `waiting_messages` — count of unread messages since `last_shift_ended_at`; excludes messages
  authored by the user (see F.Today.20 and §4.4 for the full contract).
- `waiting_recognitions` — count of private recognitions received since `last_shift_ended_at`.
- `last_shift_ended_at` — anchor for all three waiting counts; nil if the user has never ended
  a shift (counts are then all-time).

The template calls `Briefing.waiting_total(@briefing)` instead of `@briefing.waiting_count`.
`waiting_count` is removed from the struct.

---

## 3. Migrations

None. All required tables already exist from the scaffold migrations. The Briefing changes are
DTO-only.

---

## 4. Context API

### 4.1 Foyer.Today (primary changes)

`lib/foyer/today.ex` and `lib/foyer/today/briefing.ex`.

```elixir
@spec brief_for(User.t()) :: Briefing.t()
def brief_for(%User{} = user) do
  shift               = Shifts.current_shift_for(user)
  on_shift?           = not is_nil(shift)
  needs_ack           = if on_shift?, do: House.needs_ack_from(user), else: []
  handoff             = if on_shift?, do: Shifts.last_handoff_for(user), else: nil
  recent_recognitions = if on_shift?, do: Recognitions.received_by(user) |> Enum.take(3), else: []
  own_announcements   = if on_shift? and manager?(user),
                          do: House.authored_by(user),
                          else: []

  last_shift_ended_at =
    case Shifts.last_ended_shift_for(user) do
      nil -> nil
      s   -> s.ended_at
    end

  {w_ann, w_msg, w_rec} =
    if on_shift?,
      do: {0, 0, 0},
      else: waiting_counts(user, last_shift_ended_at)

  %Briefing{
    user: user,
    shift: shift,
    on_shift?: on_shift?,
    handoff: handoff,
    needs_ack: needs_ack,
    recent_recognitions: recent_recognitions,
    own_announcements: own_announcements,
    waiting_announcements: w_ann,
    waiting_messages: w_msg,
    waiting_recognitions: w_rec,
    last_shift_ended_at: last_shift_ended_at
  }
end
```

The `waiting_counts/2` private helper delegates to the three cousin contexts:

```elixir
@spec waiting_counts(User.t(), DateTime.t() | nil) ::
        {non_neg_integer(), non_neg_integer(), non_neg_integer()}
defp waiting_counts(user, since) do
  ann = House.unacked_since(user, since)
  msg = Chat.unread_since(user, since)
  rec = Recognitions.private_received_since(user, since)
  {ann, msg, rec}
end
```

`Today` is the only context permitted to call cousins — see §10 for the trade-off discussion.

### 4.2 Port change: Foyer.TodayPort

`lib/foyer/today_port.ex` — no change to callback signature. The port stays:

```elixir
@callback brief_for(User.t()) :: Briefing.t()
```

The richer Briefing struct is still the return type; Dialyzer will catch any test scenario that
returns an old-shape struct.

### 4.3 Delta helpers required from cousin contexts

These functions are new additions **owned by those feature groups' contexts**, not by Today. Today
calls them; this plan documents their exact signatures as a contract. The isolated tests use
Today scenario modules that return fixed counts (real data is not needed for unit/isolated tests).
See §4.4 for the cross-group dependency and sequencing declaration.

#### Foyer.House — additions (`lib/foyer/house.ex` + `lib/foyer/house_port.ex`)

```elixir
@callback authored_by(User.t()) :: [Announcement.t()]
# Returns published announcements (published_at IS NOT NULL) authored by the given user,
# ordered published_at desc. Used by manager variant of Today (F.Today.14).
@spec authored_by(User.t()) :: [Announcement.t()]

@callback unacked_since(User.t(), DateTime.t() | nil) :: non_neg_integer()
# Returns the count of announcements requiring acknowledgement (requires_ack: true) from the user
# that were published after `since` (or all-time if since is nil) and not yet acknowledged.
@spec unacked_since(User.t(), DateTime.t() | nil) :: non_neg_integer()
```

#### Foyer.Chat — additions (`lib/foyer/chat.ex` + `lib/foyer/chat_port.ex`)

```elixir
@callback unread_since(User.t(), DateTime.t() | nil) :: non_neg_integer()
# Returns the count of chat messages satisfying all of:
#   - message.author_id != user.id  (excludes own messages)
#   - message.inserted_at > since, or all-time if since is nil
#   - user is a direct participant in the conversation (via conversation_participants)
#     OR a member of the channel conversation (via channel_memberships)
#   - no chat_message_reads row exists for (message_id, user_id)
# Required indexes: chat_messages(conversation_id, inserted_at),
#   chat_message_reads(user_id), conversation_participants(user_id, conversation_id),
#   channel_memberships(user_id, channel_id) — all exist from scaffold migrations.
@spec unread_since(User.t(), DateTime.t() | nil) :: non_neg_integer()
```

#### Foyer.Recognitions — additions (`lib/foyer/recognitions.ex` + `lib/foyer/recognitions_port.ex`)

```elixir
@callback private_received_since(User.t(), DateTime.t() | nil) :: non_neg_integer()
# Returns the count of private (public: false) recognitions where recipient_id = user.id,
# inserted_at > since (or all-time if since is nil).
@spec private_received_since(User.t(), DateTime.t() | nil) :: non_neg_integer()
```

#### Foyer.Shifts — additions (`lib/foyer/shifts.ex` + `lib/foyer/shifts_port.ex`)

```elixir
@callback last_ended_shift_for(User.t()) :: Shift.t() | nil
# Returns the most recent shift for the user that has ended_at set (ended_at IS NOT NULL),
# ordered ended_at desc, limit 1.
# Used to anchor waiting counts for the off-shift view.
# Backed by index(:shifts, [:user_id, :ended_at]) (exists from scaffold migrations).
@spec last_ended_shift_for(User.t()) :: Shift.t() | nil
```

### 4.4 Cross-group dependencies

Today depends on the following helpers being delivered by their owning feature groups **before**
Today's step 7 (integration smoke test) can be verified against real data:

| Helper | Owning group | Signature |
|---|---|---|
| `House.authored_by/1` | House | `(User.t()) :: [Announcement.t()]` |
| `House.unacked_since/2` | House | `(User.t(), DateTime.t() \| nil) :: non_neg_integer()` |
| `Chat.unread_since/2` | Chat | `(User.t(), DateTime.t() \| nil) :: non_neg_integer()` |
| `Recognitions.private_received_since/2` | Recognitions | `(User.t(), DateTime.t() \| nil) :: non_neg_integer()` |
| `Shifts.last_ended_shift_for/1` | Shifts | `(User.t()) :: Shift.t() \| nil` |

Today does not own the query internals for these helpers; it only orchestrates them. Each owning
group must add unit tests for their implementation. Today's isolated tests stub these via
`Mox.stub_with/2` against scenario modules, so isolated tests can run without the owning group
having landed yet.

---

## 5. LiveView

### Route (no change)

The scaffold already defines:

```
live "/today",           TodayLive, :index
live "/today/end-shift", TodayLive, :end_shift
```

Both live inside `live_session :authenticated_today` with `on_mount: :ensure_authenticated`.

### mount/3

No change from scaffold: assigns `briefing: nil, end_shift_form: nil, page_title: "Today"`.
No database calls in mount — keeps the double-render cheap.

### handle_params/3 changes

Current scaffold loads `brief_for` for both `:index` and `:end_shift` actions. Extend to:

- For `:end_shift`: also load `channels = LiveDeps.channels().list_for_user(scope.user)` and
  assign `channel_options = Enum.map(channels, &{&1.name, &1.id})` so the handoff channel picker
  is populated. The scaffold currently omits this picker; the design shows it.
- For `:index`: consume the `state=shift_complete` query param to set `just_clocked_out: true`
  (see shift-complete transient state below).

```elixir
def handle_params(params, _uri, socket) do
  scope    = socket.assigns.current_scope
  briefing = FoyerWeb.LiveDeps.today().brief_for(scope.user)

  socket =
    socket
    |> assign(:briefing, briefing)
    |> assign(:just_clocked_out, params["state"] == "shift_complete")
    |> maybe_assign_end_shift_form(scope)

  {:noreply, socket}
end

defp maybe_assign_end_shift_form(%{assigns: %{live_action: :end_shift}} = socket, scope) do
  channels        = FoyerWeb.LiveDeps.channels().list_for_user(scope.user)
  channel_options = Enum.map(channels, &{&1.name, &1.id})

  socket
  |> assign(:end_shift_form, build_end_shift_form())
  |> assign(:channel_options, channel_options)
end

defp maybe_assign_end_shift_form(socket, _scope), do: socket
```

### handle_event/3

Three events:

**`"start_shift"`** (existing, no change needed)

```elixir
def handle_event("start_shift", _params, socket) do
  scope = socket.assigns.current_scope
  case FoyerWeb.LiveDeps.shifts().start_shift(scope.user) do
    {:ok, _shift} ->
      {:noreply, socket |> put_flash(:info, "Shift started.") |> push_navigate(to: ~p"/today")}
    {:error, _cs} ->
      {:noreply, put_flash(socket, :error, "Could not start shift.")}
  end
end
```

**`"end_shift_submit"`** (extend to include channel selection and shift-complete navigation)

The scaffold currently accepts `%{"shift" => attrs}` but the form does not include a channel picker.
Add `handoff_channel_id` to the form inputs. On success, navigate with the `state=shift_complete`
query param so `handle_params/3` can set `just_clocked_out: true` on the first load:

```elixir
def handle_event("end_shift_submit", %{"shift" => attrs}, socket) do
  scope = socket.assigns.current_scope
  case FoyerWeb.LiveDeps.shifts().end_shift(scope.shift, attrs) do
    {:ok, _shift} ->
      {:noreply,
       socket
       |> put_flash(:info, "Shift ended. Rest well.")
       |> push_navigate(to: ~p"/today?state=shift_complete")}
    {:error, cs} ->
      {:noreply, assign(socket, :end_shift_form, to_form(cs))}
  end
end
```

A page refresh after the shift-complete first load renders the normal off-shift banner because
`params["state"]` will be absent (the browser strips query params on reload unless re-supplied).

**`"acknowledge"`** (new — inline ack from Today, `F.Today.5` / `F.Today.6`)

The design shows a "READ IN FULL →" link on needs-ack items that navigates to the announcement
detail. Acknowledgement itself happens on the detail page. No `"acknowledge"` event is needed on
TodayLive. However, when the user returns to `/today` after acknowledging, `handle_params/3`
reloads the briefing and the item is gone. This satisfies `F.Today.6` without adding a new event.

### Off-shift gate

Implemented by `UserAuth.on_mount(:ensure_on_shift)` in the `:authenticated_on_shift` live_session.
No changes needed to the gate itself. `F.Today.2` is tested at the smoke-test level.

### Template changes

The scaffold template already covers the three `cond` branches (off-shift / manager / staff). The
following gaps need filling:

1. **Waiting-count line**: replace `@briefing.waiting_count` with
   `Briefing.waiting_total(@briefing)` and add the `Foyer.Today.Briefing` alias in the template.
   Show a breakdown below the total ("X announcements · Y messages · Z recognitions") to match
   the off-shift design detail.

2. **Handoff channel picker in end-shift form**: add a `<.input>` of type `select` for
   `handoff_channel_id` using `@channel_options`, with a stable `id="handoff-channel-select"`.
   The scaffold currently renders only a `handoff_note` textarea. Also add a "Skip · clock out"
   link with `id="skip-clock-out"` so the spec interaction is testable.

3. **Recognition cards**: the scaffold's `on-shift-staff` section ends after the needs-ack list but
   does not render `@briefing.recent_recognitions`. Add a recognition section per `F.Today.4` and
   `F.Today.18`:

   ```heex
   <div :if={@briefing.recent_recognitions != []} id="recent-recognition">
     <div class="foyer-mono">Recognition for you</div>
     <div
       :for={r <- @briefing.recent_recognitions}
       id={"recognition-#{r.id}"}
       class="rounded-lg border p-3 mt-2"
       style="border-color: var(--foyer-rule);"
     >
       <div class="flex items-center gap-2">
         <FoyerComponents.avatar initials={r.sender.initials} size={:sm} />
         <span class="foyer-mono">{r.sender.name}</span>
       </div>
       <p class="foyer-serif mt-2">{r.body}</p>
       <div class="flex gap-1 mt-2">
         <span :for={v <- r.values} class="foyer-tag outline">{v}</span>
       </div>
     </div>
   </div>
   ```

4. **Manager live posts section**: add below needs-ack in the manager branch. Links use
   `~p"/announcements/#{a.id}"` (the real router route — not `/house/:id`):

   ```heex
   <div :if={@briefing.own_announcements != []} id="manager-live-posts">
     <div class="foyer-mono">Your live posts</div>
     <.link
       :for={a <- @briefing.own_announcements}
       navigate={~p"/announcements/#{a.id}"}
       id={"live-post-#{a.id}"}
       class="block rounded-lg border p-3 mt-2"
       style="border-color: var(--foyer-rule);"
     >
       <span :if={a.pinned_at} class="foyer-tag claret">Pinned</span>
       <div class="foyer-serif mt-1">{a.title}</div>
     </.link>
   </div>
   ```

5. **Needs-ack item links**: all needs-ack item links must use `~p"/announcements/#{a.id}"` (not
   `/house/:id`). The `id` attribute on each link must be `id={"needs-ack-#{a.id}"}` for
   testability (per F.Today.5).

6. **End-shift summary (shift-complete variant)**: the `mobile-shift-complete-handoff.html` design
   shows a "Shift complete" confirmation with "Announcements acked", "Recognition received", and
   "What happens next" copy. This variant is shown immediately after clocking out. Implementation:
   the `just_clocked_out` assign (set by `handle_params/3` when `params["state"] == "shift_complete"`)
   gates an alternate off-shift banner. The shift-complete copy ("Eight hours well held.",
   "Notifications will quiet down.") replaces the normal off-shift copy on that first load only.
   A page refresh without the query param shows the normal off-shift banner.

   ```heex
   <div :if={not @briefing.on_shift?}>
     <%= if @just_clocked_out do %>
       <%# shift-complete variant %>
       <div id="shift-complete-banner">
         <div class="foyer-tag moss">Shift complete</div>
         <h2 class="foyer-serif text-2xl mt-2">Eight hours well held.</h2>
         <p class="foyer-mono mt-1">Notifications will quiet down.</p>
       </div>
     <% else %>
       <%# normal off-shift banner %>
       <div id="off-shift-banner">
         ...
       </div>
     <% end %>
   </div>
   ```

---

## 6. Off-shift gate behaviour

The gate is implemented at the `live_session` layer, not inside TodayLive itself:

```
live_session :authenticated_on_shift,
  on_mount: [{FoyerWeb.UserAuth, :ensure_on_shift}] do
  live "/house", HouseLive, :index
  live "/announcements/new", AnnouncementLive, :new
  live "/announcements/:id", AnnouncementLive, :show
  ...
end
```

`UserAuth.on_mount(:ensure_on_shift)` checks `scope.on_shift?`. If false, it halts with
`redirect(to: ~p"/today")`. The result is `{:error, {:redirect, %{to: "/today"}}}` when the
surface is accessed via `live(conn, path)` in a test.

Today itself is in `:authenticated_today`, which requires authentication but not an open shift.
This means off-shift users land on Today and cannot leave until they start a shift — the product
boundary described in FOYER.md.

The bottom-nav renders House/Chat/Me navigation as disabled (grayed out, `pointer-events-none`)
when `scope.on_shift?` is false, per the scaffold's `FoyerComponents.bottom_nav`. This prevents
tap-through before the route guard fires.

---

## 7. Mobile-first rendering plan

Four design variants and their mapping to LiveView states:

| Design file | LiveView state | Rendered when |
|---|---|---|
| `mobile-off-shift-before.html` | off-shift | `not @current_scope.on_shift?` branch of the `cond` |
| `mobile-on-shift.html` | on-shift staff | `true` (default) branch of the `cond` |
| `mobile-manager-today.html` | on-shift manager | `Scope.manager?(@current_scope)` branch |
| `mobile-shift-complete-handoff.html` | off-shift immediately after clock-out | off-shift branch with `@just_clocked_out` assign (set from `?state=shift_complete` param) |

**Mobile-first rules for the implementation pass:**

- The outermost container uses `foyer-root` (`min-height: 100vh; padding-bottom: 5rem`). This
  pads for the sticky bottom-nav.
- Cards use `rounded-lg border p-3` with `border-color: var(--foyer-rule)` inline style (or a
  Tailwind utility equivalent once the Tailwind theme is extended).
- Tap targets: every interactive element inside the needs-ack list and recognition cards must be
  at least 44 px tall. Use `min-h-[44px]` on the link wrapper if the card would otherwise be
  shorter than 44 px.
- The handoff channel picker in the end-shift form must be a native `<select>` element (using
  `<.input type="select">`) on mobile to get the OS picker behaviour.
- No horizontal overflow: avoid fixed-width containers; use `w-full` on cards and sections.
- The bottom navigation is `fixed bottom-0 w-full md:hidden`. Per scaffold §7 and §8, the
  `FoyerComponents.bottom_nav` already implements this. TodayLive uses it unchanged.

---

## 8. Test strategy

Per `docs/TESTING_GUIDE.md`: isolated tests for UI states, route smoke tests for wiring.

### 8.1 Scenario modules

Create under `test/support/scenarios/today/`. Each module implements `Foyer.TodayPort`:

| Module | Scenario |
|---|---|
| `Today.Scenarios.OffShift` | off-shift user, no prior shifts, waiting counts all zero |
| `Today.Scenarios.OffShiftWithWaiting` | off-shift user, 3 announcements + 2 messages + 1 private rec waiting |
| `Today.Scenarios.OnShiftStaff` | on-shift staff, handoff present, 1 needs-ack, 2 recognitions |
| `Today.Scenarios.OnShiftNoHandoff` | on-shift staff, no handoff, 0 needs-ack, 0 recognitions |
| `Today.Scenarios.OnShiftAllAcked` | on-shift staff, needs-ack list empty |
| `Today.Scenarios.OnShiftManager` | on-shift manager, 1 needs-ack, 2 live posts |
| `Today.Scenarios.AfterClockOut` | off-shift, `just_clocked_out: true`, shift-complete variant |

Each scenario returns a `%Foyer.Today.Briefing{}` with the relevant shape. The `@behaviour
Foyer.TodayPort` annotation catches any struct-shape drift at compile time.

### 8.2 Isolated LiveView tests (`test/foyer_web/live/today_live_test.exs`)

For each spec clause that has observable UI state, one `test` block using `live_isolated/3` +
`Mox.stub_with/2`. Pin the clause number in the test name:

- `F.Today.1` — off-shift banner: assert tag "Off shift · notifications paused", button "Start
  shift", and waiting line are all present; assert "Needs your acknowledgement" section absent.
- `F.Today.3` — start_shift event: `render_click(view, "#start-shift-btn")`, assert
  `push_navigate` redirects to `/today`.
- `F.Today.4` — on-shift content order: assert handoff card precedes needs-ack section which
  precedes recognition cards; use DOM selector ordering assertions.
- `F.Today.6 / F.Today.7` — empty needs-ack: use `OnShiftAllAcked` scenario, assert
  `#needs-ack` absent.
- `F.Today.8` — handoff card content: assert sender name, ended-at time, and note text appear.
- `F.Today.9` — no handoff: use `OnShiftNoHandoff`, assert `#handoff-card` absent.
- `F.Today.10 / F.Today.11` — end-shift form: navigate to `:end_shift` action, assert textarea,
  channel picker (`#handoff-channel-select`), and skip link (`#skip-clock-out`) present.
- `F.Today.13` — manager CTA: use `OnShiftManager`, assert `#compose-cta` present.
- `F.Today.14` — manager live posts: use `OnShiftManager`, assert `#manager-live-posts` present.
- `F.Today.17` — mobile rendering: assert no element with `overflow-x: scroll` or explicit
  fixed width > 390 px in the rendered HTML.
- `F.Today.18` / `F.Today.19` — recognition cards: assert recognition body text present /
  absent based on scenario. Field name in scenario struct: `recent_recognitions` (plural).

### 8.3 Route smoke tests (`test/foyer_web/scaffold_smoke_test.exs` or a new `today_smoke_test.exs`)

These use `live(conn, path)` against the real router and real seeded data:

- `F.Today.2` — off-shift gate: pick Maya (on shift in seeds), end her shift, then attempt
  `live(conn, ~p"/house")`, assert `{:error, {:redirect, %{to: "/today"}}}`.
- Happy path: pick Maya (on shift), assert Today loads with her handoff card and the allergy
  protocol in the needs-ack list.
- Happy path: pick Charlotte (manager), assert Today loads with the manager CTA.

### 8.4 Context unit tests (`test/foyer/today_test.exs`)

- Test `Foyer.Today.brief_for/1` returns a `%Briefing{}` with correct field shapes when called
  with mocked cousins (or a minimal test DB setup via sandbox).
- Test `Briefing.waiting_total/1` correctly sums the three waiting fields.

### 8.5 Delta context tests (owned by those feature groups)

`House.authored_by/1`, `House.unacked_since/2`, `Chat.unread_since/2`,
`Recognitions.private_received_since/2`, `Shifts.last_ended_shift_for/1` — each of those groups
should add a unit test for their new function. Today's plan does not own these tests; it only
documents the dependency.

---

## 9. Step-by-step execution order

1. **Update `Foyer.Today.Briefing`** (`lib/foyer/today/briefing.ex`): replace `waiting_count`
   with `waiting_announcements`, `waiting_messages`, `waiting_recognitions`,
   `last_shift_ended_at`, and `own_announcements`. Add `Briefing.waiting_total/1`.

2. **Add port callbacks** for the five delta functions on House, Chat, Recognitions, and Shifts
   (their `_port.ex` files). The real implementations are owned by those feature groups (see §4.4);
   do not add stub implementations. The Mox mocks in tests will satisfy the callbacks.

3. **Add Mox mock stubs** in `test/test_helper.exs` for the new callbacks on the four port mocks
   (they already exist as `Mox.defmock` calls; verify the new callbacks are declared).

4. **Update `Foyer.Today.brief_for/1`** (`lib/foyer/today.ex`) to call the new delta helpers and
   populate the new Briefing fields. Guard with `if on_shift?` to keep the off-shift path cheap.

5. **Update `FoyerWeb.TodayLive.handle_params/3`**: add channel loading for `:end_shift` action;
   assign `channel_options`.

6. **Update TodayLive template**:
   - Replace `@briefing.waiting_count` with `Briefing.waiting_total(@briefing)`.
   - Add recognition cards section to the staff branch.
   - Add manager live-posts section to the manager branch.
   - Add handoff channel picker to the end-shift form.
   - Add shift-complete transient state handling (`just_clocked_out` assign).

7. **Write scenario modules** under `test/support/scenarios/today/` (all seven from §8.1).

8. **Write isolated LiveView tests** pinned to spec clauses (`test/foyer_web/live/today_live_test.exs`).

9. **Write / extend smoke tests** for `F.Today.2` off-shift gate and the two happy-path routes.

10. **Write context unit test** for `Foyer.Today.brief_for/1` and `Briefing.waiting_total/1`.

11. **Run** `mix test`, `mix format`, `mix credo --strict`, `mix dialyzer`. Fix any failures.

12. **Verify against the four design files**: walk through each design variant manually (or via
    `mix phx.server`) and confirm the rendered output matches the designs.

---

## 10. Risks, trade-offs, and resolved decisions

### Cousin-calling trade-off (resolved)

`Foyer.Today` calls `Foyer.Shifts`, `Foyer.House`, `Foyer.Recognitions`, and `Foyer.Chat` — four
cousins. ARCHITECTURE.md's "no cousin calls" rule is intentionally relaxed here because:

- Pushing the aggregation into TodayLive would violate "fat contexts, slim LiveViews" more badly.
- The risk of Today becoming a god context is bounded by keeping it **strictly read-only**. Today
  has no write functions. Every write flows to the owning context from the LiveView event handler.
- This trade-off is documented in scaffold plan §6.8 and acknowledged there explicitly.

If Today ever needs to write (e.g. inline-ack from the briefing without navigating to the detail
page), that write should be added to `House.acknowledge/2` called directly from TodayLive, not
routed through `Foyer.Today`.

### No-PubSub boundary (resolved — deferred to v2)

Deliberately deferred. If a future agent adds PubSub, they must:
- Subscribe in `mount/3` to the user's channel topics.
- Handle `%{event: "announcement_acked"}` and update `briefing.needs_ack` via `update/2`.
- Add `terminate/2` to unsubscribe.
- Add a PubSub test (async: false, with a documented reason).

The no-PubSub choice is explicit in `F.Today.15` and should not be silently reversed.

### waiting_count: single integer vs breakdown (resolved)

Replaced with three granular fields (`waiting_announcements`, `waiting_messages`,
`waiting_recognitions`) and a derived `Briefing.waiting_total/1` helper. This is a breaking change
to the Briefing DTO. Both the `brief_for/1` function and the template `@briefing.waiting_count`
reference must be updated in steps 1 and 6.

### Shift-complete variant (resolved)

Use query-param-based transient state: `push_navigate(to: ~p"/today?state=shift_complete")`.
`handle_params/3` assigns `just_clocked_out: params["state"] == "shift_complete"`. A page refresh
without the param shows the normal off-shift banner. No session key mutation from a LiveView event;
no separate route needed for v1.

### Announcements route (resolved)

All announcement detail links in TodayLive use `~p"/announcements/#{a.id}"` — the real router
route. The stale `/house/:id` reference from an earlier draft is removed.

### Sequencing risk

Execution must be sequenced after Channels/House/Chat/Recognitions/Shifts plans deliver the listed
helpers (`House.authored_by/1`, `House.unacked_since/2`, `Chat.unread_since/2`,
`Recognitions.private_received_since/2`, `Shifts.last_ended_shift_for/1`). Today's isolated tests
can run at any time via Mox. The integration smoke test (step 9) requires the real helpers to be
present.

### Verify checklist hooks

The plan must satisfy the WORKFLOW.md verify checklist:

- **Mobile responsiveness**: §7 and `F.Today.17` test covers this.
- **Accessibility**: ARIA label on the "Start shift" button (`aria-label="Start shift"`); the
  needs-ack links have visible text labels; the channel picker has a `label` element via `<.input>`.
- **N+1 queries**: `brief_for/1` makes at most five queries (one per cousin call). None of those
  walk associations in a loop. The `needs_ack` preload includes `:author, :channel`. The
  `recent_recognitions` preload includes `:sender`. Verify with `Ecto.Repo` telemetry logging.
- **Database indexes**: all queries used by `brief_for/1` rely on existing scaffold indexes
  (`shifts_one_open_shift_per_user`, `index(:shifts, [:handoff_channel_id, :ended_at])`,
  `index(:announcements, [:channel_id, :pinned_at, :published_at])`). The new
  `last_ended_shift_for/1` query uses `index(:shifts, [:user_id, :ended_at])`. No new migrations
  needed.
- **Telemetry**: Today's write events (start_shift, end_shift) are handled by Shifts context which
  should emit a telemetry span. Add `:telemetry.execute/3` calls in `Foyer.Shifts.start_shift/1`
  and `end_shift/2` if not already present.
