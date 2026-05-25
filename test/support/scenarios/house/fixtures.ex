defmodule Foyer.HouseScenarios.Fixtures do
  @moduledoc """
  Shared in-memory struct builders for the `Foyer.HouseScenarios.*` modules.

  These fixtures construct `%User{}`, `%Channel{}`, `%Announcement{}`,
  `%AnnouncementAck{}`, and `%AnnouncementRead{}` structs directly (no Repo
  insert) so isolated LiveView tests can render against a known shape of the
  world without touching the database.

  Each scenario builds on top of these helpers; the "shape of the world" is
  expressed by which announcements, acks, and reads each scenario returns,
  not by re-defining the seed users.
  """

  alias Foyer.Accounts.User
  alias Foyer.Channels.Channel
  alias Foyer.House.Announcement
  alias Foyer.House.AnnouncementAck
  alias Foyer.House.AnnouncementRead

  @spec channel() :: Channel.t()
  def channel do
    %Channel{
      id: 1,
      name: "Housekeeping · Floor 4",
      slug: "housekeeping-floor-4",
      kind: :department
    }
  end

  @spec leadership_channel() :: Channel.t()
  def leadership_channel do
    %Channel{
      id: 2,
      name: "Leadership",
      slug: "leadership",
      kind: :department
    }
  end

  @spec manager() :: User.t()
  def manager do
    %User{
      id: 10,
      name: "Charlotte Voss",
      initials: "CV",
      role: :manager,
      department: "Housekeeping",
      title: "Dir. of Housekeeping",
      languages: ["EN"],
      points_balance: 0
    }
  end

  @spec staff() :: User.t()
  def staff do
    %User{
      id: 11,
      name: "Maya Okafor",
      initials: "MO",
      role: :staff,
      department: "Housekeeping",
      title: "Senior Housekeeper · Floor 4",
      languages: ["EN"],
      points_balance: 0
    }
  end

  @spec other_staff() :: User.t()
  def other_staff do
    %User{
      id: 12,
      name: "Aisha Bello",
      initials: "AB",
      role: :staff,
      department: "Housekeeping",
      title: "Housekeeper · Fl. 4",
      languages: ["EN"],
      points_balance: 0
    }
  end

  @doc """
  Returns the canonical announcement used across scenarios. Authored by the
  manager (`manager/0`), in `channel/0`, published 5 minutes ago, requires
  acknowledgement, pinned.
  """
  @spec announcement(keyword()) :: Announcement.t()
  def announcement(overrides \\ []) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    five_min_ago = DateTime.add(now, -5 * 60, :second)

    base = %Announcement{
      id: 100,
      author_id: manager().id,
      author: manager(),
      channel_id: channel().id,
      channel: channel(),
      title: "Suite 412 - Allergy protocol in effect",
      body: "Guest in 412 has severe tree-nut allergy.",
      pinned_at: five_min_ago,
      requires_ack: true,
      published_at: five_min_ago,
      removed_at: nil,
      removed_by_id: nil,
      reads: [],
      acks: []
    }

    Enum.reduce(overrides, base, fn {k, v}, acc -> Map.put(acc, k, v) end)
  end

  @spec ack(integer(), User.t()) :: AnnouncementAck.t()
  def ack(announcement_id, %User{id: user_id} = user) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %AnnouncementAck{
      id: announcement_id * 1000 + user_id,
      announcement_id: announcement_id,
      user_id: user_id,
      user: user,
      ack_at: now
    }
  end

  @spec read(integer(), User.t()) :: AnnouncementRead.t()
  def read(announcement_id, %User{id: user_id} = user) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %AnnouncementRead{
      id: announcement_id * 2000 + user_id,
      announcement_id: announcement_id,
      user_id: user_id,
      user: user,
      read_at: now
    }
  end

  @doc """
  An empty receipt grouping (no recipients in any bucket).
  """
  @spec empty_receipts() :: map()
  def empty_receipts do
    %{acknowledged: [], read_without_acknowledgement: [], unread: [], off_shift: []}
  end
end
