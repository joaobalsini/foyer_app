defmodule Today.Scenarios.OnShiftDepsShifts do
  @moduledoc false

  alias Foyer.Shifts.Shift

  def current_shift_for(%{id: user_id}) do
    %Shift{id: 10, user_id: user_id, started_at: ~U[2026-05-25 06:00:00Z]}
  end

  def last_handoff_for(_user), do: nil
  def last_ended_shift_for(_user), do: nil
end
