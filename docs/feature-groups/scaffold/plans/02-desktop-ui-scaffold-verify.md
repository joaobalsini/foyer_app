# Verify — Plan 02 Desktop UI scaffold

Verifies: [`02-desktop-ui-scaffold.md`](./02-desktop-ui-scaffold.md) (Codex
review in [`02-desktop-ui-scaffold-review.md`](./02-desktop-ui-scaffold-review.md)).
Builds on the mobile scaffold landed in
[`01-mobile-ui-scaffold.md`](./01-mobile-ui-scaffold.md) and its
[implementation review](./01-mobile-ui-scaffold-implementation-review.md).

## Verdict

**Pass with follow-ups.**

The executor implemented every section §3–§11 of plan v2 with the right shape:
CSS primitives, `desktop_rail/1` component, shell wrapper on all seven LiveViews,
two-panel chat layout with dual-load in `load_conversation/2`, `.foyer-content-cols`
two-column treatment for compose, read-receipts, recognition give, profile card.
Static checks were clean before this pass and remain clean after. The verification
turned up one genuine band-aid (the `ack_initials/1` helper, papering over a missing
preload on `Foyer.House.get_announcement!/2`), one fragile test assertion (the
"direct load populates inbox" test only checked a container ID), no test
proving the staff-compose render-only gate truly removes the form, and no test
pinning the CSRF emission on the rail's sign-out link. All four are now fixed.
One known issue remains: `compose_submit` / `edit_submit` event handlers have no
manager? guard — they rely on `create_announcement` returning `:not_implemented`.
That's a real feature-group concern (House) per plan §5.3, not a scaffold one.

## Checklist

1. **Spec drift (plan v2 §3–§11):** ✔ Each section maps to concrete code: CSS in
   `assets/css/app.css:248-377`, rail component in
   `lib/foyer_web/components/foyer_components.ex:126-230`, shell wrapper applied to
   all 7 LiveViews (Today/House/Announcement/Chat/Recognitions/Profile/People),
   `foyer-content-cols` used in profile_card, compose new/edit, show read-receipts,
   recognition new. Router unchanged as promised.

2. **Guidelines followed:** ✔ `smoke_test.exs` tagged `:integration`,
   `async: true`. Uses `stub_with` (not `Application.put_env`). Imports fixture
   helper. No F-numbers (scaffold has no F-clauses per `scaffold/spec.md`).

3. **Static checks clean:** ✔ `mix compile --warnings-as-errors`, `mix format
   --check-formatted`, `mix credo --strict`, `mix test` all pass after fixes.

4. **Test suite health:** ✔ 39 tests, 0 failures, 0.5s. Well under the 10s budget.
   New smoke tests are behaviour-pinning, not class-presence-only.

5. **Database indexes & no N+1:** ✔ No new migrations. Confirmed via `git status`.
   `get_announcement!/2` preload tightened to `acks: :user` — backed by existing
   `unique_index(:announcement_acks, [:announcement_id, :user_id])` (mobile plan
   §6.4). Single join, no N+1. Channels load for the rail is a single
   `list_for_user/1` per `handle_params/3`, backed by
   `index(:channel_memberships, [:user_id])`.

6. **Context isolation:** ✔ LiveViews call `FoyerWeb.LiveDeps.*` ports;
   contexts call schemas. The desktop_rail component reads from assigns only —
   no DB. The one direct context call inserted in the new test
   (`Foyer.House.acknowledge/2`) is a test-side fixture insertion, not LiveView
   code.

7. **LiveView mount discipline:** ✔ All seven `mount/3` functions are pure assigns
   + (in ChatLive) PubSub subscribe; no DB loads. All data loads happen in
   `handle_params/3` (and the private `load_conversation/2`). No `assign_async`
   needed for the scaffold.

8. **Mobile responsiveness:** ✔ `.foyer-shell` keeps mobile (block) layout below
   768 px; `.foyer-rail { display: none }` below `md:`. `.foyer-content` keeps
   `padding-bottom: 5rem` below `md:` for bottom-nav clearance. `.foyer-bottom-nav
   { display: none }` only inside `@media (min-width: 768px)`. Chat inbox uses
   `md:p-0` only at `md:+`, so mobile padding from `.foyer-scroll` is preserved.
   Profile card stacks single-column below `lg:` (flex-direction: column).

