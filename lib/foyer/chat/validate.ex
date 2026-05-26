defmodule Foyer.Chat.Validate do
  @moduledoc """
  Pure validation and visibility helpers for `Foyer.Chat`.

  Nothing in this module talks to `Foyer.Repo` or `Phoenix.PubSub`. Every
  function here is deterministic given its inputs so it can be unit-tested
  without seeds. Repo-bound work (membership lookups, channel recipient
  expansion, conversation upserts) stays in `Foyer.Chat`.
  """

  alias Foyer.Chat.Conversation
  alias Foyer.Chat.Message
  alias Foyer.Chat.Participant

  @doc """
  Canonicalises a direct pair, rejecting the self-direct case.

  Returns `{:ok, [low, high]}` with the two user ids sorted ascending so the
  caller can build the canonical `direct_key`. Returns
  `{:error, :invalid_direct}` when both ids refer to the same user.
  """
  @spec direct_pair(integer(), integer()) ::
          {:ok, [integer()]} | {:error, :invalid_direct}
  def direct_pair(user_id, user_id), do: {:error, :invalid_direct}

  def direct_pair(a_id, b_id) when is_integer(a_id) and is_integer(b_id) do
    {:ok, Enum.sort([a_id, b_id])}
  end

  @doc """
  Returns `true` if `user_id` participates in the direct conversation.

  Pure list scan — the participants must already be loaded by the caller.
  Channel-kind membership is enforced by `Foyer.Chat` against the database
  because it needs a `Membership` lookup.
  """
  @spec direct_member?([Participant.t()], integer()) :: boolean()
  def direct_member?(participants, user_id) when is_list(participants) do
    Enum.any?(participants, &(&1.user_id == user_id))
  end

  @doc """
  Extracts recipient user ids from a loaded direct conversation's
  participants. Pure list mapping; channel recipients come from `Membership`
  and are resolved in `Foyer.Chat`.
  """
  @spec direct_recipient_ids([Participant.t()]) :: [integer()]
  def direct_recipient_ids(participants) when is_list(participants) do
    Enum.map(participants, & &1.user_id)
  end

  @doc """
  Builds the attribute map fed to `Foyer.Chat.Message.changeset/2`.

  Normalises mixed `"body"`/`:body` keys (LiveView form payloads use string
  keys, internal callers use atoms), drops anything else the caller may have
  passed, and stamps the `conversation_id`/`author_id` so the changeset
  validation can run. Purely a `Map` reshuffle — no database, no side
  effects.
  """
  @spec compose_message_attrs(Conversation.t(), integer(), map()) :: map()
  def compose_message_attrs(%Conversation{id: conversation_id}, author_id, attrs)
      when is_integer(author_id) do
    attrs
    |> Map.take(["body", :body])
    |> Map.put("conversation_id", conversation_id)
    |> Map.put("author_id", author_id)
  end

  @doc """
  Convenience wrapper that returns the `%Message{}` changeset built from
  normalised attrs. Stays pure — `Message.changeset/2` does not touch the
  Repo.
  """
  @spec message_changeset(Conversation.t(), integer(), map()) :: Ecto.Changeset.t()
  def message_changeset(%Conversation{} = conversation, author_id, attrs) do
    Message.changeset(%Message{}, compose_message_attrs(conversation, author_id, attrs))
  end
end
