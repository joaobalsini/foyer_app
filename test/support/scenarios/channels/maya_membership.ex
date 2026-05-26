defmodule Foyer.ChannelsScenarios.MayaMembership do
  @moduledoc """
  Channels scenario: Maya is a member of the housekeeping floor 4 channel only.
  Drives the chat picker's channel list and the side-rail channel list.
  """
  @behaviour Foyer.Channels.Behavior

  alias Foyer.ChatScenarios.Fixtures

  @impl true
  def list_for_user(_user), do: [Fixtures.floor_4()]

  @impl true
  def list_all_with_member_counts, do: [{Fixtures.floor_4(), 4}]

  @impl true
  def get!(_id), do: Fixtures.floor_4()

  @impl true
  def member?(_user, _channel), do: true

  @impl true
  def member_count(_channel), do: 4
end
