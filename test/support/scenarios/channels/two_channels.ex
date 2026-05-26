defmodule Foyer.ChannelsScenarios.TwoChannels do
  @moduledoc """
  A Channels world with two departments for isolated LiveView tests.

  Provides "Housekeeping · Floor 4" (id: 101) and "All Housekeeping" (id: 102),
  with stable IDs so tests can assert on them.
  """
  @behaviour Foyer.Channels.Behavior

  alias Foyer.Channels.Channel

  @floor_4 %Channel{
    id: 101,
    name: "Housekeeping · Floor 4",
    slug: "housekeeping-floor-4",
    kind: :department
  }

  @all_hk %Channel{
    id: 102,
    name: "All Housekeeping",
    slug: "all-housekeeping",
    kind: :department
  }

  @impl true
  def list_for_user(_user), do: [@all_hk, @floor_4]

  @impl true
  def list_all_with_member_counts, do: [{@all_hk, 7}, {@floor_4, 4}]

  @impl true
  def get!(101), do: @floor_4
  def get!(102), do: @all_hk
  def get!(id), do: raise(Ecto.NoResultsError, queryable: Channel, term: id)

  @impl true
  def member?(_user, _channel), do: true

  @impl true
  def member_count(%Channel{id: 101}), do: 4
  def member_count(%Channel{id: 102}), do: 7
  def member_count(_channel), do: 0

  @spec floor_4() :: Channel.t()
  def floor_4, do: @floor_4

  @spec all_hk() :: Channel.t()
  def all_hk, do: @all_hk
end
