defmodule Today.Scenarios.OnShiftManager do
  @moduledoc """
  Scenario: on-shift manager, 1 needs-ack, 2 live posts.
  """
  @behaviour Foyer.Today.Behavior

  alias Foyer.Accounts.User
  alias Foyer.Channels.Channel
  alias Foyer.House.Announcement
  alias Foyer.Shifts.Shift
  alias Foyer.Today.Briefing

  @impl true
  def brief_for(%User{} = user) do
    now = DateTime.utc_now()

    shift = %Shift{
      id: 5,
      user_id: user.id,
      started_at: DateTime.add(now, -3 * 3600, :second),
      ended_at: nil,
      handoff_note: nil,
      handoff_channel_id: nil
    }

    channel = %Channel{
      id: 2,
      name: "All Housekeeping",
      slug: "all-housekeeping",
      kind: :department
    }

    needs_ack_ann = %Announcement{
      id: 20,
      author_id: 10,
      author: %User{
        id: 10,
        name: "Rafael Mendes",
        initials: "RM",
        role: :manager,
        department: "Front Office",
        title: "Night Manager",
        languages: ["EN"],
        points_balance: 0
      },
      channel_id: 2,
      channel: channel,
      title: "Q2 review notes — please acknowledge",
      body: "Internal review notes.",
      requires_ack: true,
      pinned_at: nil,
      published_at: DateTime.add(now, -3600, :second)
    }

    live_post_1 = %Announcement{
      id: 11,
      author_id: user.id,
      author: user,
      channel_id: 2,
      channel: channel,
      title: "Suite 412 - Allergy protocol in effect",
      body: "Allergy protocol.",
      requires_ack: true,
      pinned_at: DateTime.add(now, -7200, :second),
      published_at: DateTime.add(now, -7200, :second)
    }

    live_post_2 = %Announcement{
      id: 12,
      author_id: user.id,
      author: user,
      channel_id: 2,
      channel: channel,
      title: "Staff meeting — Floor 4 team",
      body: "Meeting at 14:00.",
      requires_ack: false,
      pinned_at: nil,
      published_at: DateTime.add(now, -3 * 3600, :second)
    }

    %Briefing{
      user: user,
      shift: shift,
      on_shift?: true,
      handoff: nil,
      needs_ack: [needs_ack_ann],
      recent_recognitions: [],
      own_announcements: [live_post_1, live_post_2],
      waiting_announcements: 0,
      waiting_messages: 0,
      waiting_recognitions: 0,
      last_shift_ended_at: nil
    }
  end
end
