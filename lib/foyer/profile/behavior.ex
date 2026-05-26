defmodule Foyer.Profile.Behavior do
  @moduledoc """
  Behaviour for `Foyer.Profile`. Read-only orchestrator that wraps Accounts +
  Recognitions + Shifts and returns a typed `Foyer.Profile.Card` DTO.

  `profile_for/2` is viewer-aware and enforces F.Profile.6 at the context
  boundary — callers receive a Card already stripped of private recognitions
  and the given list when `viewer != subject`. See `own_profile_for/1` for the
  `/me` convenience.
  """

  alias Foyer.Accounts.User
  alias Foyer.Profile.Card
  alias Foyer.Profile.RewardItem

  @callback profile_for(subject :: User.t(), viewer :: User.t()) :: Card.t()
  @callback own_profile_for(User.t()) :: Card.t()
  @callback rewards_catalog() :: [RewardItem.t()]
end
