defmodule Foyer.Shifts.Shift do
  @moduledoc """
  A user is on shift iff there is a `shifts` row with `user_id = ?` and
  `ended_at IS NULL`. There is no `is_on_shift` boolean on `User`. The DB
  enforces "at most one open shift per user" via the
  `shifts_one_open_shift_per_user` partial unique index — see plan §5.13.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          user_id: integer() | nil,
          started_at: DateTime.t() | nil,
          ended_at: DateTime.t() | nil,
          handoff_note: String.t() | nil,
          handoff_channel_id: integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "shifts" do
    belongs_to :user, Foyer.Accounts.User
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime
    field :handoff_note, :string
    belongs_to :handoff_channel, Foyer.Channels.Channel

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(shift, attrs) do
    shift
    |> cast(attrs, [:user_id, :started_at, :ended_at, :handoff_note, :handoff_channel_id])
    |> validate_required([:user_id, :started_at])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:handoff_channel_id)
    |> unique_constraint(:user_id, name: :shifts_one_open_shift_per_user)
  end
end
