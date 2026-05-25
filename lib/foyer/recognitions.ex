defmodule Foyer.Recognitions do
  @moduledoc """
  Peer recognition context. Reads are real; `give/2` is stubbed until the
  Recognitions feature group lands.
  """
  @behaviour Foyer.RecognitionsPort

  import Ecto.Query, warn: false

  alias Foyer.Accounts.User
  alias Foyer.Recognitions.Recognition
  alias Foyer.Repo

  @impl true
  @spec feed_public(keyword()) :: [Recognition.t()]
  def feed_public(_opts \\ []) do
    from(r in Recognition,
      where: r.public == true,
      order_by: [desc: r.inserted_at],
      preload: [:sender, :recipient]
    )
    |> Repo.all()
  end

  @impl true
  @spec received_by(User.t()) :: [Recognition.t()]
  def received_by(%User{id: user_id}) do
    from(r in Recognition,
      where: r.recipient_id == ^user_id,
      order_by: [desc: r.inserted_at],
      preload: [:sender, :recipient]
    )
    |> Repo.all()
  end

  @impl true
  @spec given_by(User.t()) :: [Recognition.t()]
  def given_by(%User{id: user_id}) do
    from(r in Recognition,
      where: r.sender_id == ^user_id,
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
          {:ok, Recognition.t()} | {:error, Ecto.Changeset.t() | :not_implemented}
  def give(%User{} = _sender, _attrs) do
    {:error, :not_implemented}
  end

  @impl true
  @spec update_recognition(Recognition.t(), User.t(), map()) ::
          {:ok, Recognition.t()} | {:error, Ecto.Changeset.t() | :not_implemented}
  def update_recognition(%Recognition{} = _recognition, %User{} = _editor, _attrs) do
    {:error, :not_implemented}
  end
end
