defmodule Foyer.HouseScenarios.WithReceipts do
  @moduledoc """
  House port scenario: the canonical announcement, viewed by its manager
  author. Acks, reads, and the receipts grouping are all populated so the
  detail page's receipt panel renders every bucket.

  Used by isolated tests that exercise:

    * `F.Announcements.9` — the four receipt buckets render correctly
    * the author-side view (no ack CTA, edit affordance, pin/unpin controls)

  The receipts map mirrors the real `Foyer.House.receipts_for/2` shape:
  `:acknowledged`, `:read_without_acknowledgement`, `:unread`, `:off_shift`,
  each holding a list of `%User{}` structs.
  """
  @behaviour Foyer.HousePort

  alias Foyer.House.Announcement
  alias Foyer.HouseScenarios.Fixtures

  @impl true
  def feed_for(_user, _opts \\ []), do: [announcement_with_acks()]

  @impl true
  def list_pinned_for(_user), do: [announcement_with_acks()]

  @impl true
  def get_announcement!(_id, _user), do: announcement_with_acks()

  @impl true
  def acknowledge(_announcement, _user), do: {:error, :not_required}

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
       acknowledged: [Fixtures.other_staff()],
       read_without_acknowledgement: [Fixtures.staff()],
       unread: [],
       off_shift: []
     }}
  end

  @impl true
  def within_grace_window?(_announcement), do: true

  @impl true
  def needs_ack_from(_user), do: []

  @impl true
  def authored_by(_user), do: [announcement_with_acks()]

  @impl true
  def unacked_since(_user, _since), do: 0

  defp announcement_with_acks do
    other = Fixtures.other_staff()
    me = Fixtures.staff()
    base = Fixtures.announcement()

    %{
      base
      | acks: [Fixtures.ack(base.id, other)],
        reads: [Fixtures.read(base.id, other), Fixtures.read(base.id, me)]
    }
  end
end
