# Testing Guide

This guide covers testing conventions for Foyer — the general philosophy that applies to every test, and the
LiveView-specific layering that follows from it.

Reference: https://cdegroot.com/elixir/2026/03/09/elixir-testing.html

## Core Philosophy

Tests verify logic, not the framework. A unit test covers **one function**. External libraries (Ecto, DateTime,
Phoenix) are trusted — don't test them unless verifying your integration with them.

## ExUnit Defaults

- `async: true` is the default. `async: false` requires a comment explaining why.
- `@tag :integration` marks tests that cross layer boundaries (e.g. database-backed tests).
- Keep integration tests minimal — they exist to verify layers connect, not to re-test logic.

## What to Test

- The logic of the function under test, isolated from its collaborators.
- Edge cases in your code, not in library behavior.
- Integration points sparingly: one or two tests confirming the layers connect.

## Test Doubles

- **No `Mock` or `meck`** — these couple tests to implementation details.
- Prefer **dependency injection via default arguments** for simple cases.
- Use **`Mox`** for complex interface boundaries where a behaviour is defined. For LiveViews specifically, see
  the [Dependency Injection](#dependency-injection), [Behaviours and Mox](#behaviours-and-mox), and
  [Scenario Modules](#scenario-modules) sections below.

## Test Suite Health

Two litmus tests:

1. Change a single piece of logic → only **1 unit test** and **1–2 integration tests** should fail. More failures
   indicate over-integration.
2. The full suite should complete in **under 10 seconds** on a laptop. Use `mix test --slowest` to find
   bottlenecks.

## Clarity

Tests should read like a story. No unnecessary setup, no teardown rituals, no noise that obscures what's being
verified.

## Context Isolation

Keep context isolation as much as possible. A module should talk to its parent, children, and siblings, but not
to its cousins. Test APIs between parts of the application at a high level rather than reaching across module
boundaries to assert internal state.

## Specs and Tests

Specs live at `docs/feature-groups/<group>/spec.md` in `given/when/then` format with `F.<FirstWord>.<N>` clause
numbering (where `FirstWord` is the first word of the feature group name, e.g. `F.Announcements.3`). Tests
should reference the clauses they cover:

- Unit tests that exercise a specific spec clause mention its number in the test name or describe block.
- Each major feature has at least one end-to-end test pinned to its `F.<FirstWord>.<N>` number, so the
  overarching behaviour is covered by something that exercises the real path.

Before concluding any work that touched a spec clause, re-read the prose and confirm it still matches what the
code does. Tests assert what the code *does*; the spec asserts what it *should* do. If the two drift, fix
whichever is wrong — and prefer pinning the correct behaviour with a tight test assertion so the next drift
fails loudly.

## LiveView Testing

Foyer uses two levels of LiveView tests. Most behaviour tests are isolated and dependency-injected. A smaller
set of smoke tests use the real router, plugs, database, and seeds to prove the application is wired together.
The remainder of this guide covers how to structure both layers.

### Goals

- Keep most LiveView tests fast and focused.
- Avoid depending on global seed shape for ordinary UI-state tests.
- Avoid per-test global configuration changes.
- Keep route/on-mount/database coverage where it matters.

### Test Layers

#### Isolated LiveView Tests

Isolated LiveView tests cover UI states and interactions inside a single surface — rendering branches, empty
states, form validation, event handling, and state transitions driven by injected fake data. They mount the
LiveView directly with `live_isolated/3`, skipping the router, plugs, `live_session`, and `on_mount` hooks. They
do not require seeds or the database; collaborators are provided through explicit dependencies.

#### Route Smoke Tests

Route smoke tests cover end-to-end wiring — that the app boots, routes resolve, plugs run, on-mount hooks load
shared assigns, authorization gates fire, and the layout renders against real seeded data. They use regular
`live(conn, path)` against the real router and database. Their job is wiring confidence, not exhaustive UI-state
coverage, so keep them to a handful per surface.

### Dependency Injection

LiveViews should avoid calling concrete contexts directly when the dependency is useful to fake in tests.

Instead of calling a context module directly:

```elixir
result = Foyer.House.some_query(user)
```

prefer resolving the dependency through `LiveDeps`:

```elixir
house = FoyerWeb.LiveDeps.house()
result = house.some_query(user)
```

`FoyerWeb.LiveDeps` exposes one accessor per context, each resolving a configured module:

```elixir
defmodule FoyerWeb.LiveDeps do
  def house, do: Application.fetch_env!(:foyer, :house_context)
  # …one accessor per context the LiveViews need.
end
```

Production config points at the real context (`Foyer.House`). Test config points at a Mox mock (`Foyer.HouseMock`).
Do not change these modules per test with `Application.put_env/3` — per-test config mutation is global and makes
async tests unsafe.

### Behaviours and Mox

Define small behaviours around the read-side functions a LiveView needs. Keep them narrow — only the calls the
LiveViews actually make, not the whole context API.

```elixir
defmodule Foyer.HousePort do
  @callback some_query(user :: term()) :: list()
  # …one @callback per function the LiveView calls on this context.
end
```

The real context implements the behaviour:

```elixir
defmodule Foyer.House do
  @behaviour Foyer.HousePort
end
```

Mocks are defined once in `test/test_helper.exs`, one per port:

```elixir
Mox.defmock(Foyer.HouseMock, for: Foyer.HousePort)
# …one defmock per context.
```

Use private Mox mode with ordinary per-test expectations:

```elixir
setup :verify_on_exit!
```

### Scenario Modules

Prefer named scenario modules over inline `expect/3` calls when a test wants a particular "shape of the world."
Scenario modules are plain modules that implement a port behaviour and describe one variation of the world the
LiveView is rendered against. `Mox.stub_with/2` swaps the scenario in per test.

```elixir
defmodule Foyer.HouseScenarios.Empty do
  @behaviour Foyer.HousePort

  def some_query(_user), do: []
end

defmodule Foyer.HouseScenarios.Busy do
  @behaviour Foyer.HousePort

  def some_query(_user), do: [build_item(), build_item()]
end
```

In a test, delegate the mock to the scenario:

```elixir
setup do
  Mox.stub_with(Foyer.HouseMock, Foyer.HouseScenarios.Busy)
  :ok
end

test "renders pending items", %{conn: conn} do
  {:ok, _view, html} = live_isolated(conn, FoyerWeb.TodayLive, session: session())
  assert html =~ "expected copy"
end
```

Why scenarios over raw `expect/3`:

- The test reads as "given a busy day, then…" instead of "given this exact sequence of three function calls."
- Scenarios are reused across tests — one place to update when a port's contract changes.
- The `@behaviour` annotation catches typos at compile time, so a renamed callback fails the build rather than a
  single test.
- Tests stay focused on the LiveView's behaviour, not on bookkeeping which mock function returned what.

When to keep `expect/3` instead:

- Asserting that a specific function was called (e.g. "submitting the form calls the create function exactly once
  with these args").
- One-off variations that don't deserve a named module.

Mix freely: `stub_with/2` for the default world, `expect/3` for the assertion you actually care about.

Organize scenario modules under `test/support/scenarios/` so they're compiled in the test environment only.
Group them by port and name them after the situation, not the data (`Empty`, `Busy`, `WithErrors` — not
`UserWithZeroItems`).

### `live_isolated`

Use `live_isolated/3` to mount a LiveView directly, without the router.

```elixir
{:ok, view, html} =
  live_isolated(conn, FoyerWeb.SomeLive,
    session: %{
      "current_user" => user
      # …any other assigns the layout/LiveView expects.
    }
  )
```

`live_isolated/3` skips:

- router pipelines
- plugs
- `live_session`
- normal `on_mount` hooks
- route authorization

That is the point. It tests the LiveView surface without proving the whole app boot path.

Because Foyer LiveViews will rely on shared assigns normally provided by on-mount hooks (current user, navigation
context, anything the rail/bottom nav reads), isolated tests need a small harness or setup helper that provides
those assigns.

### Test Harness

For isolated tests, use a small test-only wrapper or helper that sets the common assigns before mounting the target
LiveView. The harness should provide whatever the layout and target LiveView read from `socket.assigns` — at minimum
the current user, plus anything the surrounding chrome (rail, bottom navigation, headers) renders against.

Keep the harness test-only. It should not add mock module names or test-only flags to production routes.

### Mox and LiveView Processes

Mox expectations are owned by the test process. LiveViews run in their own process.

After `live_isolated/3` returns, allow the LiveView pid to use the mocks:

```elixir
{:ok, view, _html} = live_isolated(conn, FoyerWeb.SomeLive, session: session)

Mox.allow(Foyer.SomeMock, self(), view.pid)
```

This works for events and PubSub callbacks after mount.

Mount-time calls are different: there is no `view.pid` until mount finishes. For those cases, prefer one of these:

- pass preloaded assigns through the isolated harness
- move loading into a function that can be tested separately
- keep that behaviour in a route smoke test if it is truly wiring-level

Avoid global Mox mode unless there is a specific reason. Private mode keeps tests isolated.

### What Belongs Where

Use isolated tests for:

- rendering branches
- empty states
- button presence
- form validation UI
- event handling after mount
- LiveView state transitions that can be driven with fake context responses

Use route smoke tests for:

- plugs and demo user selection
- role and shift gates on routes
- layout assign wiring
- assumptions about seeded users and data
- one happy path per major surface

### Rule of Thumb

If the test is asking, “does this screen behave correctly for this data?”, use `live_isolated/3` and injected
dependencies.

If the test is asking, “does the whole application route, authorize, load shared assigns, and render?”, use the real
route and the database.
