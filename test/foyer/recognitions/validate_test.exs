defmodule Foyer.Recognitions.ValidateTest do
  @moduledoc """
  Unit tests for `Foyer.Recognitions.Validate` — pure validation, no DB.

  Covers:
    F.Recognitions.2 — self-recognition rejected
    F.Recognitions.3 — house value vocabulary fixed (changeset-level)
    F.Recognitions.4 — at least one house value required (changeset-level)
    F.Recognitions.5 — bonus points manager-only
    F.Recognitions.6 — bonus point tier enforced
    F.Recognitions.9 — grace window gates edits and removals
  """
  use ExUnit.Case, async: true

  alias Foyer.Accounts.User
  alias Foyer.Recognitions.Recognition
  alias Foyer.Recognitions.Validate

  defp manager(id \\ 1), do: %User{id: id, role: :manager}
  defp staff(id \\ 2), do: %User{id: id, role: :staff}

  defp valid_attrs(overrides) do
    Map.merge(
      %{
        "sender_id" => 1,
        "recipient_id" => 2,
        "body" => "Thank you.",
        "values" => ["care"]
      },
      overrides
    )
  end

  defp changeset(attrs, base \\ %Recognition{}) do
    Recognition.changeset(base, attrs)
  end

  describe "F.Recognitions.2 — ensure_not_self/2" do
    test "rejects when recipient_id matches sender id" do
      cs = changeset(valid_attrs(%{"sender_id" => 7, "recipient_id" => 7}))
      assert {:error, :self_recognition} = Validate.ensure_not_self(manager(7), cs)
    end

    test "passes when recipient_id differs from sender id" do
      cs = changeset(valid_attrs(%{"sender_id" => 7, "recipient_id" => 9}))
      assert :ok = Validate.ensure_not_self(manager(7), cs)
    end
  end

  describe "F.Recognitions.3 — Recognition.changeset/2 vocabulary" do
    test "accepts the six house values" do
      cs =
        changeset(
          valid_attrs(%{"values" => ~w(care craft warmth discretion initiative excellence)})
        )

      assert cs.valid?
    end

    test "rejects unknown tokens like 'team'" do
      cs = changeset(valid_attrs(%{"values" => ["team"]}))
      refute cs.valid?
      assert cs.errors[:values] != nil
    end

    test "rejects a mix of valid and unknown tokens" do
      cs = changeset(valid_attrs(%{"values" => ["care", "team"]}))
      refute cs.valid?
      assert cs.errors[:values] != nil
    end
  end

  describe "F.Recognitions.4 — Recognition.changeset/2 requires at least one value" do
    test "empty values list produces the 'choose at least one value' error" do
      cs = changeset(valid_attrs(%{"values" => []}))
      refute cs.valid?
      assert {"choose at least one value", _} = cs.errors[:values]
    end

    test "values stripped to empty by normalize_values still fails the changeset" do
      attrs =
        %{"sender_id" => 1, "recipient_id" => 2, "body" => "Hi", "values" => ["", nil]}
        |> Validate.normalize_values()

      cs = changeset(attrs)
      refute cs.valid?
      assert {"choose at least one value", _} = cs.errors[:values]
    end
  end

  describe "F.Recognitions.5 — ensure_bonus_allowed/2 and normalize_bonus_points/2" do
    test "manager may grant positive bonus points" do
      cs = changeset(valid_attrs(%{"bonus_points" => 25}))
      assert :ok = Validate.ensure_bonus_allowed(manager(), cs)
    end

    test "staff with zero or nil bonus points passes" do
      zero = changeset(valid_attrs(%{"bonus_points" => 0}))
      assert :ok = Validate.ensure_bonus_allowed(staff(), zero)
    end

    test "staff with positive bonus points is rejected" do
      cs = changeset(valid_attrs(%{"bonus_points" => 25}))
      assert {:error, :unauthorized_points} = Validate.ensure_bonus_allowed(staff(), cs)
    end

    test "normalize_bonus_points forces staff to 0" do
      assert %{"bonus_points" => 0} =
               Validate.normalize_bonus_points(%{"bonus_points" => 100}, staff())
    end

    test "normalize_bonus_points leaves manager input untouched" do
      assert %{"bonus_points" => 100} =
               Validate.normalize_bonus_points(%{"bonus_points" => 100}, manager())
    end
  end

  describe "F.Recognitions.6 — ensure_bonus_tier/1" do
    test "accepts each value in the fixed tier" do
      for tier <- Validate.bonus_tiers() do
        cs = changeset(valid_attrs(%{"bonus_points" => tier}))
        assert :ok = Validate.ensure_bonus_tier(cs), "expected #{tier} to be a valid tier"
      end
    end

    test "rejects off-tier values like 15" do
      cs = changeset(valid_attrs(%{"bonus_points" => 15}))
      assert {:error, :invalid_point_tier} = Validate.ensure_bonus_tier(cs)
    end

    test "bonus_tiers/0 exposes the canonical 0/10/25/50/100 list" do
      assert Validate.bonus_tiers() == [0, 10, 25, 50, 100]
    end
  end

  describe "F.Recognitions.9 — grace window helpers" do
    test "within_grace_window?/1 is true just after insertion" do
      recognition = %Recognition{inserted_at: DateTime.utc_now() |> DateTime.truncate(:second)}
      assert Validate.within_grace_window?(recognition)
    end

    test "within_grace_window?/1 is false past the 15-minute mark" do
      old =
        DateTime.utc_now()
        |> DateTime.add(-(Validate.grace_window_seconds() + 1), :second)
        |> DateTime.truncate(:second)

      refute Validate.within_grace_window?(%Recognition{inserted_at: old})
    end

    test "within_grace_window?/1 is false when inserted_at is missing" do
      refute Validate.within_grace_window?(%Recognition{})
    end

    test "ensure_within_grace/1 mirrors within_grace_window?/1" do
      fresh = %Recognition{inserted_at: DateTime.utc_now() |> DateTime.truncate(:second)}
      assert :ok = Validate.ensure_within_grace(fresh)

      stale = %Recognition{
        inserted_at:
          DateTime.utc_now()
          |> DateTime.add(-(Validate.grace_window_seconds() + 1), :second)
          |> DateTime.truncate(:second)
      }

      assert {:error, :outside_grace_window} = Validate.ensure_within_grace(stale)
    end

    test "ensure_sender/2 only allows the original author" do
      recognition = %Recognition{sender_id: 1}
      assert :ok = Validate.ensure_sender(recognition, %User{id: 1})
      assert {:error, :unauthorized} = Validate.ensure_sender(recognition, %User{id: 2})
    end

    test "grace_window_seconds/0 exposes the 15-minute window" do
      assert Validate.grace_window_seconds() == 15 * 60
    end
  end

  describe "ensure_not_removed/1" do
    test "passes when removed_at is nil" do
      assert :ok = Validate.ensure_not_removed(%Recognition{removed_at: nil})
    end

    test "rejects when the recognition is already soft-removed" do
      assert {:error, :removed} =
               Validate.ensure_not_removed(%Recognition{removed_at: DateTime.utc_now()})
    end
  end

  describe "recognition_attrs/1 and normalize_values/1" do
    test "merges atom and string keys, preferring atom-key values" do
      attrs = Validate.recognition_attrs(%{"body" => "old", body: "new", recipient_id: 5})
      assert attrs["body"] == "new"
      assert attrs["recipient_id"] == 5
    end

    test "drops keys that are not part of the compose form" do
      attrs =
        Validate.recognition_attrs(%{"sender_id" => 99, "body" => "hi", "values" => ["care"]})

      refute Map.has_key?(attrs, "sender_id")
      assert attrs["body"] == "hi"
    end

    test "normalize_values strips blanks and nils" do
      assert %{"values" => ["care"]} =
               Validate.normalize_values(%{"values" => ["care", "", nil]})
    end

    test "normalize_values leaves maps without a values key untouched" do
      assert %{"body" => "hi"} = Validate.normalize_values(%{"body" => "hi"})
    end
  end
end
