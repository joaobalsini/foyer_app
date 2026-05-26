defmodule Foyer.AccountsScenarios.PeopleWithOffShift do
  @moduledoc """
  Accounts scenario: returns four pickable people — Maya, Charlotte, Hugo, and
  Jamal — and resolves `get_user/1` for the same set. Jamal is the off-shift
  colleague (driven by `Foyer.ShiftsScenarios.MayaCharlotteHugoOn`).
  """
  @behaviour Foyer.Accounts.Behavior

  alias Foyer.ChatScenarios.Fixtures

  @impl true
  def list_pickable_users, do: people()

  @impl true
  def list_people(_opts), do: people()

  @impl true
  def get_user(id) when is_integer(id) do
    Enum.find(people(), fn u -> u.id == id end)
  end

  def get_user(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> get_user(int)
      _ -> nil
    end
  end

  defp people, do: [Fixtures.maya(), Fixtures.charlotte(), Fixtures.hugo(), Fixtures.jamal()]
end
