defmodule Foyer.ChatPort do
  @moduledoc """
  Behaviour for `Foyer.Chat`.
  """

  alias Foyer.Accounts.User
  alias Foyer.Chat.Conversation
  alias Foyer.Chat.Message

  @callback open_direct(User.t(), User.t()) ::
              {:ok, Conversation.t()} | {:error, Ecto.Changeset.t() | :invalid_direct}
  @callback open_channel(User.t(), integer() | String.t()) ::
              {:ok, Conversation.t()} | {:error, Ecto.Changeset.t() | :unauthorized}
  @callback inbox_for(User.t()) :: [Conversation.t()]
  @callback get_conversation!(integer() | String.t(), User.t()) :: Conversation.t()
  @callback get_or_create_direct_conversation(User.t(), User.t()) ::
              {:ok, Conversation.t()} | {:error, Ecto.Changeset.t()}
  @callback list_messages(Conversation.t()) :: [Message.t()]
  @callback compose_changeset(map()) :: Ecto.Changeset.t()
  @callback send_message(Conversation.t(), User.t(), map()) ::
              {:ok, Message.t()} | {:error, Ecto.Changeset.t() | :unauthorized}
  @callback mark_read(Conversation.t(), User.t()) ::
              {:ok, non_neg_integer()} | {:error, :unauthorized}
  @callback unread_count(User.t()) :: non_neg_integer()
end
