defmodule Foyer.HousePort do
  @moduledoc """
  Behaviour for `Foyer.House`. Read-side callbacks (feed, pinned, detail) are
  fully implemented in the scaffold; `acknowledge/2`, `mark_read/2`, and
  `compose_changeset/1` are implemented; `create_announcement/2` is stubbed
  until the House feature group lands.
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
end
