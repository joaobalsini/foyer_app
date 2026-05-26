defmodule Foyer.ChannelsScenarios.SingleChannel do
  @moduledoc """
  Channels port scenario: the user is a member of exactly one channel —
  `Foyer.HouseScenarios.Fixtures.channel/0`.

  Used by isolated announcement tests so `list_for_user/1` returns a
  predictable list (the compose form's `channel_id` select reads from this).
  """
  @behaviour Foyer.Channels.Behavior

  alias Foyer.HouseScenarios.Fixtures

  @impl true
  def list_for_user(_user), do: [Fixtures.channel()]

  @impl true
  def list_all_with_member_counts, do: [{Fixtures.channel(), 4}]

  @impl true
  def get!(_id), do: Fixtures.channel()

  @impl true
  def member?(_user, _channel), do: true

  @impl true
  def member_count(_channel), do: 4
end
