defmodule Foyer.ProfilePort do
  @moduledoc """
  Behaviour for `Foyer.Profile`. Read-only orchestrator that wraps Accounts +
  Recognitions + Shifts and returns a typed `Foyer.Profile.Card` DTO.
  """

  alias Foyer.Accounts.User
  alias Foyer.Profile.Card

  @callback profile_for(target :: User.t(), viewer :: User.t()) :: Card.t()
end
