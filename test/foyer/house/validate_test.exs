defmodule Foyer.House.ValidateTest do
  @moduledoc """
  Unit tests for `Foyer.House.Validate` — pure validation, no DB.

  Covers:
    F.Announcements.2 — staff cannot compose
    F.Announcements.3 — author may edit within grace
    F.Announcements.4 — edit/remove rejected after grace or non-author
    F.Announcements.6 — soft-removal gate (`ensure_not_removed`)
    F.Announcements.7 — author excluded from required-ack set
    F.Announcements.9 — receipt buckets cover every member exactly once
  """
  use ExUnit.Case, async: true

  alias Foyer.Accounts.User
  alias Foyer.House.Announcement
  alias Foyer.House.Validate

  describe "grace_window_seconds/0 and receipt_buckets/0" do
    test "exposes the 5-minute grace window in seconds" do
      assert Validate.grace_window_seconds() == 5 * 60
    end

    test "exposes the four receipt buckets in render order" do
      assert Validate.receipt_buckets() == [
               :acknowledged,
               :read_without_acknowledgement,
               :unread,
               :off_shift
             ]
    end
  end

  describe "F.Announcements.2 — ensure_manager/1" do
    test "managers are allowed" do
      assert :ok = Validate.ensure_manager(%User{id: 1, role: :manager})
    end

    test "staff are rejected with :unauthorized" do
      assert {:error, :unauthorized} = Validate.ensure_manager(%User{id: 1, role: :staff})
    end

    test "users without a role are rejected with :unauthorized" do
      assert {:error, :unauthorized} = Validate.ensure_manager(%User{id: 1, role: nil})
    end
  end

  describe "F.Announcements.4 — ensure_author/2" do
    test "the announcement's author is allowed" do
      assert :ok =
               Validate.ensure_author(
                 %Announcement{author_id: 7},
                 %User{id: 7, role: :manager}
               )
    end

    test "any other user is rejected with :unauthorized" do
      assert {:error, :unauthorized} =
               Validate.ensure_author(
                 %Announcement{author_id: 7},
                 %User{id: 8, role: :manager}
               )
    end
  end

  describe "F.Announcements.3 / F.Announcements.4 — ensure_within_grace/1 and within_grace_window?/1" do
    test "returns :ok when published_at is inside the grace window" do
      announcement = %Announcement{published_at: seconds_ago(60)}

      assert :ok = Validate.ensure_within_grace(announcement)
      assert Validate.within_grace_window?(announcement)
    end

    test "returns :ok at the inclusive grace window edge" do
      announcement = %Announcement{
        published_at: seconds_ago(Validate.grace_window_seconds())
      }

      assert :ok = Validate.ensure_within_grace(announcement)
    end

    test "returns {:error, :outside_grace_window} once the window has expired" do
      announcement = %Announcement{
        published_at: seconds_ago(Validate.grace_window_seconds() + 1)
      }

      assert {:error, :outside_grace_window} = Validate.ensure_within_grace(announcement)
      refute Validate.within_grace_window?(announcement)
    end

    test "an announcement with no published_at is treated as outside the window" do
      announcement = %Announcement{published_at: nil}

      assert {:error, :outside_grace_window} = Validate.ensure_within_grace(announcement)
      refute Validate.within_grace_window?(announcement)
    end
  end

  describe "F.Announcements.6 — ensure_not_removed/1" do
    test "returns :ok when removed_at is nil" do
      assert :ok = Validate.ensure_not_removed(%Announcement{removed_at: nil})
    end

    test "returns {:error, :removed} once removed_at is set" do
      assert {:error, :removed} =
               Validate.ensure_not_removed(%Announcement{removed_at: DateTime.utc_now()})
    end
  end

  describe "F.Announcements.7 — ensure_ack_required_from/2" do
    test "returns :ok for a non-author when the announcement requires ack" do
      assert :ok =
               Validate.ensure_ack_required_from(
                 %Announcement{requires_ack: true, author_id: 1},
                 %User{id: 2}
               )
    end

    test "returns {:error, :not_required} when the author tries to ack" do
      assert {:error, :not_required} =
               Validate.ensure_ack_required_from(
                 %Announcement{requires_ack: true, author_id: 1},
                 %User{id: 1}
               )
    end

    test "returns {:error, :not_required} when the announcement does not require ack" do
      assert {:error, :not_required} =
               Validate.ensure_ack_required_from(
                 %Announcement{requires_ack: false, author_id: 1},
                 %User{id: 2}
               )
    end
  end

  describe "F.Announcements.9 — receipt_bucket_for/4" do
    test "off_shift takes precedence over every other state" do
      on_shift = %{}
      acked = %{1 => true}
      read = %{1 => true}

      assert Validate.receipt_bucket_for(1, on_shift, acked, read) == :off_shift
    end

    test "on-shift and acknowledged falls into :acknowledged" do
      assert Validate.receipt_bucket_for(1, %{1 => true}, %{1 => true}, %{}) == :acknowledged
    end

    test "on-shift and read-only falls into :read_without_acknowledgement" do
      assert Validate.receipt_bucket_for(1, %{1 => true}, %{}, %{1 => true}) ==
               :read_without_acknowledgement
    end

    test "on-shift with neither ack nor read falls into :unread" do
      assert Validate.receipt_bucket_for(1, %{1 => true}, %{}, %{}) == :unread
    end

    test "ack takes precedence over read for an on-shift member" do
      assert Validate.receipt_bucket_for(1, %{1 => true}, %{1 => true}, %{1 => true}) ==
               :acknowledged
    end
  end

  describe "F.Announcements.9 — empty_receipt_groups/0" do
    test "starts every bucket empty so the receipts panel never crashes on a missing key" do
      assert Validate.empty_receipt_groups() == %{
               acknowledged: [],
               read_without_acknowledgement: [],
               unread: [],
               off_shift: []
             }
    end

    test "every bucket from receipt_buckets/0 is keyed in empty_receipt_groups/0" do
      keys = Validate.empty_receipt_groups() |> Map.keys() |> Enum.sort()
      buckets = Validate.receipt_buckets() |> Enum.sort()

      assert keys == buckets
    end
  end

  describe "Announcement.changeset/2 — pure validations" do
    test "is valid with all required fields" do
      cs =
        Announcement.changeset(%Announcement{}, %{
          "author_id" => 1,
          "channel_id" => 2,
          "title" => "Suite 412 allergy protocol",
          "body" => "Guest in 412 has a severe nut allergy.",
          "published_at" => DateTime.utc_now() |> DateTime.truncate(:second)
        })

      assert cs.valid?
    end

    test "missing required fields produce can't-be-blank errors" do
      cs = Announcement.changeset(%Announcement{}, %{})

      refute cs.valid?
      assert {"can't be blank", _} = cs.errors[:author_id]
      assert {"can't be blank", _} = cs.errors[:channel_id]
      assert {"can't be blank", _} = cs.errors[:title]
      assert {"can't be blank", _} = cs.errors[:body]
      assert {"can't be blank", _} = cs.errors[:published_at]
    end

    test "requires_ack defaults to false when omitted" do
      cs =
        Announcement.changeset(%Announcement{}, %{
          "author_id" => 1,
          "channel_id" => 2,
          "title" => "Heads up",
          "body" => "Just FYI.",
          "published_at" => DateTime.utc_now() |> DateTime.truncate(:second)
        })

      assert cs.valid?
      assert Ecto.Changeset.get_field(cs, :requires_ack) == false
    end
  end

  defp seconds_ago(seconds) do
    DateTime.utc_now() |> DateTime.add(-seconds, :second) |> DateTime.truncate(:second)
  end
end
