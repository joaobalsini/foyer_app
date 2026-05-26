defmodule Foyer.TodayTest do
  @moduledoc """
  Unit tests for `Foyer.Today` — the briefing assembler that turns shift
  state, announcements, recognitions, and chat unread counts into a
  `Today.Briefing` DTO. Pure-struct testing with injected callables; no DB.

  Covers:
    F.Today.20 — unread_since anchors waiting counts on last_shift_ended_at
  """
  use ExUnit.Case, async: true

  alias Foyer.Accounts.User
  alias Foyer.Today
  alias Foyer.Today.Briefing

  describe "Briefing.waiting_total/1" do
    test "sums the three waiting fields" do
      briefing = %Briefing{
        user: %Foyer.Accounts.User{},
        shift: nil,
        on_shift?: false,
        handoff: nil,
        needs_ack: [],
        recent_recognitions: [],
        own_announcements: [],
        waiting_announcements: 3,
        waiting_messages: 2,
        waiting_recognitions: 1,
        last_shift_ended_at: nil
      }

      assert Briefing.waiting_total(briefing) == 6
    end

    test "returns zero when all waiting fields are zero" do
      briefing = %Briefing{
        user: %Foyer.Accounts.User{},
        shift: nil,
        on_shift?: false,
        handoff: nil,
        needs_ack: [],
        recent_recognitions: [],
        own_announcements: [],
        waiting_announcements: 0,
        waiting_messages: 0,
        waiting_recognitions: 0,
        last_shift_ended_at: nil
      }

      assert Briefing.waiting_total(briefing) == 0
    end
  end

  describe "Today.brief_for/2 with injected deps" do
    test "returns a Briefing struct with on_shift? true for a user with an open shift" do
      user = user()
      briefing = Today.brief_for(user, on_shift_deps())

      assert %Briefing{} = briefing
      assert briefing.on_shift? == true
      assert briefing.user == user
      assert is_list(briefing.needs_ack)
      assert is_list(briefing.recent_recognitions)
    end

    test "returns a Briefing struct with on_shift? false for a user with no open shift" do
      user = user()
      briefing = Today.brief_for(user, off_shift_deps())

      assert %Briefing{} = briefing
      assert briefing.on_shift? == false
      assert briefing.waiting_announcements == 3
      assert briefing.waiting_messages == 2
      assert briefing.waiting_recognitions == 1
    end

    test "on_shift? false: recent_recognitions is empty list" do
      briefing = Today.brief_for(user(), off_shift_deps())
      assert briefing.recent_recognitions == []
    end

    test "on_shift? false: needs_ack is empty list" do
      briefing = Today.brief_for(user(), off_shift_deps())
      assert briefing.needs_ack == []
    end

    test "on_shift? false: own_announcements is empty list" do
      briefing = Today.brief_for(user(), off_shift_deps())
      assert briefing.own_announcements == []
    end

    test "on_shift? true: waiting counts are all zero" do
      briefing = Today.brief_for(user(), on_shift_deps())
      assert briefing.waiting_announcements == 0
      assert briefing.waiting_messages == 0
      assert briefing.waiting_recognitions == 0
    end

    test "on_shift? true: recent recognitions include authored private recognitions" do
      briefing = Today.brief_for(user(), on_shift_deps())

      assert Enum.any?(briefing.recent_recognitions, &(&1.id == 42))
    end

    test "F.Today.20 — unread_since anchors waiting counts on last_shift_ended_at" do
      briefing = Today.brief_for(user(), off_shift_deps())

      # The OffShiftWaitingDepsShifts scenario pins last_shift_ended_at so the
      # Chat/House/Recognitions stubs can return their since-anchored counts.
      assert briefing.on_shift? == false
      assert briefing.last_shift_ended_at == ~U[2026-05-25 13:00:00Z]
      assert briefing.waiting_announcements == 3
      assert briefing.waiting_messages == 2
      assert briefing.waiting_recognitions == 1
    end
  end

  defp user do
    %User{
      id: 42,
      name: "Unit Test User",
      initials: "UT",
      role: :staff,
      department: "Testing",
      title: "Tester"
    }
  end

  defp on_shift_deps do
    %{
      shifts: Elixir.Today.Scenarios.OnShiftDepsShifts,
      house: Elixir.Today.Scenarios.OnShiftDepsHouse,
      chat: Elixir.Today.Scenarios.OnShiftDepsChat,
      recognitions: Elixir.Today.Scenarios.OnShiftDepsRecognitions
    }
  end

  defp off_shift_deps do
    %{
      shifts: Elixir.Today.Scenarios.OffShiftWaitingDepsShifts,
      house: Elixir.Today.Scenarios.OffShiftWaitingDepsHouse,
      chat: Elixir.Today.Scenarios.OffShiftWaitingDepsChat,
      recognitions: Elixir.Today.Scenarios.OffShiftWaitingDepsRecognitions
    }
  end
end
