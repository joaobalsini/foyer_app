defmodule Foyer.Recognitions.PointEntry do
  @moduledoc """
  Auditable points ledger entry tied to a recognition.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          recognition_id: integer() | nil,
          user_id: integer() | nil,
          delta: integer() | nil,
          reason: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "recognition_point_entries" do
    belongs_to :recognition, Foyer.Recognitions.Recognition
    belongs_to :user, Foyer.Accounts.User
    field :delta, :integer
    field :reason, :string

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:recognition_id, :user_id, :delta, :reason])
    |> validate_required([:recognition_id, :user_id, :delta, :reason])
  end
end
