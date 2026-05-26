defmodule Today.Scenarios.OnShiftDepsRecognitions do
  @moduledoc false

  alias Foyer.Recognitions.Recognition

  def received_by(_target, _viewer), do: []

  def given_by(user, _viewer) do
    [
      %Recognition{
        id: 42,
        sender_id: user.id,
        sender: user,
        recipient_id: 99,
        body: "Private recognition I authored.",
        values: ["care"],
        public: false,
        inserted_at: ~U[2026-05-25 14:00:00Z]
      }
    ]
  end

  def private_received_since(_user, _since),
    do: raise("private_received_since should not run while on shift")
end
