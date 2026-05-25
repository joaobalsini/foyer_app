# Review — Plan 01 Profile feature group

## Verdict

Revise

The plan covers the right surface area, but privacy enforcement, desktop shell assumptions, and time-dependent stats need correction before execution.

## Strengths

- The plan keeps Profile read-only, which matches FOYER.md v1 and the Profile spec.
- Moving the rewards catalog out of `ProfileLive` and behind `ProfilePort` is aligned with fat contexts / slim LiveViews.
- Adding `received_this_month` and `points_earned` to `Foyer.Profile.Card` addresses real scaffold gaps.
- The plan correctly identifies that current `PeopleLive :show` passes the unfiltered card directly to `profile_card`.

## Critical Issues

### §5.3 Private Recognition Filtering Belongs At The Boundary, Not As A Caller Patch

Risk: The plan builds a full `%Profile.Card{}` for the target user, including private recognitions, then asks `PeopleLive` to filter `card.received` before assigning it. That can satisfy the immediate template, but it leaves the public/colleague privacy rule as a convention every caller must remember. `F.Profile.6` is a product privacy boundary, not a display preference.

Fix: encode viewer-aware visibility in the Profile API:

```elixir
@callback profile_for(subject :: User.t(), viewer :: User.t()) :: Card.t()
@callback own_profile_for(User.t()) :: Card.t()
```

Recommended implementation:

```elixir
def profile_for(%User{id: id} = subject, %User{id: id}) do
  build_card(subject, viewer: :self)
end

def profile_for(%User{} = subject, %User{} = _viewer) do
  subject
  |> build_card(viewer: :other)
  |> then(fn card -> %{card | received: Enum.filter(card.received, & &1.public), given: []} end)
end
```

Then `ProfileLive` calls `profile_for(scope.user, scope.user)`, and `PeopleLive :show` calls `profile_for(target, current_scope.user)`. The component can still use `viewer={:self | :other}`, but the data boundary must not expose private recognitions accidentally.

### §6.3 Incorrectly Claims The Desktop Side-Rail Comes From `Layouts.app`

Bug: The current `Layouts.app/1` only renders the inner block and flash group. It does not render `FoyerComponents.desktop_rail/1`. Existing surfaces that have a rail call the component themselves. The plan says the Profile desktop side-rail is "from `Layouts.app`", so executing only the described `ProfileLive` changes will not satisfy `F.Profile.17`.

Fix: update `ProfileLive` and `PeopleLive :show` to render the same shell pattern used by `TodayLive` and `HouseLive`:

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

### §4.2 `received_this_month` Is Time-Dependent And Hard To Test Reliably

Risk: `count_this_month/1` calls `DateTime.utc_now()` directly. Tests that create recognitions near a month boundary or run under property-local expectations will be brittle, and the plan already notes a timezone concern without fixing it.

Fix: make the date boundary explicit. For v1, use UTC or a configured property timezone, but pass "today" into the helper so unit tests are deterministic:

```elixir
@spec profile_for(User.t(), Date.t()) :: Card.t()
def profile_for(%User{} = user, today \\ Date.utc_today()) do
  ...
  received_this_month: count_this_month(received, today)
end

defp count_this_month(recognitions, %Date{year: year, month: month}) do
  Enum.count(recognitions, fn r ->
    date = DateTime.to_date(r.inserted_at)
    date.year == year and date.month == month
  end)
end
```

If using property-local time is required, read the timezone from runtime config and document the fallback.

### §7 Reward Glyphs Conflict With The Project Icon Guidance

Contradiction: The plan introduces Unicode glyphs as reward icons. The project instructions require using the imported `<.icon>` component for icons and avoiding ad hoc icon systems. It also adds non-ASCII UI content without a strong need.

Fix: store an icon name, not a glyph, in the typed DTO:

```elixir
field :icon, String.t()
```

Render with:

```heex
<.icon name={item.icon} class="size-5" />
```

Use Heroicon names already supported by `CoreComponents.icon/1`, such as `hero-sparkles`, `hero-clock`, `hero-gift`, or `hero-heart`.

## Spec drift / missing clauses

- The Profile spec does not mention channel memberships, while the Channels plan expects colleague profile cards to show memberships. Add a Profile clause only if Profile owns that display; otherwise Channels should render memberships outside `profile_card`.
- `F.Profile.12` says point-bearing recognitions make up the earnings breakdown, but `points_balance` is currently a seeded user field and can differ from the sum of `bonus_points`. Add a clause defining how the UI behaves when balance and recognized earnings do not reconcile.
- `F.Profile.17` should explicitly require `desktop_rail` IDs or side-rail component presence, because the current layout does not provide this automatically.
- The spec should define whether property code is a constant, runtime config value, or future schema field. The plan introduces config without a spec-backed source.

## Cross-plan concerns

- Channels and Profile both edit `PeopleLive :show`. Profile must not remove or hide any Channels-owned membership display, and Channels must not widen `Profile.Card` without Profile agreeing to the DTO change.
- Today depends on private-recognition semantics for off-shift waiting counts. Profile should avoid changing `Recognitions.received_by/1` to public-only, or Today will undercount private recognitions.
- If Profile changes `ProfilePort.profile_for/1` to `profile_for/2`, all existing `ProfileMock` scenarios and PeopleLive/ProfileLive tests across Channels/Profile must be updated in the same execution window.

## Nits

- `F.Profile.10` uses an em dash placeholder. This is fine because the spec requires it, but tests should assert the stat tile by ID rather than broad text matching.
- Settings links marked as `href="#"` can cause awkward scroll/focus behaviour. Prefer disabled buttons with `type="button"` and `aria-disabled="true"` if they are inert.
- `RewardItem.cost` should be `non_neg_integer()` rather than `integer()`.
- The plan's route smoke tests are database-backed and should be `async: false` with a short comment if they share sandbox state.

## Open questions raised by the original plan

- `/people/:own-id`: recommended answer is no redirect for v1, but the data boundary should still treat the viewer as self if using `profile_for(subject, viewer)`. The component can choose colleague chrome if product wants that visual.
- `points_earned` manager-bonus-only vs base recognition points: escalate to product/Recognitions. For this plan, label the section as bonus-point earnings or include an unreconciled balance note; do not imply it fully explains `points_balance`.
- "Ack on time" denominator: resolved for v1. Render the placeholder only.
- `recognition.inserted_at` vs `sent_at`: resolved. Use `inserted_at` in v1.
- Private recognition count in Today: Profile must preserve `Recognitions.received_by/1` as all recognitions for the recipient; Today should use a separate `private_received_since/2` helper.
