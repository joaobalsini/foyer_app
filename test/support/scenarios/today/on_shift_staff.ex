defmodule Today.Scenarios.OnShiftStaff do
  @moduledoc """
  Scenario: on-shift staff, handoff present, 1 needs-ack, 2 recognitions.
  """
  @behaviour Foyer.TodayPort

  alias Foyer.Accounts.User
  alias Foyer.Channels.Channel
  alias Foyer.House.Announcement
  alias Foyer.Recognitions.Recognition
  alias Foyer.Shifts.Shift
  alias Foyer.Today.Briefing

  @impl true
  def brief_for(%User{} = user) do
    now = DateTime.utc_now()

    sender = %User{
      id: 99,
      name: "Rafael Mendes",
      initials: "RM",
      role: :manager,
      department: "Front Office",
      title: "Night Manager",
      languages: ["EN"],
      points_balance: 0
    }

    channel = %Channel{
      id: 1,
      name: "Housekeeping · Floor 4",
      slug: "housekeeping-floor-4",
      kind: :department
    }

    shift = %Shift{
      id: 1,
      user_id: user.id,
      started_at: DateTime.add(now, -7 * 3600, :second),
      ended_at: nil,
      handoff_note: nil,
      handoff_channel_id: nil
    }

    handoff_shift = %Shift{
      id: 2,
      user_id: 99,
      user: sender,
      started_at: DateTime.add(now, -14 * 3600, :second),
      ended_at: DateTime.add(now, -2 * 3600, :second),
      handoff_note: "Quiet night, 206 settled.",
      handoff_channel_id: 1,
      handoff_channel: channel
    }

    announcement = %Announcement{
      id: 10,
      author_id: 99,
      author: sender,
      channel_id: 1,
      channel: channel,
      title: "Suite 412 - Allergy protocol in effect",
      body: "Guest in 412 has severe tree-nut allergy.",
      requires_ack: true,
      pinned_at: DateTime.add(now, -3600, :second),
      published_at: DateTime.add(now, -3600, :second)
    }

    rec1 = %Recognition{
      id: 1,
      sender_id: 99,
      sender: sender,
      recipient_id: user.id,
      body: "Quietly handled a 02:14 guest issue with grace.",
      values: ["care", "discretion"],
      public: true
    }

    rec2 = %Recognition{
      id: 2,
      sender_id: 99,
      sender: sender,
      recipient_id: user.id,
      body: "Excellent attention to detail in the Garden Suite.",
      values: ["craft"],
      public: false
    }

    %Briefing{
      user: user,
      shift: shift,
      on_shift?: true,
      handoff: handoff_shift,
      needs_ack: [announcement],
      recent_recognitions: [rec1, rec2],
      own_announcements: [],
      waiting_announcements: 0,
      waiting_messages: 0,
      waiting_recognitions: 0,
      last_shift_ended_at: nil
    }
  end
end
