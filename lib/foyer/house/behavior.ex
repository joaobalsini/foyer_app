defmodule Foyer.House.Behavior do
  @moduledoc """
  Behaviour for `Foyer.House`. All callbacks (read-side feed/pinned/detail,
  acknowledge/mark_read, create/update/remove, pin/unpin, receipts,
  needs_ack_from) are implemented by the House feature group.
  """

  alias Foyer.Accounts.User
  alias Foyer.House.Announcement

  @doc """
  Returns the announcement feed visible to the user, ordered for the house
  surface.

  The current implementation ignores `opts`; callers pass `[]`.
  """
  @callback feed_for(User.t(), opts :: keyword()) :: [Announcement.t()]

  @doc """
  Returns pinned announcements visible to the user.
  """
  @callback list_pinned_for(User.t()) :: [Announcement.t()]

  @doc """
  Looks up an announcement visible to the user.

  Returns `nil` for missing, removed, or unauthorized announcements.
  """
  @callback get_announcement(integer() | String.t(), User.t()) :: Announcement.t() | nil

  @doc """
  Records the user's acknowledgement of an announcement when acknowledgement is
  required and allowed.
  """
  @callback acknowledge(Announcement.t(), User.t()) :: {:ok, term()} | {:error, term()}

  @doc """
  Marks an announcement as read for the user.
  """
  @callback mark_read(Announcement.t(), User.t()) :: {:ok, term()} | {:error, term()}

  @doc """
  Builds a changeset for composing a new announcement.

  Expected attrs may use string or atom keys:

    * `"channel_id"` / `:channel_id` - required target channel id.
    * `"title"` / `:title` - required announcement title.
    * `"body"` / `:body` - required announcement body.
    * `"requires_ack"` / `:requires_ack` - optional boolean or form boolean.
    * `"pinned"` / `:pinned` - optional form flag; when truthy on create,
      `pinned_at` is set by the context.
  """
  @callback compose_changeset(map()) :: Ecto.Changeset.t()

  @doc """
  Builds a changeset for editing an existing announcement.

  Accepts the same user-editable attrs as `compose_changeset/1`.
  """
  @callback change_announcement(Announcement.t(), map()) :: Ecto.Changeset.t()

  @doc """
  Creates an announcement authored by the given user.

  Expected attrs may use string or atom keys:

    * `"channel_id"` / `:channel_id` - required target channel id.
    * `"title"` / `:title` - required announcement title.
    * `"body"` / `:body` - required announcement body.
    * `"requires_ack"` / `:requires_ack` - optional boolean or form boolean.
    * `"pinned"` / `:pinned` - optional form flag; when truthy, `pinned_at` is
      set automatically.

  The context sets `author_id` and `published_at`; callers must not provide
  those fields as trusted input.
  """
  @callback create_announcement(User.t(), map()) ::
              {:ok, Announcement.t()} | {:error, Ecto.Changeset.t() | atom()}

  @doc """
  Updates an announcement when the editor is authorized and within the edit
  window.

  Accepts the same user-editable attrs as `create_announcement/2`, except the
  `"pinned"` / `:pinned` flag is ignored by updates. Pinning is handled by
  `pin_announcement/2` and `unpin_announcement/2`.
  """
  @callback update_announcement(Announcement.t(), User.t(), map()) ::
              {:ok, Announcement.t()} | {:error, Ecto.Changeset.t() | atom()}

  @doc """
  Soft-removes an announcement when the remover is authorized and within the
  edit window.
  """
  @callback remove_announcement(Announcement.t(), User.t()) ::
              {:ok, Announcement.t()} | {:error, Ecto.Changeset.t() | atom()}

  @doc """
  Pins an announcement for eligible channel members.
  """
  @callback pin_announcement(Announcement.t(), User.t()) ::
              {:ok, Announcement.t()} | {:error, Ecto.Changeset.t() | atom()}

  @doc """
  Removes the pinned state from an announcement for eligible channel members.
  """
  @callback unpin_announcement(Announcement.t(), User.t()) ::
              {:ok, Announcement.t()} | {:error, Ecto.Changeset.t() | atom()}

  @doc """
  Returns receipt buckets for a manager viewing an announcement.
  """
  @callback receipts_for(Announcement.t(), User.t()) :: {:ok, map()} | {:error, atom()}

  @doc """
  Returns whether an announcement is still inside the edit/remove grace window.
  """
  @callback within_grace_window?(Announcement.t()) :: boolean()

  @doc """
  Returns announcements that require acknowledgement from the user and have not
  yet been acknowledged.
  """
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
