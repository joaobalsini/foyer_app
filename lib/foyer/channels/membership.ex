defmodule Foyer.Channels.Membership do
  @moduledoc """
  Join row between a `User` and a `Channel`. Uniqueness on
  `(user_id, channel_id)` is enforced at the DB level — see plan §5.13.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          user_id: integer() | nil,
          channel_id: integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "channel_memberships" do
    belongs_to :user, Foyer.Accounts.User
    belongs_to :channel, Foyer.Channels.Channel

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:user_id, :channel_id])
    |> validate_required([:user_id, :channel_id])
    |> unique_constraint([:user_id, :channel_id],
      name: :channel_memberships_user_id_channel_id_index
    )
  end
end
