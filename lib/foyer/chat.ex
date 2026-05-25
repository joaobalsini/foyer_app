defmodule Foyer.Chat do
  @moduledoc """
  Chat context.
  """
  @behaviour Foyer.ChatPort

  import Ecto.Query, warn: false

  alias Foyer.Accounts.User
  alias Foyer.Channels.Membership
  alias Foyer.Chat.Conversation
  alias Foyer.Chat.Message
  alias Foyer.Chat.MessageRead
  alias Foyer.Chat.Participant
  alias Foyer.Repo

  @impl true
  @spec open_direct(User.t(), User.t()) ::
          {:ok, Conversation.t()} | {:error, Ecto.Changeset.t() | :invalid_direct}
  def open_direct(%User{id: user_id}, %User{id: user_id}), do: {:error, :invalid_direct}

  def open_direct(%User{id: a_id}, %User{id: b_id}) do
    participant_ids = Enum.sort([a_id, b_id])
    direct_key = Conversation.direct_key(participant_ids)

    case Repo.transaction(fn -> upsert_direct(direct_key, participant_ids) end) do
      {:ok, conversation} -> {:ok, conversation}
      {:error, reason} -> {:error, reason}
    end
  end

  defp upsert_direct(direct_key, participant_ids) do
    conversation =
      case Repo.get_by(Conversation, kind: :direct, direct_key: direct_key) do
        nil -> create_direct(direct_key, participant_ids)
        existing -> existing
      end

    preload_conversation(conversation)
  end

  defp create_direct(direct_key, participant_ids) do
    conversation = insert_or_fetch_direct(direct_key, participant_ids)
    insert_direct_participants(conversation, participant_ids)
    conversation
  end

  defp insert_or_fetch_direct(direct_key, participant_ids) do
    %Conversation{}
    |> Conversation.changeset(%{
      kind: :direct,
      direct_key: direct_key,
      participant_user_ids: participant_ids
    })
    |> Repo.insert()
    |> case do
      {:ok, conversation} ->
        conversation

      {:error, %Ecto.Changeset{}} ->
        Repo.get_by!(Conversation, kind: :direct, direct_key: direct_key)
    end
  end

  defp insert_direct_participants(%Conversation{id: conversation_id}, participant_ids) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows =
      Enum.map(participant_ids, fn participant_id ->
        %{
          conversation_id: conversation_id,
          user_id: participant_id,
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(Participant, rows, on_conflict: :nothing)
  end

  @impl true
  @spec open_channel(User.t(), integer() | String.t()) ::
          {:ok, Conversation.t()} | {:error, Ecto.Changeset.t() | :unauthorized}
  def open_channel(%User{id: user_id}, channel_id) do
    if member_of_channel?(channel_id, user_id) do
      find_or_create_channel(channel_id)
    else
      {:error, :unauthorized}
    end
  end

  defp find_or_create_channel(channel_id) do
    case Repo.get_by(Conversation, kind: :channel, channel_id: channel_id) do
      nil -> insert_channel_conversation(channel_id)
      conversation -> {:ok, preload_conversation(conversation)}
    end
  end

  defp insert_channel_conversation(channel_id) do
    %Conversation{}
    |> Conversation.changeset(%{kind: :channel, channel_id: channel_id})
    |> Repo.insert()
    |> case do
      {:ok, conversation} ->
        {:ok, preload_conversation(conversation)}

      {:error, %Ecto.Changeset{} = changeset} ->
        recover_channel_conversation(channel_id, changeset)
    end
  end

  defp recover_channel_conversation(channel_id, changeset) do
    case Repo.get_by(Conversation, kind: :channel, channel_id: channel_id) do
      nil -> {:error, changeset}
      conversation -> {:ok, preload_conversation(conversation)}
    end
  end

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
        order_by: [asc: msg.conversation_id, desc: msg.inserted_at, desc: msg.id],
        preload: [:author]
      )
      |> Repo.all()
      |> Map.new(&{&1.conversation_id, &1})

    unread_by_id = unread_counts_by_conversation(user_id, conv_ids)

    Enum.map(conversations, fn c ->
      latest = Map.get(latest_by_id, c.id)
      unread_count = Map.get(unread_by_id, c.id, 0)

      %{
        c
        | messages: if(latest, do: [latest], else: []),
          unread?: unread_count > 0,
          unread_count: unread_count
      }
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
  @spec get_or_create_direct_conversation(User.t(), User.t()) ::
          {:ok, Conversation.t()} | {:error, Ecto.Changeset.t()}
  def get_or_create_direct_conversation(%User{id: user_id}, %User{id: other_user_id}) do
    direct_key = Conversation.direct_key([user_id, other_user_id])

    case Repo.get_by(Conversation, direct_key: direct_key) do
      %Conversation{} = conversation ->
        {:ok, Repo.preload(conversation, participants: :user)}

      nil ->
        create_direct_conversation(user_id, other_user_id, direct_key)
    end
  end

  defp create_direct_conversation(user_id, other_user_id, direct_key) do
    Repo.transaction(fn ->
      {:ok, conversation} = insert_direct_conversation(direct_key, [user_id, other_user_id])
      insert_direct_participants!(conversation.id, [user_id, other_user_id])
      Repo.preload(conversation, participants: :user)
    end)
    |> case do
      {:ok, conversation} -> {:ok, conversation}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
    end
  end

  defp insert_direct_conversation(direct_key, participant_user_ids) do
    %Conversation{}
    |> Conversation.changeset(%{
      kind: :direct,
      direct_key: direct_key,
      participant_user_ids: participant_user_ids
    })
    |> Repo.insert()
  end

  defp insert_direct_participants!(conversation_id, user_ids) do
    for user_id <- user_ids do
      %Participant{}
      |> Participant.changeset(%{
        conversation_id: conversation_id,
        user_id: user_id
      })
      |> Repo.insert!()
    end
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
          {:ok, Message.t()} | {:error, Ecto.Changeset.t() | :unauthorized}
  def send_message(%Conversation{} = conversation, %User{} = author, attrs) do
    conversation = ensure_conversation_loaded(conversation)

    if conversation_member?(conversation, author.id) do
      do_send_message(conversation, author, attrs)
    else
      {:error, :unauthorized}
    end
  end

  defp do_send_message(conversation, author, attrs) do
    changeset = message_changeset(conversation, author, attrs)

    if changeset.valid? do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      persist_and_broadcast(conversation, author, changeset, now)
    else
      {:error, changeset}
    end
  end

  defp persist_and_broadcast(conversation, author, changeset, now) do
    case Repo.transaction(fn ->
           insert_message_with_side_effects(conversation, author, changeset, now)
         end) do
      {:ok, message} ->
        broadcast_message(conversation, message)
        {:ok, message}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp insert_message_with_side_effects(conversation, author, changeset, now) do
    message =
      changeset
      |> Repo.insert!()
      |> Repo.preload(:author)

    conversation
    |> Ecto.Changeset.change(last_message_at: now)
    |> Repo.update!()

    %MessageRead{}
    |> MessageRead.changeset(%{message_id: message.id, user_id: author.id, read_at: now})
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:message_id, :user_id])

    message
  end

  @impl true
  @spec mark_read(Conversation.t(), User.t()) ::
          {:ok, non_neg_integer()} | {:error, :unauthorized}
  def mark_read(%Conversation{} = conversation, %User{id: user_id} = user) do
    conversation = ensure_conversation_loaded(conversation)

    if conversation_member?(conversation, user_id) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      message_ids =
        from(m in Message,
          where: m.conversation_id == ^conversation.id,
          select: m.id
        )
        |> Repo.all()

      rows =
        Enum.map(message_ids, fn message_id ->
          %{
            message_id: message_id,
            user_id: user_id,
            read_at: now,
            inserted_at: now,
            updated_at: now
          }
        end)

      {count, _} =
        Repo.insert_all(MessageRead, rows,
          on_conflict: :nothing,
          conflict_target: [:message_id, :user_id]
        )

      broadcast_inbox(user)
      {:ok, count}
    else
      {:error, :unauthorized}
    end
  end

  @impl true
  @spec unread_count(User.t()) :: non_neg_integer()
  def unread_count(%User{id: user_id}) do
    Message
    |> visible_unread_query(user_id)
    |> select([msg], count(msg.id))
    |> Repo.one()
  end

  defp visible_unread_query(query, user_id) do
    from(msg in query,
      join: c in Conversation,
      on: c.id == msg.conversation_id,
      left_join: p in Participant,
      on: p.conversation_id == c.id and p.user_id == ^user_id,
      left_join: membership in Membership,
      on: membership.channel_id == c.channel_id and membership.user_id == ^user_id,
      left_join: read in MessageRead,
      on: read.message_id == msg.id and read.user_id == ^user_id,
      where:
        msg.author_id != ^user_id and is_nil(read.id) and
          (not is_nil(p.id) or not is_nil(membership.id))
    )
  end

  defp unread_counts_by_conversation(_user_id, []), do: %{}

  defp unread_counts_by_conversation(user_id, conv_ids) do
    Message
    |> visible_unread_query(user_id)
    |> where([msg], msg.conversation_id in ^conv_ids)
    |> group_by([msg], msg.conversation_id)
    |> select([msg], {msg.conversation_id, count(msg.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp member_of_channel?(channel_id, user_id) do
    from(m in Membership,
      where: m.channel_id == ^channel_id and m.user_id == ^user_id,
      select: true,
      limit: 1
    )
    |> Repo.exists?()
  end

  defp conversation_member?(%Conversation{kind: :direct, participants: participants}, user_id)
       when is_list(participants) do
    Enum.any?(participants, &(&1.user_id == user_id))
  end

  defp conversation_member?(%Conversation{kind: :channel, channel_id: channel_id}, user_id) do
    member_of_channel?(channel_id, user_id)
  end

  defp ensure_conversation_loaded(%Conversation{} = conversation) do
    Repo.preload(conversation, [:channel, participants: :user])
  end

  defp preload_conversation(%Conversation{} = conversation) do
    Repo.preload(conversation, [:channel, participants: :user], force: true)
  end

  defp message_changeset(%Conversation{} = conversation, %User{} = author, attrs) do
    %Message{}
    |> Message.changeset(
      attrs
      |> Map.take(["body", :body])
      |> Map.put("conversation_id", conversation.id)
      |> Map.put("author_id", author.id)
    )
  end

  defp broadcast_message(%Conversation{} = conversation, %Message{} = message) do
    Phoenix.PubSub.broadcast(
      Foyer.PubSub,
      "chat:room:#{conversation.id}",
      {:chat_message, message}
    )

    conversation
    |> recipient_user_ids()
    |> Enum.uniq()
    |> Enum.each(fn user_id ->
      Phoenix.PubSub.broadcast(
        Foyer.PubSub,
        "chat:inbox:#{user_id}",
        {:chat_inbox_updated, conversation.id}
      )
    end)
  end

  defp broadcast_inbox(%User{id: user_id}) do
    Phoenix.PubSub.broadcast(
      Foyer.PubSub,
      "chat:inbox:#{user_id}",
      {:chat_unread_updated, user_id}
    )
  end

  defp recipient_user_ids(%Conversation{kind: :direct, participants: participants}) do
    Enum.map(participants, & &1.user_id)
  end

  defp recipient_user_ids(%Conversation{kind: :channel, channel_id: channel_id}) do
    from(m in Membership, where: m.channel_id == ^channel_id, select: m.user_id)
    |> Repo.all()
  end

  # Owned by feature/chat; this branch carries a local copy until that branch lands on main.
  @impl true
  @spec unread_since(User.t(), DateTime.t() | nil) :: non_neg_integer()
  def unread_since(%User{id: user_id}, since) do
    query =
      from(msg in Message,
        join: c in Conversation,
        on: c.id == msg.conversation_id,
        left_join: p in Participant,
        on: p.conversation_id == c.id and p.user_id == ^user_id,
        left_join: m in Membership,
        on: m.channel_id == c.channel_id and m.user_id == ^user_id,
        left_join: r in MessageRead,
        on: r.message_id == msg.id and r.user_id == ^user_id,
        where:
          msg.author_id != ^user_id and
            (not is_nil(p.id) or not is_nil(m.id)) and
            is_nil(r.id),
        select: count(msg.id)
      )

    query =
      if is_nil(since) do
        query
      else
        from([msg] in query, where: msg.inserted_at > ^since)
      end

    Repo.one!(query)
  end
end
