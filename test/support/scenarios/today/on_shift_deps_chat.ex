defmodule Today.Scenarios.OnShiftDepsChat do
  @moduledoc false

  def unread_since(_user, _since), do: raise("unread_since should not run while on shift")
end
