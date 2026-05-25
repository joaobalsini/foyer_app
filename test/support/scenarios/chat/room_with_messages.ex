defmodule Foyer.ChatScenarios.RoomWithMessages do
  @moduledoc """
  Chat scenario: an open room with two messages already in it and no unread
  count. Used for room-panel tests where the focus is event handling
  (compose submit, mark_read trigger), not inbox enrichment.
  """
  @behaviour Foyer.ChatPort

  alias Foyer.ChatScenarios.Fixtures

  @impl true
  def inbox_for(_user), do: [Fixtures.direct_maya_charlotte(unread?: false, unread_count: 0)]

  @impl true
  def unread_count(_user), do: 0

  @impl true
  def open_direct(_user, _colleague), do: {:ok, Fixtures.direct_maya_charlotte()}

  @impl true
  def open_channel(_user, channel_id) when is_integer(channel_id) do
    {:ok, %{Fixtures.channel_floor_4() | id: channel_id}}
  end

  def open_channel(_user, channel_id) when is_binary(channel_id) do
    open_channel(nil, String.to_integer(channel_id))
  end

  @impl true
  def get_conversation!(id, _user) when is_integer(id) do
    %{Fixtures.direct_maya_charlotte() | id: id}
  end

  def get_conversation!(id, user) when is_binary(id) do
    get_conversation!(String.to_integer(id), user)
  end

  @impl true
  def list_messages(conversation) do
    [
      Fixtures.direct_message(
        100,
        conversation.id,
        Fixtures.charlotte().id,
        "Morning Maya - guest in 412 needs the laminated card on the door."
      ),
      Fixtures.direct_message(
        101,
        conversation.id,
        Fixtures.maya().id,
        "Confirmed in 412."
      )
    ]
  end

  @impl true
  def compose_changeset(attrs) do
    Foyer.Chat.compose_changeset(attrs)
  end

  @impl true
  def send_message(_conversation, _user, %{"body" => body}) do
    {:ok, Fixtures.direct_message(900, 50, Fixtures.maya().id, body)}
  end

  def send_message(_conversation, _user, %{body: body}) do
    {:ok, Fixtures.direct_message(900, 50, Fixtures.maya().id, body)}
  end

  @impl true
  def mark_read(_conversation, _user), do: {:ok, 0}
end
