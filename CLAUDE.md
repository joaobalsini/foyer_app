# Claude Code — Foyer

## About

Foyer is a staff communications platform for luxury hotel groups. See [docs/FOYER.md](docs/FOYER.md) for the
full product description.

## Stack

Elixir 1.19
Erlang 28
Phoenix Liveview 1.1.30
PostgreSQL 17
Node.js 22 LTS (npm 10.x) — bundled with Node 22; used for Phoenix asset tooling (esbuild/tailwind via Mix, plus any direct JS deps)
Nix and direnv to manage the stack

## Architecture and development guidelines

Two layers — read both:

- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — Foyer-specific architecture rules and development
  guidelines (fat contexts, port behaviours, `handle_params/3` over `mount/3`, typed boundaries, Elixir
  code style, environment configuration, editor tooling, …).
- **[AGENTS.md](AGENTS.md)** — Framework-level guidelines shipped by Phoenix / LiveView (Phoenix v1.8
  conventions, `Layouts.app` usage, `current_scope`, `<.input>` / `<.icon>` components, Tailwind v4
  import syntax, `mix precommit`, Elixir/OTP idioms, …). Treat as authoritative for Phoenix and LiveView
  patterns; when it conflicts with `docs/ARCHITECTURE.md`, the Foyer doc wins because it is the
  project-specific layer on top.

## Feature groups

Documentation is organized by **feature group** under `docs/feature-groups/<group>/` (one `spec.md`,
`designs/`, `plans/` per group). See [docs/WORKFLOW.md](docs/WORKFLOW.md) for the full layout, the
parallelism rationale, and the `F.<FirstWord>.<N>` spec prefix scheme.

## AI Conventions

Work flows through four phases: **spec → plan → execute → verify**, run by different agents (Codex reviews
the plan, Sonnet executes, Opus verifies). See [docs/WORKFLOW.md](docs/WORKFLOW.md) for the full workflow,
including the verify checklist.

## Build & Test

```bash
# Elixir
mix test                          # run tests
MIX_ENV=test mix test             # explicit test env
mix format                        # format code
mix credo --strict                # static analysis (must pass cleanly under --strict)
mix dialyzer                      # static analysis
```

## Testing

See [docs/TESTING_GUIDE.md](docs/TESTING_GUIDE.md).
