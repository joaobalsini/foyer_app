defmodule Foyer.TodayTest do
  use Foyer.DataCase, async: true

  alias Foyer.Accounts.User
  alias Foyer.Repo
  alias Foyer.Shifts.Shift
  alias Foyer.Today
  alias Foyer.Today.Briefing

  # ──────────────────────────────────────────────────────────
  # Briefing.waiting_total/1
  # ──────────────────────────────────────────────────────────

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

  # ──────────────────────────────────────────────────────────
  # Today.brief_for/1 — shape tests with mocked cousins
  # ──────────────────────────────────────────────────────────

  # Foyer.Today calls real context modules directly (not via LiveDeps).
  # These tests use real DB data via the sandbox.
  describe "Today.brief_for/1 with real DB" do
    test "returns a Briefing struct with on_shift? true for a user with an open shift" do
      user = insert_user()
      _shift = insert_shift!(user)

      briefing = Today.brief_for(user)

      assert %Briefing{} = briefing
      assert briefing.on_shift? == true
      assert briefing.user == user
      assert is_list(briefing.needs_ack)
      assert is_list(briefing.recent_recognitions)
    end

    test "returns a Briefing struct with on_shift? false for a user with no open shift" do
      user = insert_user()

      briefing = Today.brief_for(user)

      assert %Briefing{} = briefing
      assert briefing.on_shift? == false
      assert briefing.waiting_announcements >= 0
      assert briefing.waiting_messages >= 0
      assert briefing.waiting_recognitions >= 0
    end

    test "on_shift? false: recent_recognitions is empty list" do
      user = insert_user()
      briefing = Today.brief_for(user)
      assert briefing.recent_recognitions == []
    end

    test "on_shift? false: needs_ack is empty list" do
      user = insert_user()
      briefing = Today.brief_for(user)
      assert briefing.needs_ack == []
    end

    test "on_shift? false: own_announcements is empty list" do
      user = insert_user()
      briefing = Today.brief_for(user)
      assert briefing.own_announcements == []
    end

    test "on_shift? true: waiting counts are all zero" do
      user = insert_user()
      _shift = insert_shift!(user)
      briefing = Today.brief_for(user)
      assert briefing.waiting_announcements == 0
      assert briefing.waiting_messages == 0
      assert briefing.waiting_recognitions == 0
    end
  end

  # ──────────────────────────────────────────────────────────
  # Helper functions
  # ──────────────────────────────────────────────────────────

  defp insert_user do
    {:ok, user} =
      %User{}
      |> User.changeset(%{
        name: "Unit Test User",
        initials: "UT",
        role: :staff,
        department: "Testing",
        title: "Tester"
      })
      |> Repo.insert()

    user
  end

  defp insert_shift!(user) do
    {:ok, shift} =
      %Shift{}
      |> Shift.changeset(%{
        user_id: user.id,
        started_at: DateTime.utc_now()
      })
      |> Repo.insert()

    shift
  end
end
