defmodule Foyer.Recognitions.Recognition do
  @moduledoc """
  Peer recognition. Tagged with one or more `@house_values`; managers may
  optionally attach `bonus_points` (0–100; only managers can set > 0 — the
  rule lives in the context, not the changeset). Visibility is public by
  default; a manager can flip it private.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          sender_id: integer() | nil,
          recipient_id: integer() | nil,
          body: String.t() | nil,
          values: [String.t()] | nil,
          bonus_points: integer() | nil,
          public: boolean() | nil,
          removed_at: DateTime.t() | nil,
          removed_by_id: integer() | nil,
          inserted_at: DateTime.t() | nil
        }

  @house_values ~w(care craft warmth discretion initiative excellence)

  schema "recognitions" do
    belongs_to :sender, Foyer.Accounts.User
    belongs_to :recipient, Foyer.Accounts.User
    field :body, :string
    field :values, {:array, :string}, default: []
    field :bonus_points, :integer, default: 0
    field :public, :boolean, default: true
    field :removed_at, :utc_datetime
    belongs_to :removed_by, Foyer.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @spec house_values() :: [String.t()]
  def house_values, do: @house_values

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(recognition, attrs) do
    recognition
    |> cast(attrs, [
      :sender_id,
      :recipient_id,
      :body,
      :values,
      :bonus_points,
      :public,
      :removed_at,
      :removed_by_id
    ])
    |> validate_required([:sender_id, :recipient_id, :body, :values])
    |> validate_values_present()
    |> validate_subset(:values, @house_values)
    |> validate_number(:bonus_points, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> check_constraint(:bonus_points, name: :bonus_points_non_negative)
  end

  defp validate_values_present(changeset) do
    case get_field(changeset, :values) do
      values when is_list(values) and values != [] -> changeset
      _ -> add_error(changeset, :values, "choose at least one value")
    end
  end
end
