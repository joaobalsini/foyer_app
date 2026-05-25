defmodule Foyer.Channels.Channel do
  @moduledoc """
  A channel is the unit of audience targeting for House announcements and
  channel-mode Chat conversations. `kind` distinguishes department (e.g.
  Housekeeping · Floor 4) from general (e.g. "Linden · All staff"). Member
  counts are computed at query time, not denormalised — see plan §5.3.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          slug: String.t() | nil,
          kind: :department | :general | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "channels" do
    field :name, :string
    field :slug, :string
    field :kind, Ecto.Enum, values: [:department, :general]

    has_many :memberships, Foyer.Channels.Membership
    has_many :members, through: [:memberships, :user]

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(channel, attrs) do
    channel
    |> cast(attrs, [:name, :slug, :kind])
    |> validate_required([:name, :slug, :kind])
    |> unique_constraint(:slug)
  end
end
