defmodule Foyer.Chat.ConversationTest do
  @moduledoc """
  Unit tests for `Foyer.Chat.Conversation` changeset and pure helpers
  (`direct_key/1`, kind/channel-pair validation). No Repo. Uniqueness via
  the database index lives in `test/foyer/chat_test.exs`.

  Covers:
    F.Chat.1 — canonical direct_key encoding (`min_uid-max_uid`)
    F.Chat.2 — kind/channel_id pairing validation
  """
  use ExUnit.Case, async: true

  alias Foyer.Chat.Conversation

  describe "F.Chat.1 — direct_key/1 canonical encoding" do
    test "encodes as min_uid-max_uid regardless of input order" do
      assert Conversation.direct_key([5, 2]) == "2-5"
      assert Conversation.direct_key([2, 5]) == "2-5"
    end

    test "equal ids produce a degenerate key (Validate.direct_pair guards this upstream)" do
      assert Conversation.direct_key([7, 7]) == "7-7"
    end
  end

  describe "F.Chat.2 — changeset kind/channel_id pairing" do
    test "channel kind without channel_id is invalid" do
      cs = Conversation.changeset(%Conversation{}, %{kind: :channel})
      refute cs.valid?
      assert cs.errors[:channel_id] != nil
    end

    test "direct kind with a channel_id is invalid" do
      cs = Conversation.changeset(%Conversation{}, %{kind: :direct, channel_id: 1})
      refute cs.valid?
      assert cs.errors[:channel_id] != nil
    end

    test "direct kind without channel_id is valid (direct_key may be set)" do
      cs =
        Conversation.changeset(%Conversation{}, %{
          kind: :direct,
          participant_user_ids: [1, 2]
        })

      assert cs.valid?
      assert Ecto.Changeset.get_change(cs, :direct_key) == "1-2"
    end

    test "channel kind with channel_id is valid" do
      cs = Conversation.changeset(%Conversation{}, %{kind: :channel, channel_id: 9})
      assert cs.valid?
    end

    test "missing kind is invalid" do
      cs = Conversation.changeset(%Conversation{}, %{})
      refute cs.valid?
      assert {"can't be blank", _} = cs.errors[:kind]
    end
  end
end