9. **Accessibility:** ✔ Rail is `<nav id="desktop-rail" aria-label="Main
   navigation">`. Active item carries `aria-current="page"`. Off-shift items
   render as **real** `<button disabled aria-disabled="true">` — keyboard-inert,
   not aria-only. New compose-gated view replaces the form (truly inert — there
   is no `<form>` in the DOM for staff, not even hidden).

10. **No secrets in source:** ✔ `git diff config/` shows no new env vars,
    credentials, or tokens.

11. **Telemetry / structured logging:** n/a — none added or removed.

## Findings fixed in this pass

### 1. `ack_initials/1` was a band-aid over a missing `acks: :user` preload

- **File:** `lib/foyer/house.ex:48-58` (the `get_announcement!/2` query).
- **Symptom:** The desktop read-receipts panel renders one badge per ack with
  `{ack_initials(ack)}`. The old preload `[:author, :channel, :reads, :acks]` did
  not preload `acks.user`, so `ack.user` was an unloaded association and the
  helper returned `"??"` for every badge. The executor wrote `ack_initials/1`
  with a `"??"` fallback as the fix — that's a UI band-aid for a context bug.
- **Change:** preload is now `[:author, :channel, :reads, acks: :user]`. One
  additional join per page load — backed by the existing
  `unique_index(:announcement_acks, [:announcement_id, :user_id])`, no N+1, no
  new migration. The `ack_initials/1` helper stays as a defensive `_ -> "??"`
  fallback (cheap insurance against a future regression), but the primary
  `%{user: %{initials: initials}}` clause now matches every real ack.
- **Test that pins it:** `test/foyer_web/smoke_test.exs` — new test
  `"ack badges render the acking user's initials (not '??')"` inserts an
  announcement, has Maya ack it, opens it as Charlotte (the author), asserts
  the badge `#ack-badge-#{maya.id}` is present and the rendered HTML does not
  contain `">?? ✓"`. If the preload regresses, this test fails loudly.

### 2. Chat dual-load test asserted only on container ID (not on the data)

- **File:** `test/foyer_web/smoke_test.exs:89-96` (was).
- **Symptom:** The "direct load of chat room populates inbox panel" test asserted
  `has_element?(view, "#chat-panel-inbox")` and `has_element?(view, "#inbox")` —
  the stream container ID is rendered unconditionally, so the test would pass
  even if `load_conversation/2` stopped streaming conversations (the whole point
  of the v2 §5.7 dual-load). The dual-load is the chat surface's biggest
  desktop-specific behaviour change; this test is its only pinning gate.
- **Change:** the assertion is now
  `has_element?(view, "#inbox #conv-#{ctx.maya_charlotte.id}")` — pinning to the
  seeded conversation's stream `dom_id`. If `load_conversation/2` drops
  `stream(:conversations, conversations, reset: true)`, this test fails.

### 3. No test that the staff-compose render-only gate hides the form

- **File:** `lib/foyer_web/live/announcement_live.ex:173-219` (the `:new`
  clause). The executor's deviation #5 was true — Maya (staff) sees the gated
  div, the form is in the `else` branch, so it is truly not rendered (not
  CSS-hidden). But there was no test pinning this.
- **Change:** two new pinning tests in
  `test/foyer_web/smoke_test.exs`:
  - `"staff visiting /announcements/new sees gated view, NO form"` asserts the
    `#compose-gated` element is present AND `#announcement-new-form` is absent
    AND no `button[type='submit']` is in the DOM. If a future edit replaces the
    Elixir gate with a `class="hidden"` toggle, this test fails.
  - `"manager visiting /announcements/new sees the form"` — the positive case
    to guard against accidentally gating managers too.

### 4. No test that the rail sign-out link is CSRF-protected

- **File:** `lib/foyer_web/components/foyer_components.ex:224` — the
  `<.link method="delete" href={~p"/session"}>` for sign-out.
