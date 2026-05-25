defmodule Foyer.Chat.Participant do
  @moduledoc """
  Join row between a `Conversation` (direct only) and a `User`. Two rows per
  direct conversation, one per participant. Channel conversations leave this
  table empty and use `Membership` for audience.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          conversation_id: integer() | nil,
          user_id: integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "conversation_participants" do
    belongs_to :conversation, Foyer.Chat.Conversation
    belongs_to :user, Foyer.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(participant, attrs) do
    participant
    |> cast(attrs, [:conversation_id, :user_id])
    |> validate_required([:conversation_id, :user_id])
    |> unique_constraint([:conversation_id, :user_id])
  end
end
