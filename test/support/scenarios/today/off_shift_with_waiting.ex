defmodule Today.Scenarios.OffShiftWithWaiting do
  @moduledoc """
  Scenario: off-shift user, 3 announcements + 2 messages + 1 private rec waiting.
  """
  @behaviour Foyer.Today.Behavior

  alias Foyer.Accounts.User
  alias Foyer.Today.Briefing

  @impl true
  def brief_for(%User{} = user) do
    last_ended = DateTime.add(DateTime.utc_now(), -8 * 3600, :second)

    %Briefing{
      user: user,
      shift: nil,
      on_shift?: false,
      handoff: nil,
      needs_ack: [],
      recent_recognitions: [],
      own_announcements: [],
      waiting_announcements: 3,
      waiting_messages: 2,
      waiting_recognitions: 1,
      last_shift_ended_at: last_ended
    }
  end
end
