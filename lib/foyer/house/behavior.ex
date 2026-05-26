defmodule Foyer.House.Behavior do
  @moduledoc """
  Behaviour for `Foyer.House`. All callbacks (read-side feed/pinned/detail,
  acknowledge/mark_read, create/update/remove, pin/unpin, receipts,
  needs_ack_from) are implemented by the House feature group.
  """

  alias Foyer.Accounts.User
  alias Foyer.House.Announcement

  @callback feed_for(User.t(), opts :: keyword()) :: [Announcement.t()]
  @callback list_pinned_for(User.t()) :: [Announcement.t()]
  @callback get_announcement!(integer() | String.t(), User.t()) :: Announcement.t()
  @callback acknowledge(Announcement.t(), User.t()) :: {:ok, term()} | {:error, term()}
  @callback mark_read(Announcement.t(), User.t()) :: {:ok, term()} | {:error, term()}
  @callback compose_changeset(map()) :: Ecto.Changeset.t()
  @callback change_announcement(Announcement.t(), map()) :: Ecto.Changeset.t()
  @callback create_announcement(User.t(), map()) ::
              {:ok, Announcement.t()} | {:error, Ecto.Changeset.t() | atom()}
  @callback update_announcement(Announcement.t(), User.t(), map()) ::
              {:ok, Announcement.t()} | {:error, Ecto.Changeset.t() | atom()}
  @callback remove_announcement(Announcement.t(), User.t()) ::
              {:ok, Announcement.t()} | {:error, Ecto.Changeset.t() | atom()}
  @callback pin_announcement(Announcement.t(), User.t()) ::
              {:ok, Announcement.t()} | {:error, Ecto.Changeset.t() | atom()}
  @callback unpin_announcement(Announcement.t(), User.t()) ::
              {:ok, Announcement.t()} | {:error, Ecto.Changeset.t() | atom()}
  @callback receipts_for(Announcement.t(), User.t()) :: {:ok, map()} | {:error, atom()}
  @callback within_grace_window?(Announcement.t()) :: boolean()
  @callback needs_ack_from(User.t()) :: [Announcement.t()]

  @doc """
  Returns published announcements (published_at IS NOT NULL) authored by the
  given user, ordered published_at desc. Used by manager variant of Today
  (F.Today.14).
  """
  @callback authored_by(User.t()) :: [Announcement.t()]

  @doc """
  Returns the count of announcements requiring acknowledgement
  (requires_ack: true) from the user that were published after `since`
  (or all-time if since is nil) and not yet acknowledged.
  """
  @callback unacked_since(User.t(), DateTime.t() | nil) :: non_neg_integer()
end
