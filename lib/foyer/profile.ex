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
  @spec profile_for(User.t()) :: Card.t()
  def profile_for(%User{} = user) do
    %Card{
      user: user,
      received: Recognitions.received_by(user),
      given: Recognitions.given_by(user),
      points: user.points_balance || 0,
      on_shift?: not is_nil(Shifts.current_shift_for(user))
    }
  end
end
