defmodule Foyer.ProfileScenarios.Simple do
  @moduledoc """
  Profile world that returns a minimal Card for any user. Used by isolated
  PeopleLive `:show` tests that don't need to assert on recognition details.
  """
  @behaviour Foyer.ProfilePort

  alias Foyer.Profile.Card

  @impl true
  def profile_for(user, _viewer) do
    %Card{
      user: user,
      received: [],
      given: [],
      points: user.points_balance || 0,
      on_shift?: false,
      received_this_month: 0,
      points_earned: []
    }
  end

  @impl true
  def own_profile_for(user), do: profile_for(user, user)

  @impl true
  def rewards_catalog, do: []
end
