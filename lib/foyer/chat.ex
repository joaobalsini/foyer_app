defmodule Foyer.Chat do
  @moduledoc """
  Chat context. Reads are real (with membership-authorized
  `get_conversation!/2`); `send_message/3` is stubbed until the Chat feature
  group lands.
  """
  @behaviour Foyer.ChatPort

  import Ecto.Query, warn: false

  alias Foyer.Accounts.User
  alias Foyer.Channels.Membership
  alias Foyer.Chat.Conversation
  alias Foyer.Chat.Message
  alias Foyer.Chat.Participant
  alias Foyer.Repo

  @impl true
  @spec inbox_for(User.t()) :: [Conversation.t()]
  def inbox_for(%User{id: user_id}) do
    conversations =
      from(c in Conversation,
        left_join: p in Participant,
        on: p.conversation_id == c.id and p.user_id == ^user_id,
        left_join: m in Membership,
        on: m.channel_id == c.channel_id and m.user_id == ^user_id,
        where:
          not is_nil(c.last_message_at) and
            (not is_nil(p.id) or not is_nil(m.id)),
        order_by: [desc: c.last_message_at],
        preload: [:channel, participants: :user]
      )
      |> Repo.all()

    conv_ids = Enum.map(conversations, & &1.id)

    latest_by_id =
      from(msg in Message,
        where: msg.conversation_id in ^conv_ids,
        distinct: msg.conversation_id,
        order_by: [asc: msg.conversation_id, desc: msg.inserted_at],
        preload: [:author]
      )
      |> Repo.all()
      |> Map.new(&{&1.conversation_id, &1})

    Enum.map(conversations, fn c ->
      latest = Map.get(latest_by_id, c.id)
      %{c | messages: if(latest, do: [latest], else: [])}
    end)
  end

  @impl true
  @spec get_conversation!(integer() | String.t(), User.t()) :: Conversation.t()
  def get_conversation!(id, %User{id: user_id}) do
    from(c in Conversation,
      left_join: p in Participant,
      on: p.conversation_id == c.id and p.user_id == ^user_id,
      left_join: m in Membership,
      on: m.channel_id == c.channel_id and m.user_id == ^user_id,
      where: c.id == ^id and (not is_nil(p.id) or not is_nil(m.id)),
      preload: [:channel, participants: :user]
    )
    |> Repo.one!()
  end

  @impl true
  @spec list_messages(Conversation.t()) :: [Message.t()]
  def list_messages(%Conversation{id: conv_id}) do
    from(m in Message,
      where: m.conversation_id == ^conv_id,
      order_by: [asc: m.inserted_at],
      preload: [:author]
    )
    |> Repo.all()
  end

  @impl true
  @spec compose_changeset(map()) :: Ecto.Changeset.t()
  def compose_changeset(attrs \\ %{}) do
    Message.changeset(%Message{}, attrs)
  end

  @impl true
  @spec send_message(Conversation.t(), User.t(), map()) ::
          {:ok, Message.t()} | {:error, Ecto.Changeset.t() | :not_implemented}
  def send_message(%Conversation{} = _conversation, %User{} = _author, _attrs) do
    {:error, :not_implemented}
  end
end
