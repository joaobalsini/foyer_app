defmodule Foyer.RecognitionsTest do
  use Foyer.DataCase, async: true

  import FoyerWeb.ScaffoldFixtures

  alias Foyer.Accounts.User
  alias Foyer.Recognitions
  alias Foyer.Recognitions.PointEntry
  alias Foyer.Recognitions.Recognition
  alias Foyer.Repo

  setup do
    {:ok, seed_scaffold!()}
  end

  describe "give/2" do
    test "F.Recognitions.1 sends recognition to another user", ctx do
      assert {:ok, recognition} =
               Recognitions.give(ctx.maya, %{
                 "recipient_id" => ctx.hugo.id,
                 "body" => "Made the room repair feel effortless.",
                 "values" => ["craft"],
                 "public" => "true"
               })

      assert recognition.sender_id == ctx.maya.id
      assert recognition.recipient_id == ctx.hugo.id
      assert recognition.values == ["craft"]
    end

    test "F.Recognitions.2 rejects self-recognition", ctx do
      assert {:error, :self_recognition} =
               Recognitions.give(ctx.maya, %{
                 "recipient_id" => ctx.maya.id,
                 "body" => "I was great.",
                 "values" => ["care"]
               })
    end

    test "F.Recognitions.3 and F.Recognitions.4 enforce the six required values", ctx do
      assert {:error, changeset} =
               Recognitions.give(ctx.maya, %{
                 "recipient_id" => ctx.hugo.id,
                 "body" => "Thank you.",
                 "values" => ["team"]
               })

      assert %{values: [_]} = errors_on(changeset)

      assert {:error, changeset} =
               Recognitions.give(ctx.maya, %{
                 "recipient_id" => ctx.hugo.id,
                 "body" => "Thank you.",
                 "values" => []
               })

      assert %{values: [_]} = errors_on(changeset)
    end

    test "F.Recognitions.5 and F.Recognitions.6 restrict point tiers", ctx do
      assert {:ok, no_points} =
               Recognitions.give(ctx.maya, %{
                 "recipient_id" => ctx.hugo.id,
                 "body" => "Thanks.",
                 "values" => ["care"],
                 "bonus_points" => "100"
               })

      assert no_points.bonus_points == 0

      assert {:error, :invalid_point_tier} =
               Recognitions.give(ctx.charlotte, %{
                 "recipient_id" => ctx.hugo.id,
                 "body" => "Thanks.",
                 "values" => ["care"],
                 "bonus_points" => "15"
               })
    end

    test "F.Recognitions.7 writes ledger and point balance in one transaction", ctx do
      before_points = Repo.get!(User, ctx.hugo.id).points_balance

      assert {:ok, recognition} =
               Recognitions.give(ctx.charlotte, %{
                 "recipient_id" => ctx.hugo.id,
                 "body" => "Recovered the suite quickly.",
                 "values" => ["initiative"],
                 "bonus_points" => "25"
               })

      assert Repo.get!(User, ctx.hugo.id).points_balance == before_points + 25

      assert [%PointEntry{delta: 25, reason: "recognition_granted"}] =
               Repo.all(from e in PointEntry, where: e.recognition_id == ^recognition.id)
    end
  end

  describe "update/remove visibility" do
    test "F.Recognitions.8 soft removal reverses points", ctx do
      assert {:ok, recognition} =
               Recognitions.give(ctx.charlotte, %{
                 "recipient_id" => ctx.hugo.id,
                 "body" => "Recovered the suite quickly.",
                 "values" => ["initiative"],
                 "bonus_points" => "25"
               })

      with_points = Repo.get!(User, ctx.hugo.id).points_balance

      assert {:ok, removed} = Recognitions.remove_recognition(recognition, ctx.charlotte)
      assert removed.removed_at
      assert Repo.get!(User, ctx.hugo.id).points_balance == with_points - 25

      assert Enum.map(
               Repo.all(from e in PointEntry, where: e.recognition_id == ^recognition.id),
               & &1.delta
             ) == [25, -25]

      refute Enum.any?(Recognitions.feed_public(), &(&1.id == recognition.id))
    end

    test "F.Recognitions.9 edit and remove are rejected outside grace", ctx do
      old = age_recognition!(ctx.hugo_recognition, 20 * 60)

      assert {:error, :outside_grace_window} =
               Recognitions.update_recognition(old, ctx.charlotte, %{"body" => "Too late"})

      assert {:error, :outside_grace_window} =
               Recognitions.remove_recognition(old, ctx.charlotte)
    end

    test "F.Recognitions.10 private recognitions are visible only to sender or recipient", ctx do
      refute Enum.any?(Recognitions.feed_public(), &(&1.id == ctx.private_recognition.id))

      assert Recognitions.get_recognition!(ctx.private_recognition.id, ctx.maya)
      assert Recognitions.get_recognition!(ctx.private_recognition.id, ctx.aisha)

      assert_raise Ecto.NoResultsError, fn ->
        Recognitions.get_recognition!(ctx.private_recognition.id, ctx.hugo)
      end
    end
  end

  defp age_recognition!(recognition, seconds) do
    inserted_at =
      DateTime.add(DateTime.utc_now(), -seconds, :second) |> DateTime.truncate(:second)

    from(r in Recognition, where: r.id == ^recognition.id)
    |> Repo.update_all(set: [inserted_at: inserted_at])

    Repo.get!(Recognition, recognition.id)
  end
end
