defmodule Today.Scenarios.OffShiftWaitingDepsHouse do
  @moduledoc false

  @since ~U[2026-05-25 13:00:00Z]

  def needs_ack_from(_user), do: []
  def authored_by(_user), do: []
  def unacked_since(_user, @since), do: 3
end
