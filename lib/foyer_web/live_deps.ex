defmodule FoyerWeb.LiveDeps do
  @moduledoc """
  Dependency injection hub for LiveViews.

  Each function in this module resolves the configured implementation module for
  one context. Production config points at the real context; test config points
  at the corresponding Mox mock, allowing fast, isolated LiveView tests without
  touching the database or global `Application.put_env/3`.

  See `docs/TESTING_GUIDE.md` for the full pattern: behaviours, Mox mocks, and
  scenario modules.

  ## Usage

      house = FoyerWeb.LiveDeps.house()
      result = house.some_query(user)

  ## Adding a new context

  1. Define a port behaviour (`Foyer.SomePort`) with one `@callback` per function
     the LiveViews call.
  2. Implement the behaviour in the real context (`Foyer.Some`).
  3. Add a `Mox.defmock(Foyer.SomeMock, for: Foyer.SomePort)` call in
     `test/test_helper.exs`.
  4. Add an accessor here: `def some, do: Application.fetch_env!(:foyer, :some_context)`.
  5. Configure `:foyer, :some_context` in `config/dev.exs` and
     `config/test.exs` (pointing at the real module and the mock respectively).
  """
end
