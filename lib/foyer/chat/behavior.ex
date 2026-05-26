defmodule Foyer.Chat.Behavior do
  @moduledoc """
  Behaviour for `Foyer.Chat`.
  """

  alias Foyer.Accounts.User
  alias Foyer.Chat.Conversation
  alias Foyer.Chat.Message

  @doc """
  Opens or creates a direct conversation between two distinct users.
  """
  @callback open_direct(User.t(), User.t()) ::
              {:ok, Conversation.t()} | {:error, Ecto.Changeset.t() | :invalid_direct}

  @doc """
  Opens or creates a channel conversation when the user is a member of the
  channel.
  """
  @callback open_channel(User.t(), integer() | String.t()) ::
              {:ok, Conversation.t()} | {:error, Ecto.Changeset.t() | :unauthorized}

  @doc """
  Returns conversations visible to the user, ordered by latest message.
  """
  @callback inbox_for(User.t()) :: [Conversation.t()]

  @doc """
  Fetches a conversation visible to the user.

  Raises when the conversation is missing or unavailable to the user.
  """
  @callback get_conversation!(integer() | String.t(), User.t()) :: Conversation.t()

  @doc """
  Returns an existing direct conversation for the users or creates it.
  """
  @callback get_or_create_direct_conversation(User.t(), User.t()) ::
              {:ok, Conversation.t()} | {:error, Ecto.Changeset.t()}

  @doc """
  Lists messages for a conversation in chronological order.
  """
  @callback list_messages(Conversation.t()) :: [Message.t()]

  @doc """
  Builds a changeset for composing a chat message.

  Expected attrs may use string or atom keys:

    * `"body"` / `:body` - required message body, 1 to 4,000 characters.
  """
  @callback compose_changeset(map()) :: Ecto.Changeset.t()

  @doc """
  Sends a message when the author is a member of the conversation.

  Expected attrs may use string or atom keys:

    * `"body"` / `:body` - required message body, 1 to 4,000 characters.

  The context sets `conversation_id` and `author_id`; callers must not provide
  those fields as trusted input.
  """
  @callback send_message(Conversation.t(), User.t(), map()) ::
              {:ok, Message.t()} | {:error, Ecto.Changeset.t() | :unauthorized}

  @doc """
  Marks visible messages in the conversation as read for the user.
  """
  @callback mark_read(Conversation.t(), User.t()) ::
              {:ok, non_neg_integer()} | {:error, :unauthorized}

  @doc """
  Counts unread messages visible to the user.
  """
  @callback unread_count(User.t()) :: non_neg_integer()
end
