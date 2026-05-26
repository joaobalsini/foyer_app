defmodule Foyer.Today.Behavior do
  @moduledoc """
  Behaviour for `Foyer.Today`. Read-only orchestrator across Shifts, House,
  and Recognitions — returns a typed `Foyer.Today.Briefing`. See plan §6.8 for
  the conscious "cousin calls" trade-off.
  """

  alias Foyer.Accounts.User
  alias Foyer.Today.Briefing

  @doc """
  Builds the Today briefing for the given user from shift, announcement, and
  recognition state.
  """
  @callback brief_for(User.t()) :: Briefing.t()
end
