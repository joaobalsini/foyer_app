defmodule Foyer.Accounts.User do
  @moduledoc """
  Foyer staff member. Identified by a friendly name + two-letter initials and
  tagged with role (`:manager` or `:staff`), department, title, languages, and
  a running `points_balance`. Shift state is NOT stored here — see
  `Foyer.Shifts.Shift`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          initials: String.t() | nil,
          role: :manager | :staff | nil,
          department: String.t() | nil,
          title: String.t() | nil,
          languages: [String.t()] | nil,
          points_balance: integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "users" do
    field :name, :string
    field :initials, :string
    field :role, Ecto.Enum, values: [:manager, :staff]
    field :department, :string
    field :title, :string
    field :languages, {:array, :string}, default: []
    field :points_balance, :integer, default: 0

    has_many :memberships, Foyer.Channels.Membership
    has_many :channels, through: [:memberships, :channel]

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :initials, :role, :department, :title, :languages, :points_balance])
    |> validate_required([:name, :initials, :role, :department, :title])
  end
end
