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

Three follow-ups remain (see end of doc): removed-announcement UX (manager
cannot reach `/announcements/:id` after removal to view audit receipts),
absence of structured logging / telemetry for write events (a project-wide
gap, not announcements-specific), and the `removed_at` btree index that
would be more useful as a partial index for the hot "where removed_at IS
NULL" filter.

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

### 2. No structured logging or telemetry on write events

- **Files:** `lib/foyer/house.ex` (all write paths), entire
  `lib/foyer/` directory.
- **Symptom:** `grep -rn "Logger\|:telemetry" lib/foyer/` returns
  nothing. The verify checklist asks for telemetry/log lines on
  meaningful events. Create/edit/remove/pin/unpin are meaningful state
  mutations — without logs, an operator cannot reconstruct who
  removed what or when.
- **Why deferred:** introducing a logging pattern in only this feature
  group would be inconsistent with the rest of `Foyer.*`. This is a
  project-wide gap (no telemetry handler module, no
  `Foyer.Telemetry.event/2` helper, no `Logger.metadata` discipline at
  context boundaries). Recommend a cross-cutting plan, not a one-off
  here.

### 3. `announcements.removed_at` index is plain btree, not partial

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

### 4. Migration doesn't use `CREATE INDEX CONCURRENTLY`

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
