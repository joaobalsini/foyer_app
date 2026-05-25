defmodule Foyer.ProfileTest do
  use ExUnit.Case, async: true

  alias Foyer.Accounts.User
  alias Foyer.Profile
  alias Foyer.Profile.Card
  alias Foyer.Profile.RewardItem
  alias Foyer.Recognitions.Recognition

  defp user(attrs) do
    Map.merge(
      %User{
        id: 1,
        name: "Maya Okafor",
        initials: "MO",
        role: :staff,
        department: "Housekeeping",
        title: "Senior Housekeeper",
        languages: ~w(EN FR YO),
        points_balance: 245
      },
      attrs
    )
  end

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

  defp profile_opts(received, given \\ []) do
    [
      received_by: fn _subject, _viewer -> received end,
      given_by: fn _subject, _viewer -> given end,
      current_shift_for: fn _subject -> %{id: 1} end
    ]
  end

  describe "profile_for/2 privacy boundary" do
    test "viewer is subject: includes private recognitions and given list" do
      maya = user(%{id: 1})
      public = recognition(%{id: 1, public: true})
      private = recognition(%{id: 2, public: false})
      given = [recognition(%{id: 3, sender_id: maya.id, recipient_id: 2, public: false})]

      card = Profile.profile_for(maya, maya, profile_opts([public, private], given))

      assert %Card{} = card
      assert card.received == [public, private]
      assert card.given == given
    end

    test "viewer is colleague: strips private recognitions and clears given list" do
      maya = user(%{id: 1})
      charlotte = user(%{id: 2, name: "Charlotte Voss", initials: "CV", role: :manager})
      public = recognition(%{id: 1, public: true})
      private = recognition(%{id: 2, public: false})
      given = [recognition(%{id: 3, sender_id: maya.id, recipient_id: charlotte.id})]

      card = Profile.profile_for(maya, charlotte, profile_opts([public, private], given))

      assert card.received == [public]
      assert card.given == []
    end
  end

  describe "own_profile_for/1" do
    test "returns a card with profile totals" do
      maya = user(%{id: 1, points_balance: 245})
      current_month = Date.utc_today()
      previous_month = Date.add(Date.beginning_of_month(current_month), -1)

      received = [
        recognition(%{id: 1, inserted_at: DateTime.new!(current_month, ~T[10:00:00], "Etc/UTC")}),
        recognition(%{
          id: 2,
          bonus_points: 25,
          inserted_at: DateTime.new!(previous_month, ~T[10:00:00], "Etc/UTC")
        })
      ]

      card = Profile.own_profile_for(maya, profile_opts(received))

      assert %Card{} = card
      assert card.user == maya
      assert card.points == 245
      assert card.on_shift?
      assert card.received_this_month == 1
      assert Enum.map(card.points_earned, & &1.id) == [2]
    end

    test "treats nil point balance as zero and nil shift as off shift" do
      maya = user(%{points_balance: nil})

      card =
        Profile.own_profile_for(maya,
          received_by: fn _subject, _viewer -> [] end,
          given_by: fn _subject, _viewer -> [] end,
          current_shift_for: fn _subject -> nil end
        )

      assert card.points == 0
      refute card.on_shift?
    end
  end

  describe "rewards_catalog/0" do
    test "returns reward item structs with required fields" do
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
end
