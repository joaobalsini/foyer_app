defmodule Foyer.HouseTest do
  @moduledoc """
  DB-backed integration tests for `Foyer.House`. The pure
  validation/permission/grace-window/bucket rules live in
  `Foyer.House.ValidateTest` and are not re-asserted here; the tests below
  exist to prove the things that actually require Postgres: persisted writes,
  soft-removal queryability, unique-index idempotency, the receipts join, and
  the channel-membership gate at the context boundary.

  Covers:
    F.Announcements.1  — managers publish to their own channels (persistence)
    F.Announcements.5  — pin/unpin updates `pinned_at`
    F.Announcements.6  — soft removal sets `removed_at` and preserves receipts
    F.Announcements.8  — acknowledge / mark-read are idempotent (unique index)
    F.Announcements.9  — receipts bucket every channel member exactly once
    F.Announcements.10 — membership is enforced at the context boundary
  """
  use Foyer.DataCase, async: true

  import FoyerWeb.ScaffoldFixtures

  alias Foyer.House
  alias Foyer.House.Announcement
  alias Foyer.Repo

  setup do
    {:ok, seed_scaffold!()}
  end

  describe "create_announcement/2" do
    test "F.Announcements.1 managers can create announcements for their channels", ctx do
      attrs = %{
        "title" => "Lift inspection",
        "body" => "Service lift will pause at noon.",
        "channel_id" => ctx.suite_412.channel_id,
        "requires_ack" => "true"
      }

      assert {:ok, announcement} = House.create_announcement(ctx.charlotte, attrs)
      assert announcement.author_id == ctx.charlotte.id
      assert announcement.requires_ack
      assert announcement.channel_id == ctx.suite_412.channel_id
      assert Repo.get!(Announcement, announcement.id).id == announcement.id
    end
  end

  describe "soft removal" do
    test "F.Announcements.6 removal is soft and removed rows leave user feeds", ctx do
      assert {:ok, removed} = House.remove_announcement(ctx.suite_412, ctx.charlotte)
      assert removed.removed_at

      assert Repo.get!(Announcement, ctx.suite_412.id).removed_at
      refute Enum.any?(House.feed_for(ctx.maya), &(&1.id == ctx.suite_412.id))
    end

    test "F.Announcements.6 / F.Today.14 removed announcements leave manager-authored posts",
         ctx do
      assert {:ok, removed} = House.remove_announcement(ctx.suite_412, ctx.charlotte)
      refute Enum.any?(House.authored_by(ctx.charlotte), &(&1.id == removed.id))
    end

    test "F.Announcements.6 removed announcements keep manager receipts auditable", ctx do
      assert {:ok, removed} = House.remove_announcement(ctx.suite_412, ctx.charlotte)
      assert {:ok, receipts} = House.receipts_for(removed, ctx.charlotte)

      assert Enum.map(receipts.acknowledged, & &1.name) == ["Aisha Bello"]
      assert Enum.map(receipts.unread, & &1.name) == ["Maya Okafor"]
    end
  end

  describe "pinning and acknowledgements" do
    test "F.Announcements.5 managers can pin and unpin announcements", ctx do
      assert {:ok, pinned} = House.pin_announcement(ctx.suite_412, ctx.charlotte)
      assert pinned.pinned_at

      assert {:ok, unpinned} = House.unpin_announcement(pinned, ctx.charlotte)
      refute unpinned.pinned_at
    end

    test "F.Announcements.8 reads and acknowledgements are idempotent", ctx do
      assert {:ok, _} = House.mark_read(ctx.suite_412, ctx.maya)
      assert {:ok, _} = House.mark_read(ctx.suite_412, ctx.maya)

      assert {:ok, _} = House.acknowledge(ctx.suite_412, ctx.maya)
      assert {:ok, _} = House.acknowledge(ctx.suite_412, ctx.maya)
    end
  end

  describe "receipts and membership authorization" do
    test "F.Announcements.9 managers can view receipt groups", ctx do
      assert {:ok, _} = House.mark_read(ctx.suite_412, ctx.maya)
      assert {:ok, receipts} = House.receipts_for(ctx.suite_412, ctx.charlotte)

      assert Enum.map(receipts.acknowledged, & &1.name) == ["Aisha Bello"]
      assert Enum.map(receipts.read_without_acknowledgement, & &1.name) == ["Maya Okafor"]
      assert receipts.unread == []
      assert Enum.map(receipts.off_shift, & &1.name) == ["Jamal Mensah"]
    end

    test "F.Announcements.10 forged membership attempts are rejected", ctx do
      assert {:error, :not_channel_member} =
               House.mark_read(ctx.leadership_only_announcement, ctx.maya)

      assert {:error, :not_channel_member} =
               House.pin_announcement(ctx.suite_412, ctx.rafael)
    end

    test "F.Announcements.10 removal requires channel membership", ctx do
      author_removed_from_channel =
        ctx.suite_412
        |> Announcement.changeset(%{"author_id" => ctx.rafael.id})
        |> Repo.update!()

      assert {:error, :not_channel_member} =
               House.remove_announcement(author_removed_from_channel, ctx.rafael)
    end
  end
end
