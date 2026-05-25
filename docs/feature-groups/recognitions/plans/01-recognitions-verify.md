# Verify — Recognitions feature group

## Verdict

**Pass with follow-ups.**

The executor implemented every clause of `docs/feature-groups/recognitions/spec.md`
(`F.Recognitions.1`–`F.Recognitions.10`) with the right shape: `give/2` and
`update_recognition/3` are real, the `team` value is gone, soft-removal columns and
a `recognition_point_entries` ledger table are migrated in, `feed_public/0` /
`get_recognition!/2` filter out removed rows. There was **no plan file** in
`docs/feature-groups/recognitions/plans/` — the execute phase worked directly from
the spec (no plan-review pass by Codex). That's a process gap, not a code gap.

This pass found and fixed one real F.Recognitions.10 visibility leak (`/people/:id`
exposing private recognitions to third parties via `Foyer.Profile.profile_for/1`),
two `call_without_opaque` dialyzer regressions on the new `Ecto.Multi` calls, and
added three pinning tests (two unit, one e2e) so the next drift on either fails
loudly. After fixes: 39 tests / 0 failures / 0.8s, format/credo/dialyzer all
clean. Three follow-ups remain — see "Known follow-ups" below.

## Checklist

1. **Spec drift — `F.Recognitions.1`–`F.Recognitions.10`.** ✔ after fixes. Each
   clause is now backed by code AND at least one assertion in
   `test/foyer/recognitions_test.exs`:

   | Clause | Code | Test |
   |---|---|---|
   | F.Recognitions.1 — any on-shift user can send | route gate in `lib/foyer_web/router.ex:37-57` (`:authenticated_on_shift`) + `Foyer.Recognitions.give/2` at `lib/foyer/recognitions.ex:79-104` | `recognitions_test.exs:17-29` |
   | F.Recognitions.2 — self-recognition rejected | `ensure_not_self/2` at `lib/foyer/recognitions.ex:186-191` | `recognitions_test.exs:31-38` |
   | F.Recognitions.3 — values are exactly the 6 listed | `@house_values` at `lib/foyer/recognitions/recognition.ex:24` + `validate_subset(:values, @house_values)` at line 57 | `recognitions_test.exs:40-58` (rejects "team") + scaffold smoke `refute render(view) =~ "Team"` |
   | F.Recognitions.4 — at least one value required | `validate_required([..., :values])` + `validate_values_present/1` at `lib/foyer/recognitions/recognition.ex:55, 62-67` | `recognitions_test.exs:50-58` (empty list rejected) |
   | F.Recognitions.5 — only managers grant bonus | `normalize_bonus_points/2` at `lib/foyer/recognitions.ex:183-184` + `ensure_bonus_allowed/2` at lines 193-200 | `recognitions_test.exs:60-78` (staff bonus_points silently zeroed) |
   | F.Recognitions.6 — tiers are exactly 0/10/25/50/100 | `@point_tiers` at `lib/foyer/recognitions.ex:16` + `ensure_bonus_tier/1` at lines 202-207 | `recognitions_test.exs:71-77` (15 rejected as `:invalid_point_tier`) |
   | F.Recognitions.7 — balance + ledger in one Multi | `grant_points/2` at `lib/foyer/recognitions.ex:222-241` runs `PointEntry.insert` and `User.update_all(inc: [points_balance: ...])` inside one `Ecto.Multi.run/3` step of the Multi started at line 93 | `recognitions_test.exs:80-95` |
   | F.Recognitions.8 — removal is soft + reverses points | `remove_recognition/2` at `lib/foyer/recognitions.ex:135-156` writes `removed_at`/`removed_by_id` via Multi.update + Multi.run that inserts negative-delta `PointEntry` and decrements balance | `recognitions_test.exs:99-120` (asserts both ledger rows `[25, -25]` and balance back to `with_points - 25`) |
   | F.Recognitions.9 — 15-minute author edit/remove window | `@grace_window_seconds 15 * 60` at `lib/foyer/recognitions.ex:15` + `ensure_within_grace/1` at lines 212-214 + `ensure_sender/2` at 209-210 | `recognitions_test.exs:122-130` (aged to 20 min → `:outside_grace_window` for both update and remove) |
   | F.Recognitions.10 — public ↔ private visibility | `feed_public/0` at `lib/foyer/recognitions.ex:20-28` (public-only), `get_recognition!/2` at lines 56-64 (public OR sender OR recipient), **`received_by/2` and `given_by/2` at lines 31-52 (added in this pass — third-party viewers now see public-only)** | `recognitions_test.exs:132-141` (get_recognition!), `:143-160` (received_by + given_by, **added in this pass**), scaffold smoke `:271-285` (e2e via `/people/:id`, **added in this pass**) |

   The fix for F.Recognitions.10 is detailed under "Findings fixed in this pass"
   §1 below.

