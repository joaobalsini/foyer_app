defmodule Foyer.House do
  @moduledoc """
  House announcements context. Implements the full announcements feature
  group (`F.Announcements.1` – `F.Announcements.10`): create, edit within
  grace window, soft remove, pin/unpin, acknowledgements, reads, and manager
  receipts. Authorization (manager-only writes, channel membership for all
  reads and writes) is enforced **in this module**, not only at the route
  layer — see `F.Announcements.10`.

  `get_announcement!/2` bakes membership authorization into the query — a
  user who is not a member of the announcement's channel raises
  `Ecto.NoResultsError`.
  """
  @behaviour Foyer.HousePort

  import Ecto.Query, warn: false

  alias Foyer.Accounts.User
  alias Foyer.Channels.Membership
  alias Foyer.House.Announcement
  alias Foyer.House.AnnouncementAck
  alias Foyer.House.AnnouncementRead
  alias Foyer.Repo
  alias Foyer.Shifts.Shift

  @grace_window_seconds 15 * 60

  @impl true
  @spec feed_for(User.t(), keyword()) :: [Announcement.t()]
  def feed_for(%User{id: user_id}, _opts \\ []) do
    from(a in Announcement,
      join: m in Membership,
      on: m.channel_id == a.channel_id and m.user_id == ^user_id,
      where: is_nil(a.removed_at),
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
      where: is_nil(a.removed_at),
      order_by: [desc: a.pinned_at, desc: a.published_at],
      preload: [:author, :channel, :reads, :acks]
    )
    |> Repo.all()
  end

  @impl true
  @spec get_announcement!(integer() | String.t(), User.t()) :: Announcement.t()
  def get_announcement!(id, %User{id: user_id}) do
    # `acks: :user` is preloaded so the desktop read-receipts panel can render
    # ack badges with the acking user's initials without a per-ack N+1. One
    # extra join per page load — backed by index(:announcement_acks,
    # [:announcement_id, :user_id]).
    # The `is_nil(removed_at)` filter enforces the soft-removal semantics from
    # `F.Announcements.6`: removed rows are not reachable through this read.
    from(a in Announcement,
      join: m in Membership,
      on: m.channel_id == a.channel_id and m.user_id == ^user_id,
      where: a.id == ^id,
      where: is_nil(a.removed_at),
      preload: [:author, :channel, :reads, acks: :user]
    )
    |> Repo.one!()
  end

  @impl true
  @spec acknowledge(Announcement.t(), User.t()) :: {:ok, term()} | {:error, term()}
  def acknowledge(%Announcement{} = announcement, %User{id: user_id} = user) do
    with :ok <- ensure_available_member(announcement, user),
         :ok <- ensure_ack_required_from(announcement, user) do
      %AnnouncementAck{}
      |> AnnouncementAck.changeset(%{
        announcement_id: announcement.id,
        user_id: user_id,
        ack_at: DateTime.utc_now()
      })
      |> Repo.insert(
        on_conflict: :nothing,
        conflict_target: [:announcement_id, :user_id]
      )
    end
  end

  @impl true
  @spec mark_read(Announcement.t(), User.t()) :: {:ok, term()} | {:error, term()}
  def mark_read(%Announcement{} = announcement, %User{id: user_id} = user) do
    with :ok <- ensure_available_member(announcement, user) do
      %AnnouncementRead{}
      |> AnnouncementRead.changeset(%{
        announcement_id: announcement.id,
        user_id: user_id,
        read_at: DateTime.utc_now()
      })
      |> Repo.insert(
        on_conflict: :nothing,
        conflict_target: [:announcement_id, :user_id]
      )
    end
  end

  @impl true
  @spec compose_changeset(map()) :: Ecto.Changeset.t()
  def compose_changeset(attrs \\ %{}) do
    Announcement.changeset(%Announcement{}, attrs)
  end

  @impl true
  @spec create_announcement(User.t(), map()) ::
          {:ok, Announcement.t()} | {:error, Ecto.Changeset.t() | atom()}
  def create_announcement(%User{} = author, attrs) do
    attrs =
      attrs
      |> announcement_attrs()
      |> Map.put("author_id", author.id)
      |> Map.put("published_at", DateTime.utc_now() |> DateTime.truncate(:second))

    changeset = Announcement.changeset(%Announcement{}, attrs)

    with :ok <- ensure_manager(author),
         :ok <- ensure_changeset_channel_member(changeset, author) do
      changeset
      |> Repo.insert()
      |> preload_announcement()
    end
  end

  @impl true
  @spec change_announcement(Announcement.t(), map()) :: Ecto.Changeset.t()
  def change_announcement(%Announcement{} = announcement, attrs \\ %{}) do
    Announcement.changeset(announcement, attrs)
  end

  @impl true
  @spec update_announcement(Announcement.t(), User.t(), map()) ::
          {:ok, Announcement.t()} | {:error, Ecto.Changeset.t() | atom()}
  def update_announcement(%Announcement{} = announcement, %User{} = editor, attrs) do
    changeset = Announcement.changeset(announcement, announcement_attrs(attrs))

    with :ok <- ensure_not_removed(announcement),
         :ok <- ensure_author(announcement, editor),
         :ok <- ensure_within_grace(announcement),
         :ok <- ensure_changeset_channel_member(changeset, editor) do
      changeset
      |> Repo.update()
      |> preload_announcement()
    end
  end

  @impl true
  @spec remove_announcement(Announcement.t(), User.t()) ::
          {:ok, Announcement.t()} | {:error, Ecto.Changeset.t() | atom()}
  def remove_announcement(%Announcement{} = announcement, %User{} = remover) do
    with :ok <- ensure_not_removed(announcement),
         :ok <- ensure_author(announcement, remover),
         :ok <- ensure_member(announcement.channel_id, remover.id),
         :ok <- ensure_within_grace(announcement) do
      announcement
      |> Announcement.changeset(%{
        "removed_at" => DateTime.utc_now() |> DateTime.truncate(:second),
        "removed_by_id" => remover.id
      })
      |> Repo.update()
      |> preload_announcement()
    end
  end

  @impl true
  @spec pin_announcement(Announcement.t(), User.t()) ::
          {:ok, Announcement.t()} | {:error, Ecto.Changeset.t() | atom()}
  def pin_announcement(%Announcement{} = announcement, %User{} = manager) do
    update_pin(announcement, manager, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  @impl true
  @spec unpin_announcement(Announcement.t(), User.t()) ::
          {:ok, Announcement.t()} | {:error, Ecto.Changeset.t() | atom()}
  def unpin_announcement(%Announcement{} = announcement, %User{} = manager) do
    update_pin(announcement, manager, nil)
  end

  @impl true
  @spec receipts_for(Announcement.t(), User.t()) :: {:ok, map()} | {:error, atom()}
  def receipts_for(%Announcement{} = announcement, %User{} = manager) do
    with :ok <- ensure_manager(manager),
         :ok <- ensure_member(announcement.channel_id, manager.id) do
      recipients = receipt_recipients(announcement)
      recipient_ids = Enum.map(recipients, & &1.id)
      on_shift = on_shift_ids(recipient_ids)
      acked = receipt_ack_ids(announcement.id, recipient_ids)
      read = receipt_read_ids(announcement.id, recipient_ids)

      grouped =
        recipients
        |> Enum.reduce(empty_receipt_groups(), fn user, acc ->
          bucket = receipt_bucket_for(user.id, on_shift, acked, read)
          Map.update!(acc, bucket, &[user | &1])
        end)
        |> Map.new(fn {key, users} -> {key, Enum.reverse(users)} end)

      {:ok, grouped}
    end
  end

  defp empty_receipt_groups do
    %{acknowledged: [], read_without_acknowledgement: [], unread: [], off_shift: []}
  end

  # Uses bare maps (not MapSet) as O(1) lookup tables. MapSet has an opaque
  # internal representation that trips Dialyzer on Erlang/OTP 27+ when its
  # values flow across function boundaries; a plain map keeps the type
  # transparent and the lookup the same complexity. The map value (`true`) is
  # unused — only key membership matters.
  @spec receipt_bucket_for(integer(), %{integer() => true}, %{integer() => true}, %{
          integer() => true
        }) :: :off_shift | :acknowledged | :read_without_acknowledgement | :unread
  defp receipt_bucket_for(user_id, on_shift, acked, read) do
    cond do
      not Map.has_key?(on_shift, user_id) -> :off_shift
      Map.has_key?(acked, user_id) -> :acknowledged
      Map.has_key?(read, user_id) -> :read_without_acknowledgement
      true -> :unread
    end
  end

  @impl true
  @spec within_grace_window?(Announcement.t()) :: boolean()
  def within_grace_window?(%Announcement{published_at: %DateTime{} = published_at}) do
    DateTime.diff(DateTime.utc_now(), published_at, :second) <= @grace_window_seconds
  end

  def within_grace_window?(%Announcement{}), do: false

  @impl true
  @spec needs_ack_from(User.t()) :: [Announcement.t()]
  def needs_ack_from(%User{id: user_id}) do
    from(a in Announcement,
      join: m in Membership,
      on: m.channel_id == a.channel_id and m.user_id == ^user_id,
      left_join: ack in AnnouncementAck,
      on: ack.announcement_id == a.id and ack.user_id == ^user_id,
      where: a.requires_ack == true and is_nil(ack.id),
      where: a.author_id != ^user_id,
      where: is_nil(a.removed_at),
      order_by: [desc_nulls_last: a.pinned_at, desc: a.published_at],
      preload: [:author, :channel]
    )
    |> Repo.all()
  end

  defp update_pin(%Announcement{} = announcement, %User{} = manager, pinned_at) do
    with :ok <- ensure_not_removed(announcement),
         :ok <- ensure_manager(manager),
         :ok <- ensure_member(announcement.channel_id, manager.id) do
      announcement
      |> Announcement.changeset(%{"pinned_at" => pinned_at})
      |> Repo.update()
      |> preload_announcement()
    end
  end

  defp announcement_attrs(attrs) do
    attrs
    |> Map.take(["title", "body", "channel_id", "requires_ack"])
    |> Map.merge(
      attrs
      |> Map.take([:title, :body, :channel_id, :requires_ack])
      |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
    )
  end

  defp preload_announcement({:ok, %Announcement{} = announcement}) do
    {:ok, Repo.preload(announcement, [:author, :channel, :reads, :acks])}
  end

  defp preload_announcement(other), do: other

  defp ensure_manager(%User{role: :manager}), do: :ok
  defp ensure_manager(%User{}), do: {:error, :unauthorized}

  defp ensure_author(%Announcement{author_id: user_id}, %User{id: user_id}), do: :ok
  defp ensure_author(%Announcement{}, %User{}), do: {:error, :unauthorized}

  defp ensure_within_grace(%Announcement{} = announcement) do
    if within_grace_window?(announcement), do: :ok, else: {:error, :outside_grace_window}
  end

  defp ensure_not_removed(%Announcement{removed_at: nil}), do: :ok
  defp ensure_not_removed(%Announcement{}), do: {:error, :removed}

  defp ensure_available_member(%Announcement{} = announcement, %User{id: user_id}) do
    with :ok <- ensure_not_removed(announcement) do
      ensure_member(announcement.channel_id, user_id)
    end
  end

  defp ensure_ack_required_from(%Announcement{requires_ack: true, author_id: author_id}, %User{
         id: user_id
       })
       when author_id != user_id,
       do: :ok

  defp ensure_ack_required_from(%Announcement{}, %User{}), do: {:error, :not_required}

  defp ensure_changeset_channel_member(%Ecto.Changeset{} = changeset, %User{id: user_id}) do
    if changeset.valid? do
      changeset
      |> Ecto.Changeset.get_field(:channel_id)
      |> ensure_member(user_id)
    else
      {:error, changeset}
    end
  end

  defp ensure_member(nil, _user_id), do: {:error, :not_channel_member}

  defp ensure_member(channel_id, user_id) do
    from(m in Membership,
      where: m.channel_id == ^channel_id and m.user_id == ^user_id,
      select: m.id,
      limit: 1
    )
    |> Repo.exists?()
    |> case do
      true -> :ok
      false -> {:error, :not_channel_member}
    end
  end

  defp receipt_recipients(%Announcement{channel_id: channel_id, author_id: author_id}) do
    from(m in Membership,
      join: u in assoc(m, :user),
      where: m.channel_id == ^channel_id and u.id != ^author_id,
      order_by: [asc: u.name],
      select: u
    )
    |> Repo.all()
  end

  @spec on_shift_ids([integer()]) :: %{integer() => true}
  defp on_shift_ids([]), do: %{}

  defp on_shift_ids(user_ids) do
    from(s in Shift,
      where: s.user_id in ^user_ids and is_nil(s.ended_at),
      select: s.user_id
    )
    |> Repo.all()
    |> Map.new(&{&1, true})
  end

  @spec receipt_ack_ids(integer(), [integer()]) :: %{integer() => true}
  defp receipt_ack_ids(_announcement_id, []), do: %{}

  defp receipt_ack_ids(announcement_id, user_ids) do
    from(ack in AnnouncementAck,
      where: ack.announcement_id == ^announcement_id and ack.user_id in ^user_ids,
      select: ack.user_id
    )
    |> Repo.all()
    |> Map.new(&{&1, true})
  end

  @spec receipt_read_ids(integer(), [integer()]) :: %{integer() => true}
  defp receipt_read_ids(_announcement_id, []), do: %{}

  defp receipt_read_ids(announcement_id, user_ids) do
    from(read in AnnouncementRead,
      where: read.announcement_id == ^announcement_id and read.user_id in ^user_ids,
      select: read.user_id
    )
    |> Repo.all()
    |> Map.new(&{&1, true})
  end
end
