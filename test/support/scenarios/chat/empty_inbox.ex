defmodule Foyer.ChatScenarios.EmptyInbox do
  @moduledoc """
  Chat scenario: the inbox is empty (no conversations with messages yet).
  Pins F.Chat.5 — empty conversations are excluded from the rendered inbox.
  """
  @behaviour Foyer.ChatPort

  alias Foyer.ChatScenarios.Fixtures

  @impl true
  def inbox_for(_user), do: []

  @impl true
  def unread_count(_user), do: 0

  @impl true
  def open_direct(_user, %{id: id}) do
    {:ok, %{Fixtures.direct_maya_charlotte() | id: id, last_message_at: nil}}
  end

  @impl true
  def get_or_create_direct_conversation(user, colleague), do: open_direct(user, colleague)

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
  def list_messages(_conversation), do: []

  @impl true
  def compose_changeset(attrs) do
    Foyer.Chat.compose_changeset(attrs)
  end

  @impl true
  def send_message(_conversation, _user, _attrs) do
    {:ok, Fixtures.direct_message(900, 50, Fixtures.maya().id, "stub")}
  end

  @impl true
  def mark_read(_conversation, _user), do: {:ok, 0}
end
