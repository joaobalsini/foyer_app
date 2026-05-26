defmodule Foyer.Recognitions do
  @moduledoc """
  Peer recognition context. Composes pure validation from
  `Foyer.Recognitions.Validate` with `Ecto.Multi` transactions and read
  queries. See `Foyer.Recognitions.Validate` for the rule-by-rule
  validation helpers (self-recognition guard, bonus-point tier, grace
  window, …).
  """
  @behaviour Foyer.RecognitionsPort

  import Ecto.Query, warn: false

  alias Foyer.Accounts.User
  alias Foyer.Recognitions.PointEntry
  alias Foyer.Recognitions.Recognition
  alias Foyer.Recognitions.Validate
  alias Foyer.Repo

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
      |> Validate.recognition_attrs()
      |> Map.put("sender_id", sender.id)
      |> Validate.normalize_bonus_points(sender)

    changeset = Recognition.changeset(%Recognition{}, attrs)

    with :ok <- Validate.ensure_not_self(sender, changeset),
         :ok <- Validate.ensure_bonus_allowed(sender, changeset),
         :ok <- Validate.ensure_bonus_tier(changeset) do
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
      |> Validate.recognition_attrs()
      |> Validate.normalize_bonus_points(editor)

    changeset = Recognition.changeset(recognition, attrs)

    with :ok <- Validate.ensure_not_removed(recognition),
         :ok <- Validate.ensure_sender(recognition, editor),
         :ok <- Validate.ensure_within_grace(recognition),
         :ok <- Validate.ensure_not_self(editor, changeset),
         :ok <- Validate.ensure_bonus_allowed(editor, changeset),
         :ok <- Validate.ensure_bonus_tier(changeset) do
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
    with :ok <- Validate.ensure_not_removed(recognition),
         :ok <- Validate.ensure_sender(recognition, remover),
         :ok <- Validate.ensure_within_grace(recognition) do
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
  def within_grace_window?(%Recognition{} = recognition),
    do: Validate.within_grace_window?(recognition)

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

  # Used by Foyer.Today to count private recognitions received since the user's
  # last shift ended (F.Today.16, F.Today.20).
  @impl true
  @spec private_received_since(User.t(), DateTime.t() | nil) :: non_neg_integer()
  def private_received_since(%User{id: user_id}, since) do
    query =
      from(r in Recognition,
        where: r.recipient_id == ^user_id and r.public == false,
        select: count(r.id)
      )

    query =
      if is_nil(since) do
        query
      else
        from(r in query, where: r.inserted_at > ^since)
      end

    Repo.one!(query)
  end
end