2. **Guidelines followed (TESTING_GUIDE.md).** ✔ `recognitions_test.exs` is
   `async: true` (line 2), uses real fixtures via `seed_scaffold!/0` (line 13),
   no `Mock`/`meck`, no `Application.put_env/3`. Each clause's test name carries
   the `F.Recognitions.<N>` number (12 of 12 lines starting `test "F.Recognitions...`).
   The scaffold smoke test file gains 2 e2e tests, both tagged `F.Recognitions.10`
   inline, and stays `async: true`. One nit: `recognitions_test.exs` is **not**
   `@moduletag :integration`, even though it inserts via `Repo` and asserts
   against it — the rest of the codebase's context tests have the same pattern
   (`Foyer.DataCase` already wraps every test in a sandbox transaction), so I'm
   not flagging it.

3. **Static checks clean.** ✔ after this pass:
   - `mix format --check-formatted` → clean
   - `mix compile --warnings-as-errors` → clean
   - `mix credo --strict` → 284 mods/funs, 0 issues
   - `mix dialyzer` → 2 warnings, 2 skipped via tightly-scoped
     `.dialyzer_ignore.exs`, "passed successfully" (exit 0). The 2 ignored are
     `call_without_opaque` false positives on `Ecto.Multi.new() |> Multi.insert /
     Multi.update` — a known Ecto/dialyxir interaction (linked from the ignore
     file). Pre-recognitions dialyzer was 0/0; the regression is entirely from
     this feature's Multi calls, so the ignore file is justified by this work.

4. **Test suite health.** ✔ 39 tests / 0 failures / 0.8s (was 35/0/0.7s before
   this pass; +3 ledger/visibility pinning tests + 1 smoke pinning test). Well
   under the 10s budget. A single change to `received_by`/`given_by`'s viewer
   filter fails exactly the 2 new unit tests + the 1 new smoke test pinned to
   it — no over-coupling.

5. **Database indexes.** ✔ for hot-path reads, with one polish follow-up:
   - `recognitions.recipient_id`, `sender_id`, `public`, `inserted_at` indexes
     already existed from `priv/repo/migrations/20260525124507_create_recognitions.exs:9-13`.
     `feed_public/0` filters on `public = true AND removed_at IS NULL` and
     orders by `inserted_at desc` — backed by the existing `public` and
     `inserted_at` indexes. The `removed_at IS NULL` filter is **not** backed by
     a partial index; the new migration `priv/repo/migrations/20260525140038_*.exs:10`
     created a regular index on `removed_at` instead, which Postgres won't use
     for `IS NULL` lookups efficiently. Marked as polish — see follow-up §1.
   - `recognition_point_entries(recognition_id)` index at
     `priv/repo/migrations/20260525140038_*.exs:22` — backs the test query at
     `recognitions_test.exs:94, 115`. Good.
   - `recognition_point_entries(user_id, inserted_at)` index at line 23 — no
     read path uses it today, but it's the obvious shape for a future "points
     history" view. Forward-looking, not wrong. Noted as follow-up §2.
   - `recognitions.removed_by_id` index at line 11 — no read path. Noted as
     follow-up §2.

6. **No N+1.** ✔ Every list read explicitly preloads `[:sender, :recipient]`:
   `feed_public/0` (line 25), `received_by/2` (line 38), `given_by/2` (line 51),
   `get_recognition!/2` (line 61). The Multi-step writes use `repo.insert` on a
   single `PointEntry` and `repo.update_all` on the user row — no per-row
   queries.