- **Symptom:** Plan v2 §4.1 explicitly switched from `<.form>` to
  `<.link method="delete">` because Phoenix renders the latter with a CSRF
  token automatically. If a future edit drops `method="delete"`, the sign-out
  becomes an unauthenticated GET (a security regression), and nothing would
  fail.
- **Change:** new test in `test/foyer_web/smoke_test.exs`,
  `"rail sign-out link carries a CSRF token"`, asserts the rendered HTML
  contains `<a … data-method="delete" data-csrf="…" data-to="/session" …
  id="rail-sign-out"`. Empirically verified: the live render emits all four
  attributes as expected.

## Known issues left

### 1. `compose_submit` / `edit_submit` have no manager? guard

- **File:** `lib/foyer_web/live/announcement_live.ex:95-130`.
- **Symptom:** A staff user could craft a `phx-submit="compose_submit"` event
  via the LiveView websocket and reach `LiveDeps.house().create_announcement/2`.
  Today that returns `:not_implemented` so nothing happens, but the moment the
  House feature group wires real writes, this becomes a real authorization gap.
- **Why out of scope:** Plan v2 §5.3 chose a render-only gate explicitly,
  acknowledging this. The real write path is deferred to the House feature
  group. Adding an event-side guard here would mean writing logic that the next
  feature plan will rewrite. Better to do it once, in that plan, against the
  real `create_announcement` contract. The render-only gate is now pinned by
  test #3 above, so the band-aid is at least visible.
- **Recommendation for the House feature-group plan:** add a manager? check at
  the **top of `handle_event("compose_submit", _, _)`** (and `edit_submit`),
  returning `{:noreply, put_flash(socket, :error, "Managers only.")}` on fail.
  Or — better — add an `:ensure_manager` on_mount hook to `UserAuth` and put
  `/announcements/new` (and the future `/announcements/digest`,
  `/announcements/mine`) in a manager-gated `live_session`.

### 2. `profile_card/1` adds 1.5rem padding inside `.foyer-scroll`'s 1rem padding

- **File:** `lib/foyer_web/components/foyer_components.ex:460` —
  `<div class="foyer-content-cols">` wraps the card, and `.foyer-content-cols`
  carries `padding: 1.5rem` (CSS line 367) on top of `.foyer-scroll`'s
  `padding: 1rem` (CSS line 181).
- **Symptom:** On every surface that wraps content in `foyer-content-cols`, the
  effective padding at mobile widths is 2.5rem total (1rem outer + 1.5rem
  inner). Visually: extra inner whitespace on Me/People :show, compose new/edit,
  recognition give, announcement show. Not a functional bug, but inconsistent
  with non-cols surfaces.
- **Why out of scope:** This is a design polish issue, not a scaffold contract
  violation. The plan's `foyer-content-cols` rule (§3.1) explicitly carries the
  1.5rem padding, and the plan was accepted with that spec. Fixing it means
  either redesigning the CSS contract or wrapping each call site differently —
  both belong in a UI-polish ticket.

### 3. The Today desktop layout is inferred (no mock)

- **File:** `lib/foyer_web/live/today_live.ex:92` — `md:max-w-2xl md:mx-auto`.
- **Symptom:** Plan §5.1 flagged this as the one inferred layout. The verifier
  cannot prove the design intent is right without a mock; only that the code
  matches the inferred plan.
- **Why out of scope:** Awaiting product design. The plan §12.1 already calls
  this out.

## Test/credo/format status (after fixes)

```
$ mix compile --warnings-as-errors    # clean
$ mix format --check-formatted        # clean
$ mix credo --strict                  # 0 issues, 265 mods/funs
$ mix test                            # 39 tests, 0 failures, 0.5s
```

`mix dialyzer` not run (slow; no @spec changes that affect typing — only
preload-list contents and test additions).

Test count went from 35 to 39 — added 4 new pinning tests in
`smoke_test.exs` (the "dual-load" test was tightened in place, not
added): ack-badge initials, staff-gated compose, manager-allowed compose,
sign-out CSRF. The desktop smoke file is now 12 tests (was 8). The
"manager-allowed compose" case is fast (Charlotte already on-shift), no
fixture overhead.
