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
      result = house.feed_for(user)

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

  @spec accounts() :: module()
  def accounts, do: Application.fetch_env!(:foyer, :accounts_context)

  @spec shifts() :: module()
  def shifts, do: Application.fetch_env!(:foyer, :shifts_context)

  @spec channels() :: module()
  def channels, do: Application.fetch_env!(:foyer, :channels_context)

  @spec house() :: module()
  def house, do: Application.fetch_env!(:foyer, :house_context)

  @spec recognitions() :: module()
  def recognitions, do: Application.fetch_env!(:foyer, :recognitions_context)

  @spec chat() :: module()
  def chat, do: Application.fetch_env!(:foyer, :chat_context)

  @spec profile() :: module()
  def profile, do: Application.fetch_env!(:foyer, :profile_context)

  @spec today() :: module()
  def today, do: Application.fetch_env!(:foyer, :today_context)
end
