defmodule Foyer.House.Validate do
  @moduledoc """
  Pure validation, permission, and time-math helpers for the House
  announcements context. Side-effect-free — no `Repo` access, no
  `DateTime.utc_now` in derivations beyond what is required to compare against
  `published_at` for the grace window check.

  `Foyer.House` composes these helpers around its DB writes so that the rules
  pinned by the announcements spec (`F.Announcements.2`, `F.Announcements.3`,
  `F.Announcements.4`, `F.Announcements.7`, `F.Announcements.9`) can be unit
  tested without touching Postgres.

  Helpers that need the database — channel membership lookups, shift queries,
  receipt recipient queries — stay in `Foyer.House`.
  """

  alias Foyer.Accounts.User
  alias Foyer.House.Announcement

  @grace_window_seconds 5 * 60

  @receipt_buckets [:acknowledged, :read_without_acknowledgement, :unread, :off_shift]

  @type receipt_bucket ::
          :acknowledged | :read_without_acknowledgement | :unread | :off_shift

  @doc """
  Number of seconds the author has after `published_at` to edit or remove an
  announcement before the grace window closes (`F.Announcements.3`,
  `F.Announcements.4`).
  """
  @spec grace_window_seconds() :: pos_integer()
  def grace_window_seconds, do: @grace_window_seconds

  @doc """
  The four receipt bucket atoms, in the order the receipts panel renders them
  (`F.Announcements.9`).
  """
  @spec receipt_buckets() :: [receipt_bucket()]
  def receipt_buckets, do: @receipt_buckets

  @doc """
  Allows managers; rejects every other role with `{:error, :unauthorized}`
  (`F.Announcements.2`).
  """
  @spec ensure_manager(User.t()) :: :ok | {:error, :unauthorized}
  def ensure_manager(%User{role: :manager}), do: :ok
  def ensure_manager(%User{}), do: {:error, :unauthorized}

  @doc """
  Allows the announcement's author; rejects every other user with
  `{:error, :unauthorized}` (`F.Announcements.4`).
  """
  @spec ensure_author(Announcement.t(), User.t()) :: :ok | {:error, :unauthorized}
  def ensure_author(%Announcement{author_id: user_id}, %User{id: user_id}), do: :ok
  def ensure_author(%Announcement{}, %User{}), do: {:error, :unauthorized}

  @doc """
  Returns `:ok` while `published_at` is within `grace_window_seconds/0`;
  otherwise `{:error, :outside_grace_window}` (`F.Announcements.4`).
  """
  @spec ensure_within_grace(Announcement.t()) :: :ok | {:error, :outside_grace_window}
  def ensure_within_grace(%Announcement{} = announcement) do
    if within_grace_window?(announcement), do: :ok, else: {:error, :outside_grace_window}
  end

  @doc """
  Returns `:ok` if the announcement has not been soft-removed
  (`removed_at` is nil); otherwise `{:error, :removed}` (`F.Announcements.6`).
  """
  @spec ensure_not_removed(Announcement.t()) :: :ok | {:error, :removed}
  def ensure_not_removed(%Announcement{removed_at: nil}), do: :ok
  def ensure_not_removed(%Announcement{}), do: {:error, :removed}

  @doc """
  Returns `:ok` when the announcement requires acknowledgement and the user
  is not the author. Authors are excluded from the required-ack set per
  `F.Announcements.7` and an explicit author ack returns
  `{:error, :not_required}`.
  """
  @spec ensure_ack_required_from(Announcement.t(), User.t()) ::
          :ok | {:error, :not_required}
  def ensure_ack_required_from(%Announcement{requires_ack: true, author_id: author_id}, %User{
        id: user_id
      })
      when author_id != user_id,
      do: :ok

  def ensure_ack_required_from(%Announcement{}, %User{}), do: {:error, :not_required}

  @doc """
  Returns `true` while the announcement is inside its 5-minute grace window
  measured from `published_at`. Announcements without a `published_at` value
  are treated as outside the window.
  """
  @spec within_grace_window?(Announcement.t()) :: boolean()
  def within_grace_window?(%Announcement{published_at: %DateTime{} = published_at}) do
    DateTime.diff(DateTime.utc_now(), published_at, :second) <= @grace_window_seconds
  end

  def within_grace_window?(%Announcement{}), do: false

  @doc """
  Derives which receipt bucket a single recipient belongs in for the receipts
  panel (`F.Announcements.9`). `off_shift` takes precedence over any other
  state; otherwise the order is acknowledged → read-only → unread.

  `on_shift`, `acked`, and `read` are O(1) lookup tables keyed by user id (see
  the typespec). Bare maps are used instead of `MapSet` because `MapSet` has an
  opaque internal representation that trips Dialyzer on Erlang/OTP 27+ when
  the values flow across function boundaries; a plain map keeps the type
  transparent at the same lookup cost. The map value (`true`) is unused — only
  key membership matters.
  """
  @spec receipt_bucket_for(integer(), %{integer() => true}, %{integer() => true}, %{
          integer() => true
        }) :: receipt_bucket()
  def receipt_bucket_for(user_id, on_shift, acked, read) do
    cond do
      not Map.has_key?(on_shift, user_id) -> :off_shift
      Map.has_key?(acked, user_id) -> :acknowledged
      Map.has_key?(read, user_id) -> :read_without_acknowledgement
      true -> :unread
    end
  end

  @doc """
  Initial accumulator for the receipts grouping fold: each bucket starts
  empty. Keeps the rendering surface from having to special-case missing keys
  when no member falls in a bucket.
  """
  @spec empty_receipt_groups() :: %{receipt_bucket() => []}
  def empty_receipt_groups do
    %{acknowledged: [], read_without_acknowledgement: [], unread: [], off_shift: []}
  end
end
