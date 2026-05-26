defmodule Today.Scenarios.OnShiftAllAcked do
  @moduledoc """
  Scenario: on-shift staff, needs-ack list empty (all acknowledged).
  """
  @behaviour Foyer.Today.Behavior

  alias Foyer.Accounts.User
  alias Foyer.Shifts.Shift
  alias Foyer.Today.Briefing

  @impl true
  def brief_for(%User{} = user) do
    now = DateTime.utc_now()

    shift = %Shift{
      id: 1,
      user_id: user.id,
      started_at: DateTime.add(now, -4 * 3600, :second),
      ended_at: nil,
      handoff_note: nil,
      handoff_channel_id: nil
    }

    %Briefing{
      user: user,
      shift: shift,
      on_shift?: true,
      handoff: nil,
      needs_ack: [],
      recent_recognitions: [],
      own_announcements: [],
      waiting_announcements: 0,
      waiting_messages: 0,
      waiting_recognitions: 0,
      last_shift_ended_at: nil
    }
  end
end
