defmodule Today.Scenarios.AfterClockOut do
  @moduledoc """
  Scenario: off-shift immediately after clock-out (shift-complete variant).
  The just_clocked_out assign is set by the LiveView from query params, not
  from brief_for — this scenario returns the off-shift briefing shape.
  """
  @behaviour Foyer.Today.Behavior

  alias Foyer.Accounts.User
  alias Foyer.Today.Briefing

  @impl true
  def brief_for(%User{} = user) do
    last_ended = DateTime.add(DateTime.utc_now(), -30, :second)

    %Briefing{
      user: user,
      shift: nil,
      on_shift?: false,
      handoff: nil,
      needs_ack: [],
      recent_recognitions: [],
      own_announcements: [],
      waiting_announcements: 0,
      waiting_messages: 0,
      waiting_recognitions: 0,
      last_shift_ended_at: last_ended
    }
  end
end
