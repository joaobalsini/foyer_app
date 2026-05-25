defmodule Foyer.House.AnnouncementRead do
  @moduledoc """
  Records that a `User` has seen an `Announcement`. Idempotent via
  the `(announcement_id, user_id)` unique index.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          announcement_id: integer() | nil,
          user_id: integer() | nil,
          read_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "announcement_reads" do
    belongs_to :announcement, Foyer.House.Announcement
    belongs_to :user, Foyer.Accounts.User
    field :read_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(read, attrs) do
    read
    |> cast(attrs, [:announcement_id, :user_id, :read_at])
    |> validate_required([:announcement_id, :user_id, :read_at])
    |> unique_constraint([:announcement_id, :user_id],
      name: :announcement_reads_announcement_id_user_id_index
    )
  end
end
