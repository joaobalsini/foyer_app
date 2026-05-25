defmodule Today.Scenarios.OnShiftDepsRecognitions do
  @moduledoc false

  def received_by(_target, _viewer), do: []

  def private_received_since(_user, _since),
    do: raise("private_received_since should not run while on shift")
end
