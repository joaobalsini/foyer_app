defmodule Foyer.HouseScenarios.WithUnacked do
  @moduledoc """
  House port scenario: one pinned, ack-required announcement that the current
  staff user has read but not yet acknowledged. Published 5 minutes ago — the
  author is still within the 15-minute grace window.

  Used by isolated tests that exercise:

    * `F.Announcements.3` — author-within-grace edit affordance
    * `F.Announcements.5` — pin/unpin button visibility for managers
    * `F.Announcements.7` — required-ack list excludes the author
    * the read/ack rendering branches of the detail page

  All callbacks return data shaped like the real `Foyer.House` context, but
  populated from `Foyer.HouseScenarios.Fixtures` — no Repo, no database
  round-trips. Mutating callbacks (`pin_announcement/2`,
  `unpin_announcement/2`, `acknowledge/2`, …) return success values shaped
  like the real context so the LiveView can update its assigns.
  """
  @behaviour Foyer.HousePort

  alias Foyer.House.Announcement
  alias Foyer.HouseScenarios.Fixtures

  @impl true
  def feed_for(_user, _opts \\ []), do: [Fixtures.announcement()]

  @impl true
  def list_pinned_for(_user), do: [Fixtures.announcement()]

  @impl true
  def get_announcement!(_id, _user), do: Fixtures.announcement()

  @impl true
  def acknowledge(announcement, %{id: user_id}) do
    if announcement.author_id == user_id do
      {:error, :not_required}
    else
      {:ok, Fixtures.ack(announcement.id, Fixtures.staff())}
    end
  end

  @impl true
  def mark_read(_announcement, _user), do: {:ok, :marked}

  @impl true
  def compose_changeset(attrs), do: Announcement.changeset(%Announcement{}, attrs)

  @impl true
  def change_announcement(announcement, attrs), do: Announcement.changeset(announcement, attrs)

  @impl true
  def create_announcement(_user, _attrs), do: {:ok, Fixtures.announcement()}

  @impl true
  def update_announcement(announcement, _user, _attrs), do: {:ok, announcement}

  @impl true
  def remove_announcement(announcement, _user) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    {:ok, %{announcement | removed_at: now}}
  end

  @impl true
  def pin_announcement(announcement, _user) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    {:ok, %{announcement | pinned_at: now}}
  end

  @impl true
  def unpin_announcement(announcement, _user) do
    {:ok, %{announcement | pinned_at: nil}}
  end

  @impl true
  def receipts_for(_announcement, _user) do
    {:ok,
     %{
       acknowledged: [],
       read_without_acknowledgement: [Fixtures.staff()],
       unread: [Fixtures.other_staff()],
       off_shift: []
     }}
  end

  @impl true
  def within_grace_window?(_announcement), do: true

  @impl true
  def needs_ack_from(_user), do: [Fixtures.announcement()]
end
