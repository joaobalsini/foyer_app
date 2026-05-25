defmodule Foyer.ChatScenarios.WithUnread do
  @moduledoc """
  Chat scenario: the inbox contains one direct conversation with one unread
  message. Pins F.Chat.8 (unread count rendering) and F.Chat.9 (inbox
  enrichment: latest message + unread state).
  """
  @behaviour Foyer.ChatPort

  alias Foyer.ChatScenarios.Fixtures

  @impl true
  def inbox_for(_user), do: [Fixtures.direct_maya_charlotte(unread?: true, unread_count: 1)]

  @impl true
  def unread_count(_user), do: 1

  @impl true
  def open_direct(user_a, user_b) do
    if user_a.id == user_b.id do
      {:error, :invalid_direct}
    else
      {:ok, Fixtures.direct_maya_charlotte()}
    end
  end

  @impl true
  def get_or_create_direct_conversation(user, colleague) do
    case open_direct(user, colleague) do
      {:error, :invalid_direct} -> {:error, Foyer.Chat.compose_changeset(%{})}
      result -> result
    end
  end

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
    case conversation.kind do
      :direct ->
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

      :channel ->
        []
    end
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
  def mark_read(_conversation, _user), do: {:ok, 2}
end
