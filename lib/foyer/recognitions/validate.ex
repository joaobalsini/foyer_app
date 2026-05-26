defmodule Foyer.Recognitions.Validate do
  @moduledoc """
  Pure, side-effect-free validation helpers for `Foyer.Recognitions`.

  These functions encapsulate the rules the context enforces around peer
  recognitions — recipient identity (no self-recognition), the manager-only
  bonus-point gate and fixed tier, the 15-minute author grace window, and the
  shape of the attribute map that feeds `Recognition.changeset/2`.

  All functions here are pure: they take structs / changesets / maps and
  return `:ok` / `{:error, atom()}` or a transformed value. They never touch
  the database or read the system clock except for `within_grace_window?/1`
  and `ensure_within_grace/1`, which compare the recognition's persisted
  `inserted_at` against `DateTime.utc_now/0`.

  The `Foyer.Recognitions` context composes these helpers inside its
  `give/2`, `update_recognition/3`, and `remove_recognition/2` flows.
  """

  alias Foyer.Accounts.User
  alias Foyer.Recognitions.Recognition

  @grace_window_seconds 15 * 60
  @point_tiers [0, 10, 25, 50, 100]

  @doc """
  Allowed bonus-point tier values. Any value outside this list is rejected by
  `ensure_bonus_tier/1` with `{:error, :invalid_point_tier}`.
  """
  @spec bonus_tiers() :: [non_neg_integer()]
  def bonus_tiers, do: @point_tiers

  @doc """
  Grace window in seconds (15 minutes) during which an author can edit or
  remove their own recognition.
  """
  @spec grace_window_seconds() :: pos_integer()
  def grace_window_seconds, do: @grace_window_seconds

  @doc """
  Normalises the compose-form attributes that feed `Recognition.changeset/2`.

  Accepts a map with either string or atom keys, takes only the keys we
  expose on the compose form, and returns a string-keyed map with blank /
  nil tokens stripped from `"values"`.
  """
  @spec recognition_attrs(map()) :: map()
  def recognition_attrs(attrs) do
    attrs
    |> Map.take(["recipient_id", "body", "values", "bonus_points", "public"])
    |> Map.merge(
      attrs
      |> Map.take([:recipient_id, :body, :values, :bonus_points, :public])
      |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
    )
    |> normalize_values()
  end

  @doc """
  Strips blank / nil entries from the `"values"` list. Leaves the map
  untouched when `"values"` is missing or not a list.
  """
  @spec normalize_values(map()) :: map()
  def normalize_values(%{"values" => values} = attrs) when is_list(values) do
    Map.put(attrs, "values", Enum.reject(values, &(&1 in ["", nil])))
  end

  def normalize_values(attrs), do: attrs

  @doc """
  Silently forces `"bonus_points"` to `0` when the sender is not a manager
  (F.Recognitions.5). Managers pass through unchanged.
  """
  @spec normalize_bonus_points(map(), User.t()) :: map()
  def normalize_bonus_points(attrs, %User{role: :manager}), do: attrs
  def normalize_bonus_points(attrs, %User{}), do: Map.put(attrs, "bonus_points", 0)

  @doc """
  Rejects self-recognition (F.Recognitions.2): if the changeset's
  `recipient_id` matches the sender's id, returns `{:error, :self_recognition}`.
  """
  @spec ensure_not_self(User.t(), Ecto.Changeset.t()) :: :ok | {:error, :self_recognition}
  def ensure_not_self(%User{id: sender_id}, %Ecto.Changeset{} = changeset) do
    case Ecto.Changeset.get_field(changeset, :recipient_id) do
      ^sender_id -> {:error, :self_recognition}
      _ -> :ok
    end
  end

  @doc """
  Enforces the manager-only bonus-point gate (F.Recognitions.5). Managers
  always pass; staff pass only when `bonus_points` is `nil` or `0`. Any
  positive value from a staff sender returns `{:error, :unauthorized_points}`.
  """
  @spec ensure_bonus_allowed(User.t(), Ecto.Changeset.t()) ::
          :ok | {:error, :unauthorized_points}
  def ensure_bonus_allowed(%User{role: :manager}, _changeset), do: :ok

  def ensure_bonus_allowed(%User{}, %Ecto.Changeset{} = changeset) do
    case Ecto.Changeset.get_field(changeset, :bonus_points) do
      points when points in [nil, 0] -> :ok
      _ -> {:error, :unauthorized_points}
    end
  end

  @doc """
  Enforces the fixed bonus-point tier (F.Recognitions.6). Any value outside
  `0 / 10 / 25 / 50 / 100` returns `{:error, :invalid_point_tier}`.
  """
  @spec ensure_bonus_tier(Ecto.Changeset.t()) :: :ok | {:error, :invalid_point_tier}
  def ensure_bonus_tier(%Ecto.Changeset{} = changeset) do
    case Ecto.Changeset.get_field(changeset, :bonus_points) do
      points when points in @point_tiers -> :ok
      _ -> {:error, :invalid_point_tier}
    end
  end

  @doc """
  Enforces that the acting user is the original author. Non-authors get
  `{:error, :unauthorized}` (F.Recognitions.9).
  """
  @spec ensure_sender(Recognition.t(), User.t()) :: :ok | {:error, :unauthorized}
  def ensure_sender(%Recognition{sender_id: user_id}, %User{id: user_id}), do: :ok
  def ensure_sender(%Recognition{}, %User{}), do: {:error, :unauthorized}

  @doc """
  Enforces the 15-minute author grace window for edits and removals
  (F.Recognitions.9). Returns `{:error, :outside_grace_window}` once the
  window has closed.
  """
  @spec ensure_within_grace(Recognition.t()) :: :ok | {:error, :outside_grace_window}
  def ensure_within_grace(%Recognition{} = recognition) do
    if within_grace_window?(recognition), do: :ok, else: {:error, :outside_grace_window}
  end

  @doc """
  Guards against acting on an already soft-removed recognition.
  """
  @spec ensure_not_removed(Recognition.t()) :: :ok | {:error, :removed}
  def ensure_not_removed(%Recognition{removed_at: nil}), do: :ok
  def ensure_not_removed(%Recognition{}), do: {:error, :removed}

  @doc """
  Returns `true` while the recognition is inside the 15-minute author grace
  window, `false` otherwise (including when `inserted_at` is missing, e.g.
  on an unsaved struct).
  """
  @spec within_grace_window?(Recognition.t()) :: boolean()
  def within_grace_window?(%Recognition{inserted_at: %DateTime{} = inserted_at}) do
    DateTime.diff(DateTime.utc_now(), inserted_at, :second) <= @grace_window_seconds
  end

  def within_grace_window?(%Recognition{}), do: false
end
