defmodule Foyer.Recognitions do
  @moduledoc """
  Peer recognition context. Reads are real; `give/2` is stubbed until the
  Recognitions feature group lands.
  """
  @behaviour Foyer.RecognitionsPort

  import Ecto.Query, warn: false

  alias Foyer.Accounts.User
  alias Foyer.Recognitions.PointEntry
  alias Foyer.Recognitions.Recognition
  alias Foyer.Repo

  @grace_window_seconds 15 * 60
  @point_tiers [0, 10, 25, 50, 100]

  @impl true
  @spec feed_public(keyword()) :: [Recognition.t()]
  def feed_public(_opts \\ []) do
    from(r in Recognition,
      where: r.public == true,
      where: is_nil(r.removed_at),
      order_by: [desc: r.inserted_at],
      preload: [:sender, :recipient]
    )
    |> Repo.all()
  end

  @impl true
  @spec received_by(User.t(), User.t()) :: [Recognition.t()]
  def received_by(%User{id: user_id}, %User{id: viewer_id}) do
    from(r in Recognition,
      where: r.recipient_id == ^user_id,
      where: is_nil(r.removed_at),
      where: r.public == true or r.sender_id == ^viewer_id or r.recipient_id == ^viewer_id,
      order_by: [desc: r.inserted_at],
      preload: [:sender, :recipient]
    )
    |> Repo.all()
  end

  @impl true
  @spec given_by(User.t(), User.t()) :: [Recognition.t()]
  def given_by(%User{id: user_id}, %User{id: viewer_id}) do
    from(r in Recognition,
      where: r.sender_id == ^user_id,
      where: is_nil(r.removed_at),
      where: r.public == true or r.sender_id == ^viewer_id or r.recipient_id == ^viewer_id,
      order_by: [desc: r.inserted_at],
      preload: [:sender, :recipient]
    )
    |> Repo.all()
  end

  @impl true
  @spec get_recognition!(integer() | String.t(), User.t()) :: Recognition.t()
  def get_recognition!(id, %User{id: user_id}) do
    from(r in Recognition,
      where: r.id == ^id,
      where: r.public == true or r.sender_id == ^user_id or r.recipient_id == ^user_id,
      where: is_nil(r.removed_at),
      preload: [:sender, :recipient]
    )
    |> Repo.one!()
  end

  @impl true
  @spec compose_changeset(map()) :: Ecto.Changeset.t()
  def compose_changeset(attrs \\ %{}) do
    Recognition.changeset(%Recognition{}, attrs)
  end

  @impl true
  @spec change_recognition(Recognition.t(), map()) :: Ecto.Changeset.t()
  def change_recognition(%Recognition{} = recognition, attrs \\ %{}) do
    Recognition.changeset(recognition, attrs)
  end

  @impl true
  @spec give(User.t(), map()) ::
          {:ok, Recognition.t()} | {:error, Ecto.Changeset.t() | atom()}
  def give(%User{} = sender, attrs) do
    attrs =
      attrs
      |> recognition_attrs()
      |> Map.put("sender_id", sender.id)
      |> normalize_bonus_points(sender)

    changeset = Recognition.changeset(%Recognition{}, attrs)

    with :ok <- ensure_not_self(sender, changeset),
         :ok <- ensure_bonus_allowed(sender, changeset),
         :ok <- ensure_bonus_tier(changeset) do
      Ecto.Multi.new()
      |> Ecto.Multi.insert(:recognition, changeset)
      |> Ecto.Multi.run(:points, fn repo, %{recognition: recognition} ->
        grant_points(repo, recognition)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{recognition: recognition}} -> {:ok, preload_recognition(recognition)}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    end
  end

  @impl true
  @spec update_recognition(Recognition.t(), User.t(), map()) ::
          {:ok, Recognition.t()} | {:error, Ecto.Changeset.t() | atom()}
  def update_recognition(%Recognition{} = recognition, %User{} = editor, attrs) do
    attrs =
      attrs
      |> recognition_attrs()
      |> normalize_bonus_points(editor)

    changeset = Recognition.changeset(recognition, attrs)

    with :ok <- ensure_not_removed(recognition),
         :ok <- ensure_sender(recognition, editor),
         :ok <- ensure_within_grace(recognition),
         :ok <- ensure_not_self(editor, changeset),
         :ok <- ensure_bonus_allowed(editor, changeset),
         :ok <- ensure_bonus_tier(changeset) do
      changeset
      |> Repo.update()
      |> case do
        {:ok, updated} -> {:ok, preload_recognition(updated)}
        other -> other
      end
    end
  end

  @impl true
  @spec remove_recognition(Recognition.t(), User.t()) ::
          {:ok, Recognition.t()} | {:error, Ecto.Changeset.t() | atom()}
  def remove_recognition(%Recognition{} = recognition, %User{} = remover) do
    with :ok <- ensure_not_removed(recognition),
         :ok <- ensure_sender(recognition, remover),
         :ok <- ensure_within_grace(recognition) do
      Ecto.Multi.new()
      |> Ecto.Multi.update(
        :recognition,
        Recognition.changeset(recognition, %{
          "removed_at" => DateTime.utc_now() |> DateTime.truncate(:second),
          "removed_by_id" => remover.id
        })
      )
      |> Ecto.Multi.run(:points, fn repo, %{recognition: removed} ->
        reverse_points(repo, removed)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{recognition: removed}} -> {:ok, preload_recognition(removed)}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    end
  end

  @impl true
  @spec within_grace_window?(Recognition.t()) :: boolean()
  def within_grace_window?(%Recognition{inserted_at: %DateTime{} = inserted_at}) do
    DateTime.diff(DateTime.utc_now(), inserted_at, :second) <= @grace_window_seconds
  end

  def within_grace_window?(%Recognition{}), do: false

  defp recognition_attrs(attrs) do
    attrs
    |> Map.take(["recipient_id", "body", "values", "bonus_points", "public"])
    |> Map.merge(
      attrs
      |> Map.take([:recipient_id, :body, :values, :bonus_points, :public])
      |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
    )
    |> normalize_values()
  end

  defp normalize_values(%{"values" => values} = attrs) when is_list(values) do
    Map.put(attrs, "values", Enum.reject(values, &(&1 in ["", nil])))
  end

  defp normalize_values(attrs), do: attrs

  defp normalize_bonus_points(attrs, %User{role: :manager}), do: attrs
  defp normalize_bonus_points(attrs, %User{}), do: Map.put(attrs, "bonus_points", 0)

  defp ensure_not_self(%User{id: sender_id}, %Ecto.Changeset{} = changeset) do
    case Ecto.Changeset.get_field(changeset, :recipient_id) do
      ^sender_id -> {:error, :self_recognition}
      _ -> :ok
    end
  end

  defp ensure_bonus_allowed(%User{role: :manager}, _changeset), do: :ok

  defp ensure_bonus_allowed(%User{}, %Ecto.Changeset{} = changeset) do
    case Ecto.Changeset.get_field(changeset, :bonus_points) do
      points when points in [nil, 0] -> :ok
      _ -> {:error, :unauthorized_points}
    end
  end

  defp ensure_bonus_tier(%Ecto.Changeset{} = changeset) do
    case Ecto.Changeset.get_field(changeset, :bonus_points) do
      points when points in @point_tiers -> :ok
      _ -> {:error, :invalid_point_tier}
    end
  end

  defp ensure_sender(%Recognition{sender_id: user_id}, %User{id: user_id}), do: :ok
  defp ensure_sender(%Recognition{}, %User{}), do: {:error, :unauthorized}

  defp ensure_within_grace(%Recognition{} = recognition) do
    if within_grace_window?(recognition), do: :ok, else: {:error, :outside_grace_window}
  end

  defp ensure_not_removed(%Recognition{removed_at: nil}), do: :ok
  defp ensure_not_removed(%Recognition{}), do: {:error, :removed}

  defp grant_points(_repo, %Recognition{bonus_points: points}) when points in [nil, 0],
    do: {:ok, nil}

  defp grant_points(repo, %Recognition{} = recognition) do
    with {:ok, _entry} <-
           %PointEntry{}
           |> PointEntry.changeset(%{
             recognition_id: recognition.id,
             user_id: recognition.recipient_id,
             delta: recognition.bonus_points,
             reason: "recognition_granted"
           })
           |> repo.insert(),
         {1, _} <-
           repo.update_all(
             from(u in User, where: u.id == ^recognition.recipient_id),
             inc: [points_balance: recognition.bonus_points]
           ) do
      {:ok, recognition.bonus_points}
    else
      error -> {:error, error}
    end
  end

  defp reverse_points(_repo, %Recognition{bonus_points: points}) when points in [nil, 0],
    do: {:ok, nil}

  defp reverse_points(repo, %Recognition{} = recognition) do
    delta = -recognition.bonus_points

    with {:ok, _entry} <-
           %PointEntry{}
           |> PointEntry.changeset(%{
             recognition_id: recognition.id,
             user_id: recognition.recipient_id,
             delta: delta,
             reason: "recognition_removed"
           })
           |> repo.insert(),
         {1, _} <-
           repo.update_all(
             from(u in User, where: u.id == ^recognition.recipient_id),
             inc: [points_balance: delta]
           ) do
      {:ok, delta}
    else
      error -> {:error, error}
    end
  end

  defp preload_recognition(%Recognition{} = recognition) do
    Repo.preload(recognition, [:sender, :recipient])
  end
end
