defmodule Today.Scenarios.OffShiftWaitingDepsShifts do
  @moduledoc false

  alias Foyer.Shifts.Shift

  @ended_at ~U[2026-05-25 13:00:00Z]

  def current_shift_for(_user), do: nil
  def last_handoff_for(_user), do: nil
  def last_ended_shift_for(%{id: user_id}), do: %Shift{user_id: user_id, ended_at: @ended_at}
end
