defmodule Today.Scenarios.OffShift do
  @moduledoc """
  Scenario: off-shift user, no prior shifts, waiting counts all zero.
  """
  @behaviour Foyer.Today.Behavior

  alias Foyer.Accounts.User
  alias Foyer.Today.Briefing

  @impl true
  def brief_for(%User{} = user) do
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
      last_shift_ended_at: nil
    }
  end
end
