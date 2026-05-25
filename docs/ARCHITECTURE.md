# Architecture and development guidelines

## Phoenix LiveView, single Elixir codebase

The brief is stack-agnostic but lists Elixir / TS / React / RN as preferred. LiveView wins this brief
specifically because:

- The product is **collaborative by default** — every surface needs to update on someone else's action (a
  message arrives, an announcement is published, a shift ends, an ack lands). LiveView + PubSub gives you that
  for free; a SPA equivalent is a websocket-and-state-management problem with twice the moving parts.
- One language for server, view, and real-time transport keeps the AI workflow tight — agents don't have to
  context-switch between Elixir contexts, TS types, and a React store on every ticket.
- Phoenix's "context" pattern matches the "context isolation" rule cleanly.

## Fat contexts, slim LiveViews

Business logic lives in contexts (`Foyer.House`, `Foyer.Chat`, `Foyer.Shifts`, …). LiveViews are thin shells:
they load data from contexts, route events back to them, and render. This keeps business logic testable in
isolation and keeps LiveView tests focused on rendering and event handling.

## Contexts are behaviours

Each context that LiveViews depend on defines a port behaviour (`Foyer.HousePort`, `Foyer.ChatPort`, …). The
real context implements the port; tests swap in scenario modules via Mox to exercise any data shape without
touching seeds. See [TESTING_GUIDE.md](TESTING_GUIDE.md) for the full pattern.

## Expensive work in `handle_params/3`, not `mount/3`

`mount/3` runs twice (HTTP render and LiveView socket) — keep it cheap. `handle_params/3` runs once per URL
change and is the right place for database loads and other expensive setup. Use `assign_async`/`start_async`
when the work can run in the background.

## Typed boundaries — no bare maps

Don't pass bare maps or generic params between modules. Type things explicitly so Dialyzer can catch
mismatches before tests do.

- **Ecto schemas** carry an explicit `@type t` declaration alongside the `schema` block. Don't rely on Ecto's
  implicit struct typing alone.
- **Non-Ecto in-memory shapes** (DTOs, value objects, intermediate data passed between contexts and LiveViews)
  use [`typed_struct`](https://hexdocs.pm/typed_struct/) rather than naked maps. The library gives you a
  struct plus a `@type t` for free.
- **Function signatures** include `@spec` annotations, especially across module boundaries (contexts ↔
  LiveViews, contexts ↔ contexts). The plan phase already requires this for context-public functions; carry
  the same discipline into internal helpers when the shape isn't obvious.

The goal: surface type drift as a Dialyzer warning, not as a runtime crash discovered by a test or — worse —
in production.

## Elixir code style

Follow the [Elixir style guide](https://hexdocs.pm/elixir_style_guide/readme.html) with one exception:

**Omit parentheses** on these Phoenix macros: `attr`, `embed_templates`, `field`, `plug`, `slot`, `socket`.

```elixir
# Good
attr :id, :string, required: true

# Bad
attr(:id, :string, required: true)
```

## Environment configuration

All environment-specific configuration is read from environment variables **at runtime**, not baked in at
compile time. The same compiled artifact must run in dev, test, staging, and production without rebuilding.

- **`DATABASE_URL`** is the canonical way to point at a database — username, password, host, port, and
  database name all encoded into one URL. No separate config knobs for each piece.
- **Test environment uses `TEST_DATABASE_URL`**, separate from `DATABASE_URL`, so dev and test never share a
  database.
- **`config/runtime.exs` reads env vars**; `config/{dev,test,prod}.exs` does not. Runtime config keeps the
  compile-time output environment-agnostic.
- **Committed `.envrc` provides safe defaults** that work out of the box against the Postgres bundled by
  `flake.nix`. Per-developer overrides and real secrets go in **`.envrc.local`** (gitignored), bootstrapped
  from a committed `.envrc.local.sample`.
- **Reproducible toolchain** — Nix + direnv (or `.tool-versions` for asdf/mise users) pin Elixir, Erlang,
  Node, and Postgres versions so every contributor's environment matches CI.

## Editor tooling

Use [ElixirLS](https://github.com/elixir-lsp/elixir-ls) in your editor while developing. It surfaces compile
errors, Dialyzer warnings, and type information inline — catching issues at the moment of writing rather than
on the next `mix dialyzer` run. The typed-boundaries discipline above only pays off if you see violations as
you type.