7. **Migration safety.** ✔ `20260525140038_*.exs` uses `change/0` with
   `alter table` + `add` (nullable columns, no defaults that rewrite existing
   rows) and `create table` for the brand-new `recognition_point_entries`.
   Reversibility confirmed by running `mix ecto.rollback --to 0` + `mix
   ecto.migrate` end-to-end — both directions succeed. `CREATE INDEX
   CONCURRENTLY` is not used; for this POC scaffold (no production data, tiny
   tables) that's acceptable per the same pragmatism used in earlier
   migrations.

8. **Context isolation.** ✔ The only cross-context coupling introduced is
   `Foyer.Profile` calling `Foyer.Recognitions.received_by/2`/`given_by/2`
   (sibling, not cousin — both are top-level Foyer.* contexts and Profile is
   explicitly the "orchestrator" per its `@moduledoc`). `Foyer.Today` already
   called `Recognitions.received_by/1` before this pass; updating that call
   site to pass viewer was a same-shape edit (`lib/foyer/today.ex:26`). The
   LiveView only talks to `FoyerWeb.LiveDeps.*` ports; the give/update/remove
   handlers in `lib/foyer_web/live/recognitions_live.ex:96-153` are thin shells
   that match on `:self_recognition`, `:invalid_point_tier`,
   `:outside_grace_window`, `:unauthorized` — all the failure atoms returned
   by the context. No bare ecto changeset shapes leak through.

9. **LiveView mount discipline.** ✔ `RecognitionsLive.mount/3` (lines 14-25)
   does pure assigns + `stream_configure`/`stream` — no DB. All loads happen
   in `handle_params/3` via `apply_index`, `apply_new`, `apply_show`,
   `apply_edit` (lines 27-93). Show/edit use try/rescue on `Ecto.NoResultsError`
   to redirect on out-of-scope IDs — this is fine because the underlying
   `get_recognition!/2` includes the visibility filter, so unauthorized reads
   bubble up as `NoResultsError` rather than a successful-but-leaky load. No
   PubSub subscription added → no terminate needed. No `assign_async` needed —
   the reads are single-Postgres roundtrips.

10. **Mobile responsiveness.** ✔ The new give-form (`recognitions_live.ex`
    lines 311-396) uses `flex flex-col gap-3` and `flex flex-wrap gap-2` for
    the values fieldset — phone-friendly out of the box. The bonus-tier
    `<div class="flex gap-2 mt-1">` at line 376 wraps natively. The shell
    (`foyer-root`/`foyer-scroll` from the scaffold) keeps the
    `padding-bottom: 5rem` for bottom-nav clearance below `md:`.

11. **Accessibility.** ✔ The bonus-tier picker (lines 374-390) uses a real
    `<fieldset>` with `<legend>Bonus points</legend>`. Each radio is wrapped
    in a `<label>` so click-anywhere and screen-reader announcement both work.
    The visibility radios (lines 350-371) have explicit text labels
    ("Public — visible on the House feed", "Private — just to the recipient")
    — better than icon-only. Remove button (lines 228-239) is a real
    `<button type="button">` with hero-icon + text "Remove", `id` for tests.

12. **No secrets in source.** ✔ `git diff config/` empty for this feature. No
    new env vars, no credentials in the migration or schemas.

13. **Telemetry / structured logging.** n/a — the spec doesn't require points
    events to emit telemetry, and no logging was added or removed. Worth
    revisiting once the points balance becomes user-visible across multiple
    surfaces (audit trail for managers).

## Findings fixed in this pass

### 1. F.Recognitions.10 leak: third-party viewers saw private recognitions on `/people/:id`

- **Files:** `lib/foyer/profile.ex:15-24` (was `profile_for/1` taking only the
  target user), `lib/foyer/recognitions.ex:31-52` (was `received_by/1` and
  `given_by/1` with no viewer scope), `lib/foyer_web/live/people_live.ex:38-46`
  (was `profile_for(target)`), `lib/foyer_web/live/profile_live.ex:30-35`,
  `lib/foyer/today.ex:26`.
