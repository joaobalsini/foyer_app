defmodule Today.Scenarios.OnShiftDepsHouse do
  @moduledoc false

  def needs_ack_from(_user), do: []
  def authored_by(_user), do: []
  def unacked_since(_user, _since), do: raise("unacked_since should not run while on shift")
end
