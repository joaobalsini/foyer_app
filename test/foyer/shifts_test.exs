defmodule Foyer.ShiftsTest do
  use Foyer.DataCase, async: true

  import FoyerWeb.ScaffoldFixtures

  alias Foyer.Shifts

  setup do
    {:ok, seed_scaffold!()}
  end

  describe "end_shift/2" do
    test "requires a handoff note when submitting the handoff form", ctx do
      shift = Shifts.current_shift_for(ctx.maya)

      assert {:error, changeset} =
               Shifts.end_shift(shift, %{
                 "handoff_note" => "",
                 "handoff_channel_id" => ctx.suite_412.channel_id
               })

      assert {"can't be blank", _} = changeset.errors[:handoff_note]
    end

    test "requires a handoff channel when submitting a handoff note", ctx do
      shift = Shifts.current_shift_for(ctx.maya)

      assert {:error, changeset} =
               Shifts.end_shift(shift, %{
                 "handoff_note" => "All clear in 412.",
                 "handoff_channel_id" => ""
               })

      assert {"can't be blank", _} = changeset.errors[:handoff_channel_id]
    end

    test "accepts a handoff channel when submitting a handoff note", ctx do
      shift = Shifts.current_shift_for(ctx.maya)

      assert {:ok, ended} =
               Shifts.end_shift(shift, %{
                 "handoff_note" => "All clear in 412.",
                 "handoff_channel_id" => ctx.suite_412.channel_id
               })

      assert ended.ended_at
      assert ended.handoff_channel_id == ctx.suite_412.channel_id
    end
  end
end
