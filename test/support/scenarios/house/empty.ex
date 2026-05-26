defmodule Foyer.HouseScenarios.Empty do
  @moduledoc """
  House port scenario: no announcements in the world.

  `feed_for/2`, `list_pinned_for/1`, and `needs_ack_from/1` all return `[]`.
  Anything that requires looking up an announcement by id raises
  `Ecto.NoResultsError` (the same way the real context does for a missing or
  unauthorized id).

  Used by isolated LiveView tests that want to render the empty/no-data
  branches of the announcement surface.
  """
  @behaviour Foyer.House.Behavior

  alias Foyer.House.Announcement
  alias Foyer.HouseScenarios.Fixtures

  @impl true
  def feed_for(_user, _opts \\ []), do: []

  @impl true
  def list_pinned_for(_user), do: []

  @impl true
  def get_announcement!(_id, _user), do: raise(Ecto.NoResultsError, queryable: Announcement)

  @impl true
  def acknowledge(_announcement, _user), do: {:error, :not_required}

  @impl true
  def mark_read(_announcement, _user), do: {:ok, :noop}

  @impl true
  def compose_changeset(attrs), do: Announcement.changeset(%Announcement{}, attrs)

  @impl true
  def change_announcement(announcement, attrs), do: Announcement.changeset(announcement, attrs)

  @impl true
  def create_announcement(_user, _attrs), do: {:error, :unauthorized}

  @impl true
  def update_announcement(_announcement, _user, _attrs), do: {:error, :outside_grace_window}

  @impl true
  def remove_announcement(_announcement, _user), do: {:error, :outside_grace_window}

  @impl true
  def pin_announcement(_announcement, _user), do: {:error, :unauthorized}

  @impl true
  def unpin_announcement(_announcement, _user), do: {:error, :unauthorized}

  @impl true
  def receipts_for(_announcement, _user), do: {:ok, Fixtures.empty_receipts()}

  @impl true
  def within_grace_window?(_announcement), do: false

  @impl true
  def needs_ack_from(_user), do: []

  @impl true
  def authored_by(_user), do: []

  @impl true
  def unacked_since(_user, _since), do: 0
end
