defmodule Foyer.ChannelsScenarios.Empty do
  @moduledoc """
  Empty Channels world for isolated LiveView tests.

  Every read returns an empty result. Use when the test does not depend on
  any channel data.
  """
  @behaviour Foyer.Channels.Behavior

  alias Foyer.Channels.Channel

  @impl true
  def list_for_user(_user), do: []

  @impl true
  def list_all_with_member_counts, do: []

  @impl true
  def get!(id), do: raise(Ecto.NoResultsError, queryable: Channel, term: id)

  @impl true
  def member?(_user, _channel), do: false

  @impl true
  def member_count(_channel), do: 0
end
