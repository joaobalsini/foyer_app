defmodule Foyer.House.AnnouncementAck do
  @moduledoc """
  Records that a `User` has acknowledged an `Announcement` (the "I've read &
  understood" CTA on the detail page). Idempotent via the `(announcement_id,
  user_id)` unique index.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          announcement_id: integer() | nil,
          user_id: integer() | nil,
          ack_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "announcement_acks" do
    belongs_to :announcement, Foyer.House.Announcement
    belongs_to :user, Foyer.Accounts.User
    field :ack_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(ack, attrs) do
    ack
    |> cast(attrs, [:announcement_id, :user_id, :ack_at])
    |> validate_required([:announcement_id, :user_id, :ack_at])
    |> unique_constraint([:announcement_id, :user_id],
      name: :announcement_acks_announcement_id_user_id_index
    )
  end
end
