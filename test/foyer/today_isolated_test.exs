defmodule Foyer.TodayIsolatedTest do
  use ExUnit.Case, async: true

  alias Foyer.Accounts.User
  alias Foyer.Today

  test "F.Today.20 unread_since counts eligible unread messages since last shift only without DB" do
    user = %User{id: 42, name: "Maya Okafor", role: :staff}

    briefing =
      Today.brief_for(user, %{
        shifts: Elixir.Today.Scenarios.OffShiftWaitingDepsShifts,
        house: Elixir.Today.Scenarios.OffShiftWaitingDepsHouse,
        chat: Elixir.Today.Scenarios.OffShiftWaitingDepsChat,
        recognitions: Elixir.Today.Scenarios.OffShiftWaitingDepsRecognitions
      })

    assert briefing.on_shift? == false
    assert briefing.last_shift_ended_at == ~U[2026-05-25 13:00:00Z]
    assert briefing.waiting_announcements == 3
    assert briefing.waiting_messages == 2
    assert briefing.waiting_recognitions == 1
  end
end
