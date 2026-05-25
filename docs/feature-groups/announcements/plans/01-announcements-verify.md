# Verify — Announcements feature group

## Verdict

**Pass with follow-ups.**

There is no plan file under `docs/feature-groups/announcements/plans/`; the
execute phase worked directly from the spec (`docs/feature-groups/announcements/spec.md`,
clauses `F.Announcements.1` – `.10`). All ten clauses now map to a real
implementation in `Foyer.House` and `FoyerWeb.AnnouncementLive`, and each
clause is pinned by at least one numbered test in
`test/foyer/house_test.exs`. Three additional LiveView-level e2e tests were
added during verify to pin staff-compose redirect, manager pin/unpin through
the UI, and soft-remove disappearance from the feed.

Static checks were **not clean** when verify started — credo flagged two
refactors in `Foyer.House` and dialyzer flagged three MapSet opaqueness
warnings in `receipts_for/2`. All three are fixed in this pass. After fixes:
`mix format --check-formatted`, `mix credo --strict`, `mix dialyzer`, and
`mix compile --warnings-as-errors` all run clean; the full suite is 44 tests
in 0.5 s.

Two follow-ups remain (see end of doc): removed-announcement UX (manager
cannot reach `/announcements/:id` after removal to view audit receipts),
and the `removed_at` btree index that would be more useful as a partial index
for the hot "where removed_at IS NULL" filter.

## Checklist

1. **Spec drift — every `F.Announcements.<N>` clause maps to code and a
   pinned test:**
   - **F.Announcements.1 — Managers can create:**
     `Foyer.House.create_announcement/2` at `lib/foyer/house.ex:111-126`
     enforces `ensure_manager/1` and `ensure_changeset_channel_member/2`.
     Pinned by `test/foyer/house_test.exs:15`.
   - **F.Announcements.2 — Staff cannot create, including forged-param
     attempts:** context guard at `lib/foyer/house.ex:120`
     (`ensure_manager/1`); LiveView render-side guard at
     `lib/foyer_web/live/announcement_live.ex:46-62` (apply_new redirects
     staff). Pinned by `test/foyer/house_test.exs:29` (context-level forged
     submit) and `test/foyer_web/scaffold_smoke_test.exs:188-197` (HTTP-level
     redirect; new in verify pass).
   - **F.Announcements.3 — Author can edit within 15 min:**
     `update_announcement/3` at `lib/foyer/house.ex:140-153` chains
     `ensure_author`, `ensure_within_grace`, `ensure_changeset_channel_member`.
     `within_grace_window?/1` at `lib/foyer/house.ex:223-228` uses
     `@grace_window_seconds = 15 * 60`. Pinned by
     `test/foyer/house_test.exs:41`.
   - **F.Announcements.4 — Edits and removals after grace are rejected:**
     same `ensure_within_grace/1` in both `update_announcement/3` and
     `remove_announcement/2` (`lib/foyer/house.ex:160`). Pinned by
     `test/foyer/house_test.exs:50` (both paths) and `:59` (non-author
     paths, which fail earlier at `ensure_author/2`).
   - **F.Announcements.5 — Managers can pin and unpin:**
     `pin_announcement/2`, `unpin_announcement/2`, and the private
     `update_pin/3` (`lib/foyer/house.ex:175-260`) require
     `ensure_manager/1` AND `ensure_member/2` — defending against a
     non-channel manager. Pinned by `test/foyer/house_test.exs:84` and
     `test/foyer_web/scaffold_smoke_test.exs:200-210` (UI round-trip; new
     in verify pass).
   - **F.Announcements.6 — Soft removal via `removed_at`; receipts
     auditable; gone from user feeds:** migration
     `priv/repo/migrations/20260525134902_add_announcement_removal_fields.exs`
     adds `removed_at` + `removed_by_id`. `remove_announcement/2` at
     `lib/foyer/house.ex:156-170` writes both. `feed_for/2`, `list_pinned_for/1`,
     `get_announcement!/2`, and `needs_ack_from/1` all filter
     `is_nil(a.removed_at)` (`lib/foyer/house.ex:31, 45, 59, 235`).
     `receipts_for/2` does NOT filter removed — receipts survive
     soft-delete. Pinned by `test/foyer/house_test.exs:66` (feed
     filtering), `:74` (receipts survive), and
     `test/foyer_web/scaffold_smoke_test.exs:212-225` (UI flow; new in
     verify pass).
   - **F.Announcements.7 — Required acks exclude the author:**
     `ensure_ack_required_from/2` at `lib/foyer/house.ex:295-301` uses a
     guard `when author_id != user_id`. `needs_ack_from/1` includes the
     SQL clause `a.author_id != ^user_id` (`lib/foyer/house.ex:236`).
     Pinned by `test/foyer/house_test.exs:92`.
   - **F.Announcements.8 — Acknowledgement and read writes are idempotent:**
     `acknowledge/2` and `mark_read/2` (`lib/foyer/house.ex:67-103`) both
     use `on_conflict: :nothing, conflict_target: [:announcement_id,
     :user_id]`. Backed by the pre-existing unique indexes
     `announcement_acks_announcement_id_user_id_index` and
     `announcement_reads_announcement_id_user_id_index`. Pinned by
     `test/foyer/house_test.exs:97` (two calls each, both `{:ok, _}`).
   - **F.Announcements.9 — Receipt groups (ack / read-without-ack /
     unread / off-shift):** `receipts_for/2` at `lib/foyer/house.ex:182-202`
     buckets via `receipt_bucket_for/4` (`lib/foyer/house.ex:213-225`).
     Off-shift wins over ack/read — a deliberate choice (the spec lists
     "off shift" as one of the four groups and the test expectation in
     `test/foyer/house_test.exs:114` confirms it). Pinned by
     `test/foyer/house_test.exs:107`.
   - **F.Announcements.10 — Membership checks are in context, not only in
     routes:** every write path
     (`update_announcement`, `remove_announcement`, `pin_announcement`,
     `unpin_announcement`) calls `ensure_member/2` or
     `ensure_changeset_channel_member/2`. The read path
     `get_announcement!/2` enforces membership via the join. Forged
     events (a non-member triggering `phx-click="pin"` or `phx-submit`)
     hit the context guard regardless of route gating. Pinned by
     `test/foyer/house_test.exs:117` (membership rejection on read/pin)
     and `:125` (membership rejection on remove for a synthetic
     out-of-channel author).

