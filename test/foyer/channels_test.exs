defmodule Foyer.ChannelsTest do
  # async: false — Ecto sandbox, shared state. Required for integration tests.
  use Foyer.DataCase, async: false

  @moduletag :integration

  alias Foyer.Accounts.User
  alias Foyer.Channels
  alias Foyer.Channels.Channel
  alias Foyer.Channels.Membership

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp insert_user!(name) do
    Repo.insert!(%User{
      name: name,
      initials: String.slice(name, 0, 2) |> String.upcase(),
      role: :staff,
      department: "Housekeeping",
      title: "Housekeeper"
    })
  end

  defp insert_channel!(slug, name \\ nil, kind \\ :department) do
    name = name || String.capitalize(slug)

    Repo.insert!(%Channel{
      slug: slug,
      name: name,
      kind: kind
    })
  end

  defp insert_membership!(user, channel) do
    Repo.insert!(%Membership{user_id: user.id, channel_id: channel.id})
  end

  # ---------------------------------------------------------------------------
  # F.Channels.1 — slug uniqueness (integration: DB unique index)
  # ---------------------------------------------------------------------------

  describe "F.Channels.1 — slug uniqueness" do
    test "inserting a duplicate slug returns a changeset error on :slug" do
      _first = insert_channel!("housekeeping-floor-4", "Housekeeping · Floor 4")

      result =
        %Channel{}
        |> Channel.changeset(%{
          slug: "housekeeping-floor-4",
          name: "Duplicate",
          kind: :department
        })
        |> Repo.insert()

      assert {:error, changeset} = result
      assert {"has already been taken", _} = changeset.errors[:slug]
    end
  end

  # ---------------------------------------------------------------------------
  # F.Channels.4 — membership uniqueness (integration: DB unique index)
  # ---------------------------------------------------------------------------

  describe "F.Channels.4 — membership uniqueness" do
    test "inserting a duplicate (user_id, channel_id) pair returns a changeset error" do
      user = insert_user!("Member User")
      channel = insert_channel!("dup-channel")
      insert_membership!(user, channel)

      result =
        %Membership{}
        |> Membership.changeset(%{user_id: user.id, channel_id: channel.id})
        |> Repo.insert()

      assert {:error, changeset} = result
      assert changeset.errors[:user_id] != nil or changeset.errors[:channel_id] != nil
    end
  end

  # ---------------------------------------------------------------------------
  # F.Channels.6 — list_for_user/1 returns only caller's channels, ordered
  # ---------------------------------------------------------------------------

  describe "F.Channels.6 — list_for_user/1 returns only caller's channels" do
    test "returns the user's channels alphabetically, excludes non-member channels" do
      user = insert_user!("User Six")
      other_user = insert_user!("Other User")

      hk_floor_4 = insert_channel!("hk-floor-4", "Housekeeping · Floor 4")
      all_hk = insert_channel!("all-hk", "All Housekeeping")
      leadership = insert_channel!("leadership-test", "Leadership")

      insert_membership!(user, hk_floor_4)
      insert_membership!(user, all_hk)
      # other_user in leadership only
      insert_membership!(other_user, leadership)

      result = Channels.list_for_user(user)
      names = Enum.map(result, & &1.name)

      assert "All Housekeeping" in names
      assert "Housekeeping · Floor 4" in names
      refute "Leadership" in names
      # Verify alphabetical order
      assert names == Enum.sort(names)
    end
  end

  # ---------------------------------------------------------------------------
  # F.Channels.7 — list_for_user/1 returns empty list for memberless user
  # ---------------------------------------------------------------------------

  describe "F.Channels.7 — list_for_user/1 empty for user with no memberships" do
    test "returns empty list" do
      user = insert_user!("No Channels User")
      assert [] == Channels.list_for_user(user)
    end
  end

  # ---------------------------------------------------------------------------
  # F.Channels.8 — get!/1 raises for unknown id
  # ---------------------------------------------------------------------------

  describe "F.Channels.8 — get!/1 raises for unknown id" do
    test "raises Ecto.NoResultsError for id 99999" do
      assert_raise Ecto.NoResultsError, fn ->
        Channels.get!(99_999)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # F.Channels.9 — list_all_with_member_counts/0
  # ---------------------------------------------------------------------------

  describe "F.Channels.9 — list_all_with_member_counts/0" do
    test "returns all channels with accurate counts in alphabetical order" do
      u1 = insert_user!("Alpha")
      u2 = insert_user!("Beta")
      u3 = insert_user!("Gamma")
      u4 = insert_user!("Delta")

      hk = insert_channel!("hk-counts", "Housekeeping Counts")
      lead = insert_channel!("lead-counts", "Leadership Counts")
      empty = insert_channel!("empty-counts", "Empty Counts")

      for u <- [u1, u2, u3, u4], do: insert_membership!(u, hk)
      for u <- [u1, u2, u3], do: insert_membership!(u, lead)

      result = Channels.list_all_with_member_counts()

      assert is_list(result)
      assert Enum.all?(result, fn {c, count} -> is_struct(c, Channel) and is_integer(count) end)

      # Find our test channels
      {_, hk_count} = Enum.find(result, fn {c, _} -> c.id == hk.id end)
      {_, lead_count} = Enum.find(result, fn {c, _} -> c.id == lead.id end)
      {_, empty_count} = Enum.find(result, fn {c, _} -> c.id == empty.id end)

      assert hk_count == 4
      assert lead_count == 3
      assert empty_count == 0

      # Verify alphabetical order
      names = Enum.map(result, fn {c, _} -> c.name end)
      assert names == Enum.sort(names)
    end
  end

  # ---------------------------------------------------------------------------
  # F.Channels.10 — member?/2
  # ---------------------------------------------------------------------------

  describe "F.Channels.10 — member?/2" do
    test "returns true for a member and false for a non-member" do
      user = insert_user!("Member Check")
      all_hk = insert_channel!("all-hk-member", "All Housekeeping Member")
      leadership = insert_channel!("leadership-member", "Leadership Member")

      insert_membership!(user, all_hk)

      assert Channels.member?(user, all_hk) == true
      assert Channels.member?(user, leadership) == false
    end
  end

  # ---------------------------------------------------------------------------
  # F.Channels.11 — member_count/1
  # ---------------------------------------------------------------------------

  describe "F.Channels.11 — member_count/1" do
    test "returns exact count for a channel" do
      u1 = insert_user!("Count User 1")
      u2 = insert_user!("Count User 2")
      channel = insert_channel!("fb-count", "F&B Count")

      insert_membership!(u1, channel)
      insert_membership!(u2, channel)

      assert Channels.member_count(channel) == 2
    end

    test "returns 0 for a channel with no members" do
      channel = insert_channel!("empty-fb", "Empty F&B")
      assert Channels.member_count(channel) == 0
    end
  end

  # ---------------------------------------------------------------------------
  # F.Channels.19 — manager role alone does not grant channel access
  # ---------------------------------------------------------------------------

  describe "F.Channels.19 — manager role alone does not grant membership" do
    test "a manager not added to Engineering does not see it in list_for_user" do
      manager =
        Repo.insert!(%User{
          name: "Test Manager",
          initials: "TM",
          role: :manager,
          department: "Housekeeping",
          title: "Dir. of Housekeeping"
        })

      engineering = insert_channel!("engineering-test", "Engineering Test")
      # manager is NOT inserted into engineering

      result = Channels.list_for_user(manager)
      refute Enum.any?(result, fn c -> c.id == engineering.id end)
    end

    test "member?/2 returns false for a manager not in a channel" do
      manager =
        Repo.insert!(%User{
          name: "Manager Not In Eng",
          initials: "MN",
          role: :manager,
          department: "Front Office",
          title: "Night Manager"
        })

      engineering = insert_channel!("eng-m-test", "Engineering M Test")

      assert Channels.member?(manager, engineering) == false
    end
  end

  # ---------------------------------------------------------------------------
  # F.Channels.20 — list_all_with_member_counts/0 issues at most 2 queries
  # ---------------------------------------------------------------------------

  describe "F.Channels.20 — list_all_with_member_counts/0 is N+1-free" do
    test "F.Channels.20 — list_all_with_member_counts/0 issues at most 2 queries" do
      # Create a few channels to make the assertion meaningful
      for i <- 1..5 do
        insert_channel!("n1-channel-#{i}", "N+1 Channel #{i}")
      end

      ref = :counters.new(1, [])

      handler = fn _event, _measurements, _metadata, _config ->
        :counters.add(ref, 1, 1)
      end

      :telemetry.attach("query-counter-channels", [:foyer, :repo, :query], handler, nil)
      on_exit(fn -> :telemetry.detach("query-counter-channels") end)

      _result = Channels.list_all_with_member_counts()

      assert :counters.get(ref, 1) <= 2
    end
  end
end
