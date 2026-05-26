defmodule Foyer.Chat.ValidateTest do
  @moduledoc """
  Unit tests for `Foyer.Chat.Validate`. Pure functions only — no Repo, no
  PubSub. Tests that need real persistence (uniqueness via index, membership
  joins, broadcast emission) stay in `test/foyer/chat_test.exs`.

  Covers:
    F.Chat.2 — self-direct rejected (pure dispatch, no DB)
    F.Chat.4 — direct membership check (pure participants list scan; the
               channel branch stays DB-bound in Foyer.Chat)
    F.Chat.6 — message attr normalisation feeding Message.changeset
  """
  use ExUnit.Case, async: true

  alias Foyer.Chat.Conversation
  alias Foyer.Chat.Participant
  alias Foyer.Chat.Validate

  describe "F.Chat.2 — direct_pair/2 self-direct rejection and canonical sort" do
    test "returns {:error, :invalid_direct} when both ids match" do
      assert {:error, :invalid_direct} = Validate.direct_pair(7, 7)
    end

    test "sorts a two-id pair ascending" do
      assert {:ok, [3, 9]} = Validate.direct_pair(9, 3)
    end

    test "is order-independent so the canonical key is stable" do
      assert Validate.direct_pair(1, 2) == Validate.direct_pair(2, 1)
    end

    test "preserves an already-sorted pair" do
      assert {:ok, [1, 2]} = Validate.direct_pair(1, 2)
    end
  end

  describe "F.Chat.4 — direct_member?/2 participants scan" do
    test "true when the user_id is present" do
      participants = [%Participant{user_id: 1}, %Participant{user_id: 2}]
      assert Validate.direct_member?(participants, 1)
      assert Validate.direct_member?(participants, 2)
    end

    test "false when the user_id is absent" do
      participants = [%Participant{user_id: 1}, %Participant{user_id: 2}]
      refute Validate.direct_member?(participants, 3)
    end

    test "false for an empty participants list" do
      refute Validate.direct_member?([], 1)
    end
  end

  describe "direct_recipient_ids/1" do
    test "maps participants to their user_ids in order" do
      participants = [%Participant{user_id: 4}, %Participant{user_id: 7}]
      assert Validate.direct_recipient_ids(participants) == [4, 7]
    end

    test "returns [] for an empty participants list" do
      assert Validate.direct_recipient_ids([]) == []
    end
  end

  describe "F.Chat.6 — compose_message_attrs/3 normalises author/conversation ids" do
    test "passes string body through and stamps ids" do
      conversation = %Conversation{id: 11}

      attrs = Validate.compose_message_attrs(conversation, 42, %{"body" => "hi"})

      assert attrs == %{"body" => "hi", "conversation_id" => 11, "author_id" => 42}
    end

    test "accepts atom :body keys for internal callers" do
      conversation = %Conversation{id: 11}

      attrs = Validate.compose_message_attrs(conversation, 42, %{body: "hi"})

      assert attrs == %{:body => "hi", "conversation_id" => 11, "author_id" => 42}
    end

    test "drops unrelated keys" do
      conversation = %Conversation{id: 11}

      attrs =
        Validate.compose_message_attrs(conversation, 42, %{
          "body" => "hi",
          "author_id" => 999,
          "ignored" => "x"
        })

      assert attrs == %{"body" => "hi", "conversation_id" => 11, "author_id" => 42}
    end
  end

  describe "F.Chat.6 — message_changeset/3 builds a validatable changeset" do
    test "valid attrs yield a valid changeset" do
      conversation = %Conversation{id: 11}

      cs = Validate.message_changeset(conversation, 42, %{"body" => "hi"})

      assert cs.valid?
      assert Ecto.Changeset.get_change(cs, :body) == "hi"
      assert Ecto.Changeset.get_change(cs, :conversation_id) == 11
      assert Ecto.Changeset.get_change(cs, :author_id) == 42
    end

    test "blank body is rejected by Message.changeset" do
      conversation = %Conversation{id: 11}

      cs = Validate.message_changeset(conversation, 42, %{"body" => ""})

      refute cs.valid?
      assert cs.errors[:body] != nil
    end

    test "body over 4_000 characters is rejected" do
      conversation = %Conversation{id: 11}

      cs = Validate.message_changeset(conversation, 42, %{"body" => String.duplicate("a", 4_001)})

      refute cs.valid?
      assert cs.errors[:body] != nil
    end
  end
end
