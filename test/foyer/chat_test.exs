defmodule Foyer.ChatTest do
  @moduledoc """
  DB-backed context tests for `Foyer.Chat`. These exercise canonical
  conversation uniqueness (direct + channel) via the database unique
  indexes, membership-gated reads and writes via joins, broadcast emission,
  and multi-step persistence — all of which are fundamental to the chat
  invariants and need a real Repo to verify. Pure validation/visibility
  helpers are unit-tested in `test/foyer/chat/validate_test.exs` and
  schema-level changeset rules in `test/foyer/chat/conversation_test.exs`.
  The LiveView surface is covered by isolated tests in
  `test/foyer_web/chat_live_test.exs`.

  Covers:
    F.Chat.1 — direct conversation is canonical per pair (DB unique index)
    F.Chat.3 — channel conversation is unique per channel (DB unique index)
    F.Chat.4 — channel membership gates open/get (DB join)
    F.Chat.5 — empty conversations excluded from inbox (DB query)
    F.Chat.6 — send_message persists, broadcasts, and gates on membership
               (DB + PubSub)
    F.Chat.7 — mark_read is idempotent and membership-gated (DB unique
               index)
    F.Chat.8 — unread count excludes own messages and respects visibility
               (DB query)
    F.Chat.9 — inbox enrichment shape (DB query)
  """
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

  test "F.Chat.1 opens one canonical two-person direct conversation", ctx do
    assert {:ok, conversation} = Chat.open_direct(ctx.maya, ctx.hugo)
    assert conversation.kind == :direct
    assert conversation.direct_key == Conversation.direct_key([ctx.maya.id, ctx.hugo.id])

    assert Repo.aggregate(
             from(p in Participant, where: p.conversation_id == ^conversation.id),
             :count
           ) == 2

    assert {:ok, same_conversation} = Chat.open_direct(ctx.hugo, ctx.maya)
    assert same_conversation.id == conversation.id
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
end
