defmodule Foyer.ChatTest do
  use Foyer.DataCase, async: true

  import FoyerWeb.ScaffoldFixtures

  alias Foyer.Channels.Channel
  alias Foyer.Chat
  alias Foyer.Chat.Conversation
  alias Foyer.Chat.Message
  alias Foyer.Chat.MessageRead
  alias Foyer.Chat.Participant
  alias Foyer.Repo

  setup do
    {:ok, seed_scaffold!()}
  end

  test "F.Chat.1/F.Chat.2 opens one canonical two-person direct conversation", ctx do
    assert {:ok, conversation} = Chat.open_direct(ctx.maya, ctx.hugo)
    assert conversation.kind == :direct
    assert conversation.direct_key == Conversation.direct_key([ctx.maya.id, ctx.hugo.id])

    assert Repo.aggregate(
             from(p in Participant, where: p.conversation_id == ^conversation.id),
             :count
           ) == 2

    assert {:ok, same_conversation} = Chat.open_direct(ctx.hugo, ctx.maya)
    assert same_conversation.id == conversation.id
    assert {:error, :invalid_direct} = Chat.open_direct(ctx.maya, ctx.maya)
  end

  test "F.Chat.3/F.Chat.4 opens one channel conversation only for channel members", ctx do
    floor_4 = Repo.get_by!(Channel, name: "Housekeeping · Floor 4")
    leadership = Repo.get_by!(Channel, name: "Leadership")

    assert {:ok, conversation} = Chat.open_channel(ctx.maya, floor_4.id)
    assert conversation.kind == :channel
    assert conversation.channel_id == floor_4.id

    assert {:ok, same_conversation} = Chat.open_channel(ctx.hugo, floor_4.id)
    assert same_conversation.id == conversation.id
    assert {:error, :unauthorized} = Chat.open_channel(ctx.maya, leadership.id)
  end

  test "F.Chat.5/F.Chat.9 inbox excludes empty conversations and enriches latest unread state",
       ctx do
    assert {:ok, empty_dm} = Chat.open_direct(ctx.maya, ctx.hugo)

    inbox = Chat.inbox_for(ctx.maya)
    refute Enum.any?(inbox, &(&1.id == empty_dm.id))

    seeded_dm = Enum.find(inbox, &(&1.id == ctx.maya_charlotte.id))
    assert [%Message{body: "Confirmed in 412."}] = seeded_dm.messages
    assert seeded_dm.unread?
    assert seeded_dm.unread_count == 1
  end

  test "F.Chat.6 sends with membership enforcement, read receipt, timestamps, and PubSub", ctx do
    Phoenix.PubSub.subscribe(Foyer.PubSub, "chat:room:#{ctx.maya_charlotte.id}")
    Phoenix.PubSub.subscribe(Foyer.PubSub, "chat:inbox:#{ctx.charlotte.id}")

    assert {:ok, message} =
             Chat.send_message(ctx.maya_charlotte, ctx.maya, %{
               "body" => "Fresh towels are staged."
             })

    assert_receive {:chat_message, ^message}
    assert_receive {:chat_inbox_updated, conversation_id}
    assert conversation_id == ctx.maya_charlotte.id

    conversation = Repo.get!(Conversation, ctx.maya_charlotte.id)
    assert conversation.last_message_at

    assert Repo.exists?(
             from(r in MessageRead,
               where: r.message_id == ^message.id and r.user_id == ^ctx.maya.id
             )
           )

    assert {:error, :unauthorized} =
             Chat.send_message(ctx.maya_charlotte, ctx.rafael, %{"body" => "No access"})
  end

  test "F.Chat.7/F.Chat.8 mark_read is idempotent and clears visible unread messages", ctx do
    assert Chat.unread_count(ctx.maya) == 1

    assert {:ok, inserted} = Chat.mark_read(ctx.maya_charlotte, ctx.maya)
    assert inserted == 2
    assert {:ok, 0} = Chat.mark_read(ctx.maya_charlotte, ctx.maya)
    assert Chat.unread_count(ctx.maya) == 0

    assert {:error, :unauthorized} = Chat.mark_read(ctx.maya_charlotte, ctx.rafael)
  end

  test "F.Today.20 unread_since counts eligible unread messages since last shift only", ctx do
    since = DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)

    floor_4 = Repo.get_by!(Channel, name: "Housekeeping · Floor 4")
    leadership = Repo.get_by!(Channel, name: "Leadership")

    {:ok, floor_conversation} = Chat.open_channel(ctx.maya, floor_4.id)
    {:ok, leadership_conversation} = Chat.open_channel(ctx.charlotte, leadership.id)

    {:ok, _channel_unread} =
      Chat.send_message(floor_conversation, ctx.hugo, %{"body" => "Fresh channel update."})

    {:ok, _own_message} =
      Chat.send_message(floor_conversation, ctx.maya, %{"body" => "I am already handling this."})

    {:ok, read_message} =
      Chat.send_message(ctx.maya_charlotte, ctx.charlotte, %{"body" => "Read this one."})

    {:ok, _read} =
      %MessageRead{}
      |> MessageRead.changeset(%{
        message_id: read_message.id,
        user_id: ctx.maya.id,
        read_at: DateTime.utc_now()
      })
      |> Repo.insert()

    {:ok, old_message} =
      Chat.send_message(ctx.maya_charlotte, ctx.charlotte, %{"body" => "Before last shift."})

    old_inserted_at = DateTime.add(since, -1, :second)

    Repo.update_all(
      from(m in Message, where: m.id == ^old_message.id),
      set: [inserted_at: old_inserted_at]
    )

    {:ok, _non_member_message} =
      Chat.send_message(leadership_conversation, ctx.rafael, %{"body" => "Managers only."})

    assert Chat.unread_since(ctx.maya, since) == 2
  end
end