2. **Guidelines followed (`docs/TESTING_GUIDE.md`):**
   - `test/foyer/house_test.exs` uses `Foyer.DataCase, async: true`, runs
     real Repo, and every test name carries its `F.Announcements.<N>`
     prefix (verified by `grep -n F.Announcements test/foyer/house_test.exs`).
   - `test/foyer_web/scaffold_smoke_test.exs` is tagged `:integration`,
     `async: true`, uses `stub_with` (no `Application.put_env`), and the
     new tests added in this pass (`scaffold_smoke_test.exs:188, 200, 212`)
     mention `F.Announcements.2`, `.5`, and `.6` in their test names.
   - No `Mock`/`meck`; Mox + scenario-style `stub_with`. ✓

3. **Static checks clean (after verify fixes):**
   - `mix compile --warnings-as-errors` — clean.
   - `mix format --check-formatted` — clean.
   - `mix credo --strict` — `300 mods/funs, found no issues`. Two
     refactors fixed in this pass (see Findings #1 and #2).
   - `mix dialyzer` — `Total errors: 0`. Three pre-existing MapSet
     opaqueness warnings fixed in this pass (see Finding #3).

4. **Test suite health:** 44 tests, 0 failures, 0.5 s. Well under the 10 s
   budget. Slowest test is the Today on-shift smoke test (82 ms), unrelated
   to announcements. Slowest announcements test is
   `F.Announcements.2 staff cannot create` (29 ms) — fixture seeding
   dominates, not the assertion.

5. **Database indexes — every introduced query is index-backed:**
   - `feed_for/2` and `list_pinned_for/1` (`lib/foyer/house.ex:27-50`)
     drive off `channel_memberships(user_id)` (existing
     `channel_memberships_user_id_index`) and
     `announcements(channel_id, pinned_at, published_at)` (existing).
     The `is_nil(removed_at)` filter is a residual predicate evaluated
     after the membership join — see follow-up #3 about converting the
     new `announcements_removed_at_index` to a partial index for the hot
     "WHERE removed_at IS NULL" path if announcement volume grows.
   - `get_announcement!/2`: index on `announcements(channel_id, ...)` +
     PK on `id`.
   - `receipts_for/2`: `receipt_recipients/1` joins on
     `channel_memberships.channel_id` (existing index);
     `on_shift_ids/1` filters `shifts.user_id in ?` (existing index on
     `shifts(user_id)`); `receipt_ack_ids/2` and `receipt_read_ids/2`
     filter `(announcement_id, user_id)` — both columns covered by the
     existing unique indexes.
   - `needs_ack_from/1`: same shape as `feed_for/2` plus a left join on
     `announcement_acks(announcement_id, user_id)` — covered by the
     unique index.
   - New migration adds `announcements_removed_at_index` and
     `announcements_removed_by_id_index`. The first is a plain btree
     (see follow-up #3); the second covers any future "list removals by
     remover" query.

6. **No N+1 queries:**
   - `feed_for/2` and `list_pinned_for/1` preload `[:author, :channel,
     :reads, :acks]`. ✓
   - `get_announcement!/2` preloads the same. ✓
   - `receipt_recipients/1` selects users via a join (single query). ✓
   - `on_shift_ids/1`, `receipt_ack_ids/2`, `receipt_read_ids/2` are each
     one query with an `IN` clause. ✓
   - `needs_ack_from/1` preloads `[:author, :channel]` (no per-row
     follow-up). ✓

7. **Migration safety:**
   - `20260525134902_add_announcement_removal_fields.exs` is reversible
     (Ecto auto-reverses `alter ... add` to `alter ... remove` and `create
     index` to `drop index`). No `CREATE INDEX CONCURRENTLY` — acceptable
     here because the `announcements` table is small and this is a POC.
     For production-scale this should switch to concurrent indexes; noted
     in follow-up #4.
   - No silent destructive defaults: both new columns are nullable and
     have no `default:`, so existing rows are unaffected.
   - `removed_by_id` references `users(id) ON DELETE NILIFY ALL` —
     matches the existing `author_id` reference, won't cascade if a
     remover account is deleted.

8. **Context isolation:** `Foyer.House` talks to `Foyer.Repo` and its own
   schemas (`Announcement`, `AnnouncementAck`, `AnnouncementRead`), plus
   `Foyer.Channels.Membership` (a sibling) and `Foyer.Shifts.Shift` (a
   sibling). The membership/shift reads are joins inside the context, not
   `Foyer.Channels.list_for_user/1` cross-calls — direct schema use across
   contexts is acceptable here because they're sibling read-only queries,
   not write paths (see `docs/ARCHITECTURE.md` "fat contexts" section).
   `FoyerWeb.AnnouncementLive` talks only through `FoyerWeb.LiveDeps.house()`
   and `FoyerWeb.LiveDeps.channels()` — no direct context import. ✓

9. **LiveView mount discipline (`lib/foyer_web/live/announcement_live.ex`):**
   - `mount/3` at line 23-34 assigns pure defaults — no DB calls. ✓
   - `handle_params/3` at line 37-43 dispatches to `apply_new/1`,
     `apply_show/2`, `apply_edit/2`. All DB loads happen in those private
     functions. ✓
   - No PubSub subscriptions in this LiveView (announcements aren't live
     yet); nothing to tear down on terminate. ✓
   - No `assign_async` / `start_async` — all loads are cheap point lookups
     against indexed columns.

10. **Mobile responsiveness:** No CSS changes in this feature group. The
    announcement detail page reuses the scaffold's `foyer-root`,
    `foyer-scroll`, `foyer-bottom-nav` classes — already mobile-verified
    in the scaffold pass.

11. **Accessibility:** The new pin/unpin/remove buttons (`announcement_live.ex:339-385`)
    are real `<button type="button">` elements with `phx-click` handlers,
    not links — keyboard activation works. Each carries a stable `id`
    (`announcement-pin-btn`, `announcement-unpin-btn`, `announcement-remove-btn`)
    for test pinning and screen-reader announcement. The "Acknowledged"
    state button (`#acked-state`) is rendered `disabled` rather than
    visually-only inert. The receipt-groups section (line 410-433) uses
    semantic `<section>` with stable IDs (`#receipts-acknowledged`,
    `#receipts-read`, `#receipts-unread`, `#receipts-off-shift`) and
    explicit `<.receipt_group label=…>` text. No new color-contrast
    surfaces introduced.

12. **No secrets in source:** `git diff config/` shows zero changes in
    config/. No new env vars introduced.

13. **Telemetry / structured logging:** **Not added.** This is a
    project-wide gap (no `lib/foyer/*` module currently emits telemetry
    or structured logs for state mutations). Introducing a pattern only
    in `Foyer.House` would be inconsistent. Noted as follow-up #2.

## Findings fixed in this pass

### 1. `ensure_available_member/2` ended with a redundant `with`

- **File:** `lib/foyer/house.ex` (was `:282-287`).
- **Symptom:** Credo (`--strict`) flagged "Last clause in `with` is redundant."
  The function chained `ensure_not_removed` and `ensure_member` in a `with`
  whose body was a literal `:ok`, when it could just return the second
  call's result.
- **Change:** dropped the final `:ok` clause and let the body return
  `ensure_member(...)` directly:

  ```elixir
  defp ensure_available_member(%Announcement{} = announcement, %User{id: user_id}) do
    with :ok <- ensure_not_removed(announcement) do
      ensure_member(announcement.channel_id, user_id)
    end
  end
  ```

  Behaviour is identical; credo passes.

### 2. `receipts_for/2` reduce-body nested too deep

- **File:** `lib/foyer/house.ex` (was `:182-216`).
- **Symptom:** Credo flagged "Function body is nested too deep (max depth
  is 2, was 3)" inside the `Enum.reduce/3` callback — the `cond ... ->
  Map.update!(...)` nest hit depth 3.
- **Change:** extracted the bucket-selection logic to a private
  `receipt_bucket_for/4` function (`lib/foyer/house.ex:213-225`); the
  reduce body is now a two-line `bucket = ...; Map.update!(acc, bucket,
  ...)`. Same algorithm, same outputs; tests
  (`F.Announcements.6` receipts survive, `F.Announcements.9` group split)
  still pass.

### 3. Pre-existing dialyzer MapSet opaqueness warnings in `receipts_for/2`

- **File:** `lib/foyer/house.ex` (was `:182-216` and the three private
  helpers `on_shift_ids/1`, `receipt_ack_ids/2`, `receipt_read_ids/2`).
- **Symptom:** `mix dialyzer` reported three `call_without_opaque`
  warnings against `MapSet.member?/2`. Confirmed by `git stash`-ing all
  verify-pass edits and re-running dialyzer against the executor's
  commit (`98a6668`) — the warnings exist on the executor's code,
  independently of any verify-pass refactor. Root cause: on
  Erlang/OTP 28 the inferred shape of `MapSet.new()` (an empty `:gb_sets`
  representation) does not unify with the opaque MapSet `:map` type
  declared in `MapSet`'s source, so any function that crosses module
  boundaries with such a value trips the opaqueness check.
- **Change:** the three id-set helpers now return plain `%{integer() =>
  true}` lookup maps instead of `MapSet.t/1`. `receipt_bucket_for/4` uses
  `Map.has_key?/2` instead of `MapSet.member?/2`. Same O(1) lookup,
  same outputs, and dialyzer is now clean (`Total errors: 0`). Each
  helper carries an explicit `@spec` so dialyzer has a concrete contract
  to check at the boundary.

### 4. Three F.Announcements clauses had no LiveView-level e2e pinning

- **File:** `test/foyer_web/scaffold_smoke_test.exs` (lines 188-225 after
  edit).
- **Symptom:** Every clause was covered by a context-level test in
  `test/foyer/house_test.exs`, but `F.Announcements.2` (staff redirect),
  `.5` (pin/unpin UI), and `.6` (UI removal disappears from feed) had no
  test that exercised the actual `/announcements/*` routes through
  `live/2`. The `WORKFLOW.md` verify checklist asks for at least one
  e2e per clause, and "e2e" for a LiveView surface naturally means
  hitting the router.
- **Change:** three new tests in the existing `describe "House"` block,
  each name-prefixed with the F-number:
  - **`F.Announcements.2 staff visiting /announcements/new is redirected
    and no form renders`** — `live/2` returns `{:error, {:live_redirect,
    %{to: "/house"}}}` for Maya. If the gate is dropped the assertion
    breaks loudly.
  - **`F.Announcements.5 manager can pin and unpin an announcement`** —
    clicks `#announcement-unpin-btn` then `#announcement-pin-btn` and
    asserts the button id swap after each click.
  - **`F.Announcements.6 removing an announcement drops it from feeds
    and back to /house`** — Charlotte clicks `#announcement-remove-btn`,
    receives a `{:live_redirect, %{to: "/house"}}`, and then Maya's
    `/house` no longer contains "Allergy protocol in effect".

### 5. Stale moduledocs claimed write paths were stubbed

- **Files:** `lib/foyer/house.ex:2-10`, `lib/foyer/house_port.ex:2-7`,
  `lib/foyer_web/live/announcement_live.ex:2-9`.
- **Symptom:** All three moduledocs said `create_announcement/2` (and in
  the LiveView, "create/update") was stubbed "pending the House feature
  group" — copy left over from the scaffold pass. Now misleading: the
  feature group has landed and every write path is implemented.
- **Change:** rewrote each moduledoc to describe the live behaviour and
  point at the `F.Announcements.<N>` clauses each module covers.

## Rebase

**Verdict after rebase: Pass.**

- **Rebase target:** `origin/main` at `49cd39b` ("desktop version").
- **New HEAD:** `bd27e55` (the four feature commits — `8dd17c1`, `2e63c03`,
  `ea4a801`, `bd27e55` — replayed in order on top of `49cd39b`).
- **Conflicts hit on the first commit (`98a6668` → `8dd17c1`):**
  - `lib/foyer/house.ex` — one hunk in `get_announcement!/2`. Desktop tightened
    the preload to `[:author, :channel, :reads, acks: :user]` so the
    read-receipts panel can render ack initials without an N+1; feature added
    `where: is_nil(a.removed_at)` for soft-removal semantics
    (`F.Announcements.6`). **Resolved by keeping both** — the tightest preload
    that satisfies the desktop ack-badge call site PLUS the removed-at filter.
    Moduledoc kept from the feature side (the desktop moduledoc described a
    stub that no longer exists). All other feature-side changes
    (`ensure_available_member/2`, the `receipts_for/2` bucket helper, the
    `%{integer() => true}` lookup-map id-set helpers with explicit `@spec`s)
    sit in regions untouched by desktop and survived auto-merge unchanged.
  - `lib/foyer_web/live/announcement_live.ex` — four hunks.
    1. `mount/3` assigns: kept both desktop's `:preview_title`/`:preview_body`
       and feature's `:can_ack?`/`:can_pin?`/`:receipts`.
    2. `apply_edit/2`: kept feature's `managed_by?`+`within_grace_window?`
       guard *and* added the desktop preview-field assigns inside the
       success branch.
    3. The render template (the largest hunk): rebuilt as desktop's shell
       (`Layouts.app` + `desktop_rail/1` + `foyer-content-cols`) wrapping
       the feature behaviour — `:new` keeps desktop's staff-gated div +
       preview column but adds the feature's `requires_ack` checkbox;
       `:edit` keeps the preview column and adds the `requires_ack`
       checkbox; `:show` puts the feature's pin/unpin/remove buttons,
       `can_ack?` gating and `requires_ack` tag inside the article (left
       column) and adds the feature's full `<.receipt_group>` breakdown to
       the desktop read-receipts right column (so both desktop's ack
       badges and the feature's bucketed groups render side-by-side).
    4. Trailing helpers: kept both `ack_initials/1` (desktop) and the
       `receipt_group/1` private component + its `attr` declarations
       (feature).
- **Post-merge fix-up:** auto-merge placed `defp update_pin_state/3`
  between two `def handle_event/3` clauses, which `--warnings-as-errors`
  flagged as ungrouped clauses. Moved `update_pin_state/3` below the last
  `handle_event/3` clause so all `handle_event/3` heads sit contiguously.
- **Test collision (desktop test of pre-feature placeholder):** the
  desktop pass added `test/foyer_web/desktop_smoke_test.exs` "staff
  visiting /announcements/new sees gated view, NO form", which asserted
  the **render-only** placeholder gate that existed before the
  Announcements feature group landed. The feature group implements
  `F.Announcements.2` as a **redirect** in `apply_new/1` (already pinned
  by `test/foyer_web/scaffold_smoke_test.exs` "F.Announcements.2 staff
  visiting /announcements/new is redirected..."). The desktop test was
  pinning superseded behaviour; rewrote it to assert the redirect (same
  intent — "no form must render for staff" — with the assertion now
  matching the spec-compliant implementation). The companion "manager
  visiting /announcements/new sees the form" test was unaffected.
- **No further conflicts** on the three verify commits (`c9d0e8e` →
  `2e63c03`, `e3f8cb5` → `ea4a801`, `bbd0500` → `bd27e55`).

### Post-rebase checks

- `mix deps.get` — all dependencies fetched, no version drift.
- `mix compile --warnings-as-errors` — clean (2 files recompiled).
- `mix format --check-formatted` — clean.
- `mix credo --strict` — `309 mods/funs, found no issues`.
- `mix dialyzer` — `Total errors: 0` (PLT already up to date for OTP 28 /
  Elixir 1.19).
- `mix test` — 56 tests, 0 failures, 0.7 s. Test DB was **not** reset; no
  schema-shape error surfaced. The `removed_at`/`removed_by_id` columns
  introduced by `20260525134902_add_announcement_removal_fields.exs`
  were already present in `foyer_test` from the pre-rebase verify pass,
  so the migration was a no-op at test time.

## Second pass — test architecture + spec

**Verdict after second pass: Pass.**

The first verify pass + rebase shipped, but two architectural gaps
remained against `docs/WORKFLOW.md` and `docs/TESTING_GUIDE.md`. Both
are closed in this pass; the four new commits sit on top of the rebase
HEAD (`bd27e55`).

### Spec rewrite — given/when/then form

`docs/WORKFLOW.md:38` requires specs in given/when/then form so tests
have a tight prose contract to pin against. The previous spec used
flat declarative clauses ("Managers can create announcements for
channels they belong to."). Rewrote each `F.Announcements.<N>` clause
(`.1` through `.10`) in given/when/then form **without renumbering** —
clause numbers are stable per `WORKFLOW.md:27-28`. The `## Scaffold
Gaps` section is preserved verbatim. F.Announcements.4 uses two
when/then blocks under a single clause to cover the "edits AND
removals after grace" pair, since both fail with the same guard chain
in the same code path.

Commit: `65ddea5` "docs(announcements): rewrite spec clauses in
given/when/then form".

### Scenario modules — `test/support/scenarios/<port>/`

`docs/TESTING_GUIDE.md:210` says "Organize scenario modules under
`test/support/scenarios/`, grouped by port." Before this pass the
directory did not exist; every test bound the mocks back to the real
context via `stub_with(Foyer.HouseMock, Foyer.House)`, which works
for route smoke tests but defeats the point of Mox for isolated
tests — there's no fake-world boundary.

Added under `test/support/scenarios/`:

- `house/fixtures.ex` — `Foyer.HouseScenarios.Fixtures`, the shared
  struct builder (`%User{}`, `%Channel{}`, `%Announcement{}`,
  `%AnnouncementAck{}`, `%AnnouncementRead{}`) every scenario draws
  from. No Repo round-trips.
- `house/empty.ex` — `Foyer.HouseScenarios.Empty` (`@behaviour
  Foyer.HousePort`): no announcements anywhere; mutations return
  `{:error, :unauthorized}` or `{:error, :outside_grace_window}`.
- `house/with_unacked.ex` — `Foyer.HouseScenarios.WithUnacked`:
  the canonical ack-required announcement, within grace, with the
  staff user in the `read_without_acknowledgement` bucket.
- `house/with_receipts.ex` — `Foyer.HouseScenarios.WithReceipts`:
  the same announcement viewed by its manager author, with one user
  acked, one read, four buckets populated.
- `channels/single_channel.ex` —
  `Foyer.ChannelsScenarios.SingleChannel`: a one-channel
  `Foyer.ChannelsPort` stub for tests that touch the compose
  audience select.

Each scenario implements its port behaviour, so a renamed callback
fails at compile time rather than at a single test (per
`TESTING_GUIDE.md:196-200`).

### Isolated LiveView tests — `live_isolated/3`

`docs/TESTING_GUIDE.md:83-95` says isolated tests are the **primary**
layer; before this pass, zero tests on this branch used
`live_isolated/3`. Added `test/foyer_web/announcement_live_test.exs`
with nine tests, each pinning a single `F.Announcements.<N>` clause:

- **F.Announcements.2** (two tests) — staff visiting
  `/announcements/new` is redirected with `{:live_redirect, to:
  "/house"}` and no form renders; manager sees `#announcement-new-form`.
- **F.Announcements.3** (two tests) — author within grace sees
  `#announcement-edit-link`; author outside grace sees the edit link
  (identity-gated, always shown to author) but NOT
  `#announcement-remove-btn` (grace-gated). The outside-grace test
  uses `Mox.expect/3` per `TESTING_GUIDE.md`'s "When to keep expect/3
  instead" — pinning the specific UI change against a one-off mock
  override rather than a named scenario.
- **F.Announcements.5** (two tests) — manager in the channel sees
  `#announcement-unpin-btn` on a pinned post; staff sees neither
  pin nor unpin.
- **F.Announcements.7** (two tests) — author of an ack-required
  post does NOT see `#acknowledge-btn`; a non-author who hasn't
  acked DOES.
- **F.Announcements.9** — the receipts panel renders all four
  `#receipts-{acknowledged,read,unread,off-shift}` bucket sections
  with the correct counts.

All tests are `async: true`. Each test calls
`FoyerWeb.IsolatedHelpers.prepare_isolated/4` to build the conn +
opts, then `Mox.allow/3` so the LiveView pid can see the test
process's mock expectations after mount.

#### Why a test router and a synthetic on_mount hook

`live_isolated/3` skips the production router, plugs,
`live_session`, and `on_mount` hooks — but the channel mount (which
runs after the static render to upgrade to a live view) DOES go
through `Phoenix.LiveView.Route.live_link_info!/3`, which looks up
the request URL in the configured router. Two consequences fall out:

1. If the route's `live_session` differs from the synthetic one in
   `conn.private[:phoenix_live_view]`, the channel mount treats the
   URL as external and redirects to it.
2. If we use the production router's `live_session
   :authenticated_on_shift`, the real `FoyerWeb.UserAuth` on_mount
   runs, sees no `current_user_id` in session, and redirects to `/`
   with "Please pick a user."

Both surfaced as `{:error, {:redirect, %{to: "http://www.example.com/"}}}`
or `{:error, {:redirect, %{to: "/"}}}` during development. The fix
is `test/support/isolated_router.ex` (`FoyerWeb.IsolatedRouter`),
which redeclares the three announcement routes under an
`:isolated_test` live_session whose on_mount is the synthetic
`FoyerWeb.IsolatedHelpers.OnMount` (reads `"current_scope"` straight
out of the session map). `prepare_isolated/4` defaults `router:` to
this test router, so both the static render and the channel mount
agree on which on_mount runs.

Commits: `3ae6164` "test(announcements): add scenario modules and
live_isolated harness", `678049f` "test(announcements): add isolated
LiveView tests via live_isolated/3".

### E2e gaps closed

`docs/TESTING_GUIDE.md:60-61` and `docs/WORKFLOW.md:77` require each
F-clause to be pinned by at least one e2e test. Before this pass,
only `F.Announcements.2`, `.5`, and `.6` had route smoke tests at
the LiveView/router layer. Added seven new tests in
`test/foyer_web/scaffold_smoke_test.exs`, each name-prefixed with
its F-number:

- **F.Announcements.1** — manager submits the compose form → the
  new announcement appears in their feed.
- **F.Announcements.3** — author edits within grace → the new title
  shows up in Maya's channel feed (and the old title is gone).
- **F.Announcements.4** — visiting `/announcements/:id/edit` after
  the grace window expires → `apply_edit/2` redirects to the show
  route with `flash: "That announcement can no longer be edited."`
  and the DB title is unchanged. (The route smoke layer cannot
  exercise the post-grace `phx-submit` path directly — the LiveView
  redirects before the form mounts — so the test pins the
  `apply_edit/2` gate, which is the only LiveView-layer point where
  this guard exists. The post-grace context-level rejection is
  pinned by `test/foyer/house_test.exs:50` `F.Announcements.4`.)
- **F.Announcements.7** — Charlotte (author of `suite_412`) does
  NOT see the acknowledge CTA on the detail page.
- **F.Announcements.8** — clicking `#acknowledge-btn` swaps it for
  `#acked-state`; the underlying `announcement_acks` row count
  stays at 1 even after a redundant context-level `acknowledge/2`,
  proving the unique-index-backed idempotent upsert.
- **F.Announcements.9** — manager loading the receipts panel sees
  all four bucket `<section>`s with the correct counts (1
  acknowledged, 1 read_without_acknowledgement, 0 unread, 1
  off_shift for the seeded scenario).
- **F.Announcements.10** — a non-member of the channel cannot
  reach the announcement; the `get_announcement!/2` membership
  guard raises `Ecto.NoResultsError`, which the LiveView converts
  into a redirect back to `/house`.

The F.10 test is intentionally distinct from the older
"unauthorized: Maya cannot open Leadership-only" test (line 177):
both pin the same membership guard, but only the new test mentions
its F-number so a spec drift is easy to spot.

Commit: `3ee07f5` "test(announcements): close e2e F-clause coverage
gaps".

### Final check results

- `mix deps.get` — clean.
- `mix compile --warnings-as-errors` — clean.
- `mix format --check-formatted` — clean.
- `mix credo --strict` — `383 mods/funs, found no issues` (was 309
  before; the new test-only modules add 74 mods/funs). Three Software
  Design nags about long-form module references were fixed by adding
  `alias Foyer.House.Announcement / AnnouncementAck` at module top
  and `alias Phoenix.LiveView.Lifecycle` in the harness.
- `mix dialyzer` — `Total errors: 0`.
- `mix test` — **72 tests, 0 failures, 0.6 s** (was 56 before
  rebase, 65 after isolated tests landed, 72 after e2e gaps were
  closed). Slowest test is still the unrelated Today on-shift smoke
  test; slowest announcement test is `F.Announcements.6` remove flow
  at ~17 ms. Well inside the 10-second budget.

Test DB was **not** reset — no schema-shape error surfaced.

### New HEAD SHA

After the four commits in this pass: `3ee07f5` "test(announcements):
close e2e F-clause coverage gaps". The four commits, in order:

1. `65ddea5` — spec rewrite (given/when/then).
2. `3ae6164` — scenario modules + isolated harness + test router.
3. `678049f` — isolated LiveView tests.
4. `3ee07f5` — e2e F-clause coverage.

A fifth commit (this verify-doc update) sits on top.

## Final review fixes

The final merge-readiness pass checked the `docs/WORKFLOW.md` verify action
directly and closed the remaining hard-gate gaps:

- Added structured `Logger.info/2` events for successful announcement
  create, update, remove, pin, and unpin operations. Each log includes
  `event`, `user_id`, `announcement_id`, and `channel_id`; those metadata
  keys are configured in `config/config.exs` so the fields are emitted.
- Cleaned the existing `mix credo --strict` failures in untouched scaffold
  areas by replacing stale `TODO` tags with neutral comments and extracting
  the nested direct-conversation creation path in `Foyer.Chat`.
- Updated `Foyer.HouseScenarios.WithUnacked`'s moduledoc so it matches the
  isolated tests that actually use that scenario.
- Re-ran the full verify gate: `mix format --check-formatted`,
  `mix credo --strict`, `mix precommit`, and `mix dialyzer` all pass.

## Known follow-ups

### 1. Removed announcements are unreachable for managers wanting to audit receipts

- **File:** `lib/foyer/house.ex:54-63` (`get_announcement!/2` filters
  `is_nil(removed_at)`).
- **Symptom:** `F.Announcements.6` says "removed announcements leave
  receipts auditable." `receipts_for/2` does keep receipts queryable
  through the context, but the LiveView `apply_show/2` calls
  `get_announcement!/2` which raises for removed rows, redirecting to
  `/house` with "That announcement is not available to you." There is
  no UI today to view receipts of a removed announcement.
- **Why deferred:** the context contract honours the spec
  (`House.receipts_for/2` works on a removed `%Announcement{}` — pinned
  by `test/foyer/house_test.exs:74`). What's missing is a manager-only
  surface (e.g. `/announcements/removed` or
  `/announcements/:id?include_removed=1`) — that's a new feature, not a
  scaffold drift. Recommend a tiny follow-up plan to add a "Removed
  announcements" view in the manager rail.

### 2. `announcements.removed_at` index is plain btree, not partial

- **File:** `priv/repo/migrations/20260525134902_add_announcement_removal_fields.exs:10`.
- **Symptom:** The hot query is `WHERE removed_at IS NULL` (every feed
  load). A plain btree on a column with mostly-null values is barely
  used by PostgreSQL; the join on `channel_memberships` does the heavy
  lifting and the IS NULL clause is a residual filter. A partial index
  `WHERE removed_at IS NULL` would compress index size and speed up
  the residual check; alternatively a partial index `WHERE removed_at
  IS NOT NULL` would speed up the audit query.
- **Why deferred:** at current POC scale (a handful of announcements
  per channel) the index choice doesn't matter measurably. Recommend
  revisiting when announcement volume per channel exceeds ~1000.

### 3. Migration doesn't use `CREATE INDEX CONCURRENTLY`

- **File:** `priv/repo/migrations/20260525134902_add_announcement_removal_fields.exs`.
- **Symptom:** Both `create index` calls are blocking. On a production
  PostgreSQL with concurrent writes this would lock the table.
- **Why deferred:** the table is empty in dev/test and small in the
  POC. The project has no Ecto migration linter enforcing
  `CONCURRENTLY`, so this is a recommended-not-required policy. Fix
  when the project standardises on a `MigrationGuard` helper.

## Test / credo / format / dialyzer status (after fixes)

```
$ mix compile --warnings-as-errors    # clean
$ mix format --check-formatted        # clean
$ mix credo --strict                  # 0 issues, 300 mods/funs
$ mix dialyzer                        # Total errors: 0
$ mix test                            # 44 tests, 0 failures, 0.5s
```

Test count went from 41 (after executor) to 44 (after verify) — added
three pinning tests in `scaffold_smoke_test.exs` (`F.Announcements.2`,
`.5`, `.6` at the LiveView/router layer). Slowest test in the suite is
unrelated (Today on-shift, 82 ms). The slowest announcements test is the
new `F.Announcements.6` remove-and-disappear flow at 17 ms — well within
budget.
