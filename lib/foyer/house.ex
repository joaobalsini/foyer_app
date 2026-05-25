defmodule Foyer.House do
  @moduledoc """
  House announcements context. Read-side and `acknowledge/2`, `mark_read/2`
  are fully implemented (the smoke test exercises the ack click).
  `create_announcement/2` is stubbed until the House feature group lands.

  `get_announcement!/2` bakes membership authorization into the query — a
  user who is not a member of the announcement's channel raises
  `Ecto.NoResultsError`. See plan §6.4.
  """
  @behaviour Foyer.HousePort

  import Ecto.Query, warn: false

  alias Foyer.Accounts.User
  alias Foyer.Channels.Membership
  alias Foyer.House.Announcement
  alias Foyer.House.AnnouncementAck
  alias Foyer.House.AnnouncementRead
  alias Foyer.Repo

  @impl true
  @spec feed_for(User.t(), keyword()) :: [Announcement.t()]
  def feed_for(%User{id: user_id}, _opts \\ []) do
    from(a in Announcement,
      join: m in Membership,
      on: m.channel_id == a.channel_id and m.user_id == ^user_id,
      order_by: [desc_nulls_last: a.pinned_at, desc: a.published_at],
      preload: [:author, :channel, :reads, :acks]
    )
    |> Repo.all()
  end

  @impl true
  @spec list_pinned_for(User.t()) :: [Announcement.t()]
  def list_pinned_for(%User{id: user_id}) do
    from(a in Announcement,
      join: m in Membership,
      on: m.channel_id == a.channel_id and m.user_id == ^user_id,
      where: not is_nil(a.pinned_at),
      order_by: [desc: a.pinned_at, desc: a.published_at],
      preload: [:author, :channel, :reads, :acks]
    )
    |> Repo.all()
  end

  @impl true
  @spec get_announcement!(integer() | String.t(), User.t()) :: Announcement.t()
  def get_announcement!(id, %User{id: user_id}) do
    from(a in Announcement,
      join: m in Membership,
      on: m.channel_id == a.channel_id and m.user_id == ^user_id,
      where: a.id == ^id,
      preload: [:author, :channel, :reads, :acks]
    )
    |> Repo.one!()
  end

  @impl true
  @spec acknowledge(Announcement.t(), User.t()) :: {:ok, term()} | {:error, term()}
  def acknowledge(%Announcement{id: ann_id}, %User{id: user_id}) do
    %AnnouncementAck{}
    |> AnnouncementAck.changeset(%{
      announcement_id: ann_id,
      user_id: user_id,
      ack_at: DateTime.utc_now()
    })
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:announcement_id, :user_id]
    )
  end

  @impl true
  @spec mark_read(Announcement.t(), User.t()) :: {:ok, term()} | {:error, term()}
  def mark_read(%Announcement{id: ann_id}, %User{id: user_id}) do
    %AnnouncementRead{}
    |> AnnouncementRead.changeset(%{
      announcement_id: ann_id,
      user_id: user_id,
      read_at: DateTime.utc_now()
    })
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:announcement_id, :user_id]
    )
  end

  @impl true
  @spec compose_changeset(map()) :: Ecto.Changeset.t()
  def compose_changeset(attrs \\ %{}) do
    Announcement.changeset(%Announcement{}, attrs)
  end

  @impl true
  @spec create_announcement(User.t(), map()) ::
          {:ok, Announcement.t()} | {:error, Ecto.Changeset.t() | :not_implemented}
  def create_announcement(%User{} = _author, _attrs) do
    {:error, :not_implemented}
  end

  @impl true
  @spec change_announcement(Announcement.t(), map()) :: Ecto.Changeset.t()
  def change_announcement(%Announcement{} = announcement, attrs \\ %{}) do
    Announcement.changeset(announcement, attrs)
  end

  @impl true
  @spec update_announcement(Announcement.t(), User.t(), map()) ::
          {:ok, Announcement.t()} | {:error, Ecto.Changeset.t() | :not_implemented}
  def update_announcement(%Announcement{} = _announcement, %User{} = _editor, _attrs) do
    {:error, :not_implemented}
  end

  @impl true
  @spec needs_ack_from(User.t()) :: [Announcement.t()]
  def needs_ack_from(%User{id: user_id}) do
    from(a in Announcement,
      join: m in Membership,
      on: m.channel_id == a.channel_id and m.user_id == ^user_id,
      left_join: ack in AnnouncementAck,
      on: ack.announcement_id == a.id and ack.user_id == ^user_id,
      where: a.requires_ack == true and is_nil(ack.id),
      order_by: [desc_nulls_last: a.pinned_at, desc: a.published_at],
      preload: [:author, :channel]
    )
    |> Repo.all()
  end
end
