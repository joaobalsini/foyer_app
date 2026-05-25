defmodule Today.Scenarios.OffShiftWaitingDepsRecognitions do
  @moduledoc false

  @since ~U[2026-05-25 13:00:00Z]

  def received_by(_target, _viewer), do: []
  def private_received_since(_user, @since), do: 1
end
