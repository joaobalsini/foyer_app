defmodule Foyer.ChatPort do
  @moduledoc """
  Behaviour for `Foyer.Chat`. `send_message/3` is stubbed until the Chat
  feature group lands.
  """

  alias Foyer.Accounts.User
  alias Foyer.Chat.Conversation
  alias Foyer.Chat.Message

  @callback inbox_for(User.t()) :: [Conversation.t()]
  @callback get_conversation!(integer() | String.t(), User.t()) :: Conversation.t()
  @callback get_or_create_direct_conversation(User.t(), User.t()) ::
              {:ok, Conversation.t()} | {:error, Ecto.Changeset.t()}
  @callback list_messages(Conversation.t()) :: [Message.t()]
  @callback compose_changeset(map()) :: Ecto.Changeset.t()
  @callback send_message(Conversation.t(), User.t(), map()) ::
              {:ok, Message.t()} | {:error, Ecto.Changeset.t() | :not_implemented}
end
