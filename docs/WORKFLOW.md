# AI Workflow

Work flows through four phases: **spec → plan → execute → verify**. Different agents run different phases.
[FOYER.md](FOYER.md) is the product north star — every spec, plan, and verification step should align with its
principles.

## Feature groups

Documentation is organized by **feature group** under `feature-groups/<group>/`:

```
feature-groups/<group>/
  spec.md      # one spec for the group, in given/when/then format
  designs/     # mockups and visual artifacts
  plans/       # implementation plans
```

A feature group is **coarse-grained** — it covers a big space of the app, not a narrow slice. Each group maps
roughly to a Phoenix context (`Foyer.Chat`, `Foyer.House`, `Foyer.Shifts`, …) and the LiveView(s) that surface
it.

This layout exists to **parallelize feature development across groups**. Multiple groups can be worked on at
the same time without touching each other's files. Within a single group, we develop one feature at a time —
no parallel work inside the same group.

Spec clauses use the prefix `F.<FirstWord>.<N>` where `FirstWord` is the first word of the group name
(e.g. `F.Announcements.3`, `F.Today.5`). The prefix is stable across the group's lifetime; inserting a new
clause never forces renumbering across groups.

`plans/` typically starts with a single plan covering the group's initial implementation. As features are
revisited or added later, additional plan files accumulate alongside it.

## Spec

Specs describe what a feature group should do, before any code is written.

- Lives at `feature-groups/<group>/spec.md`.
- Written in given/when/then format.
- Each clause is numbered `F.<FirstWord>.<N>` (where `FirstWord` is the first word of the group name) so tests
  can pin to it and drift can be detected later.
- Revisit and refine specs as feature details emerge — they're a living artifact, not a one-shot.

## Plan

A plan turns a spec into a concrete implementation strategy.

- Lives under `feature-groups/<group>/plans/`.
- Step-by-step, in execution order.
- Identifies the files and modules each step touches.
- Calls out architectural trade-offs and risks.
- **Includes all Ecto schemas** the group needs — fields, types, relationships, validations. Concrete enough
  to be reviewed before any code is written.
- **Includes all public function signatures with `@spec` typespecs**, especially in contexts. The context API
  is the contract LiveViews and tests depend on; surfacing it in the plan makes design issues visible before
  implementation.
- **Reviewed by a Codex agent before execution.** Codex's job is to challenge the plan, not rubber-stamp it —
  surface missing edge cases, alternative approaches, and risks the primary agent might have glossed over.

## Execute

A **Sonnet agent** runs the execute loop, working through the plan step by step.

- Stay within the plan's scope — no drive-by refactors or speculative features.
- Review changes incrementally as they land, not batched at the end.
- After the last step, do a final pass across the feature to catch anything that fell through the cracks.

## Verify

An **Opus agent** verifies the implementation before the work is considered done. This is the most important
phase — it's what stops drift, regressions, and silent shortcuts from compounding.

- **Spec drift.** Re-read the `F.<FirstWord>.<N>` clauses touched. Confirm prose still matches what the code
  renders, returns, or persists. Fix whichever is wrong and pin the correct behaviour with a tight test
  assertion so the next drift fails loudly.
- **Guidelines followed.** Tests follow [TESTING_GUIDE.md](TESTING_GUIDE.md) (isolated by default, scenario
  modules for variations, `async: true` unless documented). Each spec feature has at least one e2e test
  mentioning its `F.<FirstWord>.<N>` number; related unit tests reference the same number.
- **Static checks clean.** `mix format`, `mix credo --strict`, and `mix dialyzer` all pass.
- **Test suite health.** Full suite runs in under 10 seconds on a laptop. A single logic change fails one unit
  test and at most one or two integration tests.
- **Database indexes.** Every query introduced by the feature relies on an existing or newly added index. No
  accidental table scans on hot paths.
- **No N+1 queries.** Preloads or explicit joins on any list endpoint that loads associations.
- **Migration safety.** Migrations are reversible (`up`/`down` or `change` with `execute`-aware fallbacks).
  `CREATE INDEX CONCURRENTLY` on non-trivial tables. No destructive defaults that rewrite existing rows
  silently.
- **Context isolation.** Modules talk to parents, children, and siblings — not cousins. APIs between
  application parts are tested at the boundary.
- **LiveView mount discipline.** Expensive loads happen in `handle_params/3`, not `mount/3`. `mount/3` does no
  blocking external calls. PubSub subscriptions are torn down on terminate. Async work uses
  `assign_async`/`start_async`.
- **Mobile responsiveness.** Each surface renders correctly at phone width — not just desktop. Today especially
  is a phone-first surface.
- **Accessibility.** Keyboard navigation works, focus is managed across LiveView updates, color contrast meets
  WCAG AA, interactive elements have ARIA labels where the visual label is missing or ambiguous.
- **No secrets in source.** Config and runtime read credentials from env vars (e.g. `DATABASE_URL`). No tokens,
  keys, or passwords committed.
- **Telemetry and structured logging.** Meaningful events emit a telemetry span or structured log line with the
  fields a future operator would need to debug them (user id, channel id, request path, etc.).
