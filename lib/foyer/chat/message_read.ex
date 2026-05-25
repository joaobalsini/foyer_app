defmodule Foyer.Chat.MessageRead do
  @moduledoc """
  Records that a `User` has seen a `Message`. Idempotent via the
  `(message_id, user_id)` unique index.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          message_id: integer() | nil,
          user_id: integer() | nil,
          read_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "chat_message_reads" do
    belongs_to :message, Foyer.Chat.Message
    belongs_to :user, Foyer.Accounts.User
    field :read_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(read, attrs) do
    read
    |> cast(attrs, [:message_id, :user_id, :read_at])
    |> validate_required([:message_id, :user_id, :read_at])
    |> unique_constraint([:message_id, :user_id])
  end
end
