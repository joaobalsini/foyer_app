defmodule Foyer.Profile do
  @moduledoc """
  Read-only profile orchestrator. Wraps Accounts + Recognitions + Shifts and
  returns a typed `Foyer.Profile.Card`. Keeps `FoyerWeb.ProfileLive` slim per
  "fat contexts, slim LiveViews".
  """
  @behaviour Foyer.ProfilePort

  alias Foyer.Accounts.User
  alias Foyer.Profile.Card
  alias Foyer.Recognitions
  alias Foyer.Shifts

  @impl true
  @spec profile_for(target :: User.t(), viewer :: User.t()) :: Card.t()
  def profile_for(%User{} = target, %User{} = viewer) do
    %Card{
      user: target,
      received: Recognitions.received_by(target, viewer),
      given: Recognitions.given_by(target, viewer),
      points: target.points_balance || 0,
      on_shift?: not is_nil(Shifts.current_shift_for(target))
    }
  end
end
