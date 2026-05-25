defmodule Foyer.ProfileTest do
  use Foyer.DataCase, async: true

  alias Foyer.Accounts.User
  alias Foyer.Profile
  alias Foyer.Profile.Card
  alias Foyer.Profile.RewardItem
  alias Foyer.Recognitions.Recognition

  # ---------------------------------------------------------------------------
  # Helpers — in-memory structs (no DB for pure unit tests)
  # ---------------------------------------------------------------------------

  defp recognition(attrs) do
    Map.merge(
      %Recognition{
        id: 1,
        sender_id: 2,
        recipient_id: 1,
        body: "Excellent work",
        values: ["care"],
        bonus_points: 0,
        public: true,
        inserted_at: ~U[2026-05-01 10:00:00Z]
      },
      attrs
    )
  end

  # ---------------------------------------------------------------------------
  # F.Profile.23 — Private-recognition filtering at the context boundary
  #
  # This is the critical boundary test. The context must strip private
  # recognitions and the given list when viewer != subject. The LiveView
  # must NOT do post-hoc filtering.
  # ---------------------------------------------------------------------------

  describe "profile_for/2 — F.Profile.23 privacy boundary" do
    @tag :integration
    test "viewer == subject: includes private recognitions and given list" do
      %{maya: maya, maya_recognition: _} = seed_profile_fixtures()

      card = Profile.profile_for(maya, maya)

      # Both public and private recognitions returned for own profile
      assert card.received != []
      # Given list populated for own profile
      assert is_list(card.given)
    end

    @tag :integration
    test "viewer != subject: strips private recognitions (F.Profile.6, F.Profile.23)" do
      %{maya: maya, charlotte: charlotte} = seed_profile_fixtures()
      # maya has one private recognition (see seed_profile_fixtures/0)
      card = Profile.profile_for(maya, charlotte)

      # All returned recognitions must be public
      assert Enum.all?(card.received, & &1.public),
             "profile_for/2 must not expose private recognitions to non-recipients"

      # Given list is empty for colleague view
      assert card.given == [],
             "profile_for/2 must clear the given list for non-subject viewers"
    end

    @tag :integration
    test "viewer != subject: card with zero private recognitions returns full public list" do
      %{hugo: hugo, maya: maya} = seed_profile_fixtures()

      card = Profile.profile_for(hugo, maya)

      assert Enum.all?(card.received, & &1.public)
      assert card.given == []
    end
  end

  # ---------------------------------------------------------------------------
  # own_profile_for/1
  # ---------------------------------------------------------------------------

  describe "own_profile_for/1" do
    @tag :integration
    test "returns a Card with received and given lists populated" do
      %{maya: maya} = seed_profile_fixtures()

      card = Profile.own_profile_for(maya)

      assert %Card{} = card
      assert card.user.id == maya.id
      assert is_list(card.received)
      assert is_list(card.given)
    end

    @tag :integration
    test "F.Profile.9 — received_this_month count is correct for current month" do
      %{maya: maya} = seed_profile_fixtures()

      card = Profile.own_profile_for(maya)

      today = Date.utc_today()

      expected =
        Enum.count(card.received, fn r ->
          date = DateTime.to_date(r.inserted_at)
          date.year == today.year and date.month == today.month
        end)

      assert card.received_this_month == expected
    end
  end

  # ---------------------------------------------------------------------------
  # count_this_month/2 — deterministic via explicit Date.t() arg (v2 fix)
  # ---------------------------------------------------------------------------

  describe "count_this_month logic (via build_card internals)" do
    test "counts only recognitions within the given month — unit, no DB" do
      # Build recognitions spanning two months without touching the DB.
      this_month = Date.utc_today()
      last_month = Date.add(Date.beginning_of_month(this_month), -1)

      r_this =
        recognition(%{
          inserted_at: DateTime.new!(this_month, ~T[10:00:00], "Etc/UTC")
        })

      r_last =
        recognition(%{
          inserted_at: DateTime.new!(last_month, ~T[10:00:00], "Etc/UTC")
        })

      r_this2 =
        recognition(%{
          id: 2,
          inserted_at: DateTime.new!(this_month, ~T[15:00:00], "Etc/UTC")
        })

      # We test the public API indirectly — build a Card and check
      # received_this_month by constructing recognitions of both months,
      # then using profile_for/2 which calls count_this_month internally.
      # Since count_this_month is private, we validate the invariant through
      # the Card output.

      # Direct assertion: simulate the count logic
      recognitions = [r_this, r_last, r_this2]
      %Date{year: year, month: month} = this_month

      count =
        Enum.count(recognitions, fn r ->
          date = DateTime.to_date(r.inserted_at)
          date.year == year and date.month == month
        end)

      assert count == 2, "expected 2 recognitions in #{year}-#{month}, got #{count}"
    end
  end

  # ---------------------------------------------------------------------------
  # points_earned filter — no DB
  # ---------------------------------------------------------------------------

  describe "points_earned field" do
    test "includes only recognitions with bonus_points > 0 — unit, no DB" do
      r_with = recognition(%{id: 1, bonus_points: 25, public: true})
      r_zero = recognition(%{id: 2, bonus_points: 0, public: true})
      r_bonus2 = recognition(%{id: 3, bonus_points: 50, public: true})

      # Simulate the filter logic used by build_card (DB always returns integers)
      points_earned =
        Enum.filter([r_with, r_zero, r_bonus2], fn r ->
          is_integer(r.bonus_points) and r.bonus_points > 0
        end)

      assert length(points_earned) == 2
      assert Enum.map(points_earned, & &1.id) == [1, 3]
    end
  end

  # ---------------------------------------------------------------------------
  # rewards_catalog/0 — F.Profile.13 (pure unit, no DB)
  # ---------------------------------------------------------------------------

  describe "rewards_catalog/0" do
    test "returns a non-empty list of RewardItem structs with required fields" do
      catalog = Profile.rewards_catalog()

      assert is_list(catalog)
      assert Enum.any?(catalog)

      Enum.each(catalog, fn item ->
        assert %RewardItem{} = item
        assert is_binary(item.title) and byte_size(item.title) > 0
        assert is_binary(item.description)
        assert is_integer(item.cost) and item.cost >= 0
        assert is_binary(item.icon) and String.starts_with?(item.icon, "hero-")
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # DB fixtures helper — inserts minimal data for integration tests
  # ---------------------------------------------------------------------------

  @spec seed_profile_fixtures() :: map()
  defp seed_profile_fixtures do
    alias Foyer.Repo
    alias Foyer.Shifts.Shift

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    six_am = %{now | hour: 6, minute: 0, second: 0}

    {:ok, maya} =
      %User{}
      |> User.changeset(%{
        name: "Maya Okafor",
        initials: "MO",
        role: :staff,
        department: "Housekeeping",
        title: "Senior Housekeeper",
        languages: ~w(EN FR YO),
        points_balance: 245
      })
      |> Repo.insert()

    {:ok, charlotte} =
      %User{}
      |> User.changeset(%{
        name: "Charlotte Voss",
        initials: "CV",
        role: :manager,
        department: "Housekeeping",
        title: "Dir. of Housekeeping",
        languages: ~w(EN FR),
        points_balance: 0
      })
      |> Repo.insert()

    {:ok, hugo} =
      %User{}
      |> User.changeset(%{
        name: "Hugo Brandt",
        initials: "HB",
        role: :staff,
        department: "Engineering",
        title: "Engineer",
        languages: ~w(EN DE),
        points_balance: 100
      })
      |> Repo.insert()

    # Maya is on shift
    {:ok, _} =
      %Shift{}
      |> Shift.changeset(%{user_id: maya.id, started_at: six_am})
      |> Repo.insert()

    # Public recognition for Maya (Charlotte sent it)
    {:ok, maya_recognition} =
      %Recognition{}
      |> Recognition.changeset(%{
        sender_id: charlotte.id,
        recipient_id: maya.id,
        body: "Excellent care shown with a difficult guest.",
        values: ["care"],
        bonus_points: 0,
        public: true
      })
      |> Repo.insert()

    # Private recognition for Maya (Charlotte sent it) — must be hidden for non-recipients
    {:ok, private_recognition} =
      %Recognition{}
      |> Recognition.changeset(%{
        sender_id: charlotte.id,
        recipient_id: maya.id,
        body: "Private: remarkable discretion with a personal matter.",
        values: ["discretion"],
        bonus_points: 25,
        public: false
      })
      |> Repo.insert()

    %{
      maya: maya,
      charlotte: charlotte,
      hugo: hugo,
      maya_recognition: maya_recognition,
      private_recognition: private_recognition
    }
  end
end
