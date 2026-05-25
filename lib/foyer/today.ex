defmodule Foyer.Today do
  @moduledoc """
  Read-only morning-briefing orchestrator. Calls cousin contexts (Shifts,
  House, Recognitions) — see plan §6.8 for the conscious trade-off.
  """
  @behaviour Foyer.TodayPort

  alias Foyer.Accounts.User
  alias Foyer.House
  alias Foyer.Recognitions
  alias Foyer.Shifts
  alias Foyer.Today.Briefing

  @impl true
  @spec brief_for(User.t()) :: Briefing.t()
  def brief_for(%User{} = user) do
    shift = Shifts.current_shift_for(user)
    needs_ack = House.needs_ack_from(user)

    %Briefing{
      user: user,
      shift: shift,
      on_shift?: not is_nil(shift),
      handoff: Shifts.last_handoff_for(user),
      needs_ack: needs_ack,
      recent_recognition: Recognitions.received_by(user) |> Enum.take(3),
      waiting_count: length(needs_ack)
    }
  end
end
