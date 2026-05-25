# Scaffold — spec

The `scaffold` feature group has **no spec by direction of the user**.

The original ask was a single mobile-first UI scaffold that proves we can navigate every surface of the
product against mocked data, locking the LiveView modules, contexts, Ecto schemas, routes and visual system
in place so that subsequent feature-group work can proceed in parallel. Because the scaffold cuts across all
feature groups by design, expressing it in `F.<FirstWord>.<N>` clauses would either (a) be hollow — each
clause would just say "the surface exists" — or (b) duplicate clauses that the real feature groups
(`today/`, `house/`, `chat/`, …) will own.

Per the workflow in [docs/WORKFLOW.md](../../WORKFLOW.md), feature groups keep one spec per group. The
scaffold here exists purely as a planning artifact: a single plan under `plans/01-mobile-ui-scaffold.md`
that the implementing agent walks step by step, and a smoke test that proves the surfaces wire together.
Spec clauses live in the per-feature-group folders that follow (`docs/feature-groups/today/spec.md`,
`docs/feature-groups/house/spec.md`, …) and will be written as those groups are picked up.

Tests written from this plan should not reference `F.Scaffold.N` numbers — they should be tagged as
infrastructure / smoke tests instead.

See [`plans/01-mobile-ui-scaffold.md`](plans/01-mobile-ui-scaffold.md) for the concrete plan.