- **Symptom:** F.Recognitions.10 says "private recognitions are visible only
  to sender and recipient." `Foyer.Profile.profile_for(target)` called
  `Recognitions.received_by(target)` which returned **every** recognition the
  target had received, regardless of `public`. So when Hugo (third party)
  opened `/people/<aisha.id>`, Aisha's profile card rendered the body of the
  private recognition Maya sent her. Same leak on `given_by` when viewing the
  sender's profile.
- **Change:** Widened the port + context signatures:
  - `Foyer.RecognitionsPort` (`lib/foyer/recognitions_port.ex:11-12`):
    `received_by/2` and `given_by/2` now take `(target :: User.t(), viewer :: User.t())`.
  - `Foyer.Recognitions` (`lib/foyer/recognitions.ex:32, 45`): query adds
    `where: r.public == true or r.sender_id == ^viewer_id or r.recipient_id == ^viewer_id`
    — the same predicate `get_recognition!/2` already used at line 59.
  - `Foyer.ProfilePort` + `Foyer.Profile`: `profile_for/2` takes
    `(target, viewer)`; passes viewer through.
  - `FoyerWeb.ProfileLive.handle_params/3`: `profile_for(scope.user, scope.user)`
    (viewer == target, so no filter).
  - `FoyerWeb.PeopleLive.apply_show/2`: `profile_for(target, current_scope.user)`
    — the real viewer.
  - `Foyer.Today.brief_for/1`: `received_by(user, user)` (briefing is always
    for the same user that's viewing).
- **Tests pinning it:**
  - `test/foyer/recognitions_test.exs:143-152` — `F.Recognitions.10 received_by
    hides private recognitions from third-party viewers` (asserts the private
    recognition shows for Aisha/Maya, not Hugo).
  - `test/foyer/recognitions_test.exs:154-160` — same for `given_by`.
  - `test/foyer_web/scaffold_smoke_test.exs:271-277` — e2e:
    `F.Recognitions.10 /people/:id hides private recognitions from third parties`
    asserts the body `"Handled the linen reset"` does **not** appear when Hugo
    opens Aisha's profile.
  - `test/foyer_web/scaffold_smoke_test.exs:279-285` — positive case: the same
    body **does** appear when Aisha opens her own `/people/:id`. Guards
    against a future over-filter that hides legitimate views.

### 2. Dialyzer regression: `call_without_opaque` on `Ecto.Multi.new() |> Multi.insert/update`

- **Files:** new `.dialyzer_ignore.exs` at the repo root, wired into `mix.exs:19`.
- **Symptom:** Before this feature, `mix dialyzer` exited 0 (verified by
  checking out the parent commit `2293bc7` and re-running). After the
  Recognitions commit, `mix dialyzer` reported 2 errors at
  `lib/foyer/recognitions.ex:93:18` and `:139:18` — both
  `call_without_opaque Type mismatch in call without opaque term in
  insert/update`. The warnings are the well-known dialyxir interaction with
  `Ecto.Multi`'s `@opaque t :: %Multi{...}` when chained from `Multi.new()`
  (the literal struct returned by `new/0` isn't recognized as the opaque
  type). The pipeline itself is the idiomatic Ecto pattern and is the shape
  the spec requires for F.Recognitions.7 and F.Recognitions.8.
- **Change:** Added `.dialyzer_ignore.exs` with a tight `{file,
  warning_type}` ignore scoped to `lib/foyer/recognitions.ex` only. The file
  comments the rationale and links to the upstream Ecto issue
  (https://github.com/elixir-ecto/ecto/issues/3825). `mix dialyzer` now
  reports `Total errors: 2, Skipped: 2, Unnecessary Skips: 0 / passed
  successfully` and exits 0. If a future edit removes the Multi calls (or
  adds a third one outside `recognitions.ex`), the skip count drifts and
  `Unnecessary Skips: > 0` or a new warning surfaces.

### 3. Test count and reference parity

- **Files:** `test/foyer/recognitions_test.exs:143-160` (+2 unit tests),
  `test/foyer_web/scaffold_smoke_test.exs:271-285` (+2 smoke tests, total +4).
- Before: 35 tests / 0.7s. After: 39 tests / 0.8s. Still well under budget.
- Every `F.Recognitions.<N>` clause now appears in at least one test name; the
  list at the top of this doc has the cross-references.

## Known follow-ups

### 1. `recognitions.removed_at` index is a regular index, not partial

- **File:** `priv/repo/migrations/20260525140038_*.exs:10`.
- **Symptom:** Every `feed_public/0`, `received_by/2`, `given_by/2`,
  `get_recognition!/2` query filters on `is_nil(r.removed_at)` (the "not
  removed" rows). A regular B-tree index on `removed_at` doesn't help
  Postgres find `WHERE removed_at IS NULL` efficiently — at scale Postgres
  will sequentially scan unless you add a partial index `WHERE removed_at
  IS NULL` (or invert: index the active rows). At POC volume (single-digit
  recognitions in fixtures) it's a non-issue, so I haven't churned the
  migration. Worth a separate migration once the table has real data.
- **Recommended:** `create index(:recognitions, [:inserted_at], where:
  "removed_at IS NULL")` to back the feed's `WHERE removed_at IS NULL ORDER
  BY inserted_at DESC` directly. The existing `[:inserted_at]` index from
  the create-recognitions migration can be dropped at the same time
  (subsumed by the partial).

### 2. Two indexes on the new schema have no read path yet

- **Files:** `priv/repo/migrations/20260525140038_*.exs:11`
  (`recognitions.removed_by_id`) and line 23
  (`recognition_point_entries(user_id, inserted_at)`).
- Both look forward-looking (who-removed-this audit, per-user points history)
  but no read path exists today. Either:
  - drop them now and reintroduce when the read path lands (purist, costs
    one extra migration later); or
  - leave them in (negligible write cost at POC scale, ready when the read
    paths arrive). I left them in. Worth a note in the next plan that
    introduces the corresponding read endpoints.

### 3. `update_recognition/3` does not reconcile point balance when `bonus_points` changes

- **File:** `lib/foyer/recognitions.ex:109-130`.
- **Symptom:** A manager-author can edit their recognition within the
  15-minute grace window. If the edit changes `bonus_points` (e.g. 25 → 50),
  the changeset is updated but **no** new `PointEntry` is written and the
  recipient's `points_balance` is not adjusted. The spec doesn't explicitly
  require it (F.Recognitions.9 says "Authors can edit or remove…" without
  spelling out what's editable; F.Recognitions.7's Multi rule is phrased for
  the give path), so this is the most likely real-world inconsistency the
  spec leaves under-defined.
- **Recommended:** Either (a) restrict the edit UI/context to non-points
  fields (body, values, public) and explicitly drop `bonus_points` from the
  cast in update mode, or (b) wrap `update_recognition/3` in an `Ecto.Multi`
  that writes a compensating `PointEntry` (delta = new - old) and updates
  the balance. Option (b) preserves the F.Recognitions.7 invariant; option
  (a) is simpler and matches the typical "give once, fix typos" UX. Worth a
  spec-clarifying conversation in the next plan.

### 4. No plan file in `docs/feature-groups/recognitions/plans/` before execute

- **File missing:** any `docs/feature-groups/recognitions/plans/00-*.md`.
- The Foyer workflow (`docs/WORKFLOW.md:44-58`) says a plan should be
  written, reviewed by Codex, and then executed. This feature was executed
  directly from the spec — there's no record of the design choices the
  executor made (point-tier whitelist vs. enum, soft-removal as nullable
  timestamps vs. a separate audit row, ledger schema shape). Future
  maintenance is harder without that artifact. **Not fixed in this pass** —
  a verify doc can't retroactively reconstruct a plan-review pass.
  Recommended: backfill a `00-recognitions-plan.md` from the implemented
  code, even if it post-dates execution, so the design rationale is
  recorded somewhere other than commit messages.

## Test/credo/format/dialyzer status (after fixes)

```
$ mix format --check-formatted    # clean
$ mix compile --warnings-as-errors # clean
$ mix credo --strict              # 0 issues, 284 mods/funs
$ mix test                        # 39 tests, 0 failures, 0.8s
$ mix dialyzer                    # 2 errors, 2 skipped, passed successfully (exit 0)
```

Test count went from 35 to 39 (+4 pinning tests). Suite is still well under the
10-second budget.
