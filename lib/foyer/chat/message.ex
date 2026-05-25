defmodule Foyer.Chat.Message do
  @moduledoc """
  Chat message. Belongs to a `Conversation` and an `author` user. Body is
  limited to 4_000 chars.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          conversation_id: integer() | nil,
          author_id: integer() | nil,
          body: String.t() | nil,
          inserted_at: DateTime.t() | nil
        }

  schema "chat_messages" do
    belongs_to :conversation, Foyer.Chat.Conversation
    belongs_to :author, Foyer.Accounts.User
    field :body, :string

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:conversation_id, :author_id, :body])
    |> validate_required([:conversation_id, :author_id, :body])
    |> validate_length(:body, min: 1, max: 4_000)
  end
end
