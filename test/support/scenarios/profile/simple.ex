defmodule Foyer.ProfileScenarios.Simple do
  @moduledoc """
  Profile world that returns a minimal Card for any user. Used by isolated
  PeopleLive `:show` tests that don't need to assert on recognition details.
  """
  @behaviour Foyer.ProfilePort

  alias Foyer.Profile.Card

  @impl true
  def profile_for(user) do
    %Card{
      user: user,
      received: [],
      given: [],
      points: user.points_balance || 0,
      on_shift?: false
    }
  end
end
