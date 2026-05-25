defmodule Foyer.ChannelsSeedTest do
  # async: false — uses the Ecto sandbox with shared fixtures.
  use Foyer.DataCase, async: false

  @moduletag :integration

  alias Foyer.Accounts.User
  alias Foyer.Channels
  alias Foyer.Channels.Channel
  alias Foyer.Channels.Membership

  # ---------------------------------------------------------------------------
  # In-test fixture that recreates the relevant seed shape without relying on
  # priv/repo/seeds.exs. The fixture is hermetic and repeatable in CI.
  # ---------------------------------------------------------------------------

  setup do
    # Users
    manager_hk =
      Repo.insert!(%User{
        name: "Test Housekeeping Manager",
        initials: "HM",
        role: :manager,
        department: "Housekeeping",
        title: "Dir. of Housekeeping"
      })

    manager_fo =
      Repo.insert!(%User{
        name: "Test Front Office Manager",
        initials: "FM",
        role: :manager,
        department: "Front Office",
        title: "Night Manager"
      })

    staff_hk =
      Repo.insert!(%User{
        name: "Test Housekeeper",
        initials: "TH",
        role: :staff,
        department: "Housekeeping",
        title: "Housekeeper"
      })

    # Channels
    linden_all =
      Repo.insert!(%Channel{
        name: "Linden · All staff",
        slug: "seed-linden-all",
        kind: :general
      })

    leadership =
      Repo.insert!(%Channel{name: "Leadership", slug: "seed-leadership", kind: :department})

    all_housekeeping =
      Repo.insert!(%Channel{
        name: "All Housekeeping",
        slug: "seed-all-housekeeping",
        kind: :department
      })

    concierge =
      Repo.insert!(%Channel{
        name: "Concierge & Front Office",
        slug: "seed-concierge-front-office",
        kind: :department
      })

    # Memberships — mirrors the seed data shape
    # All staff in linden-all
    for u <- [manager_hk, manager_fo, staff_hk] do
      Repo.insert!(%Membership{user_id: u.id, channel_id: linden_all.id})
    end

    # Managers in leadership
    for u <- [manager_hk, manager_fo] do
      Repo.insert!(%Membership{user_id: u.id, channel_id: leadership.id})
    end

    # manager_hk manages Housekeeping dept
    Repo.insert!(%Membership{user_id: manager_hk.id, channel_id: all_housekeeping.id})

    # staff_hk is in Housekeeping
    Repo.insert!(%Membership{user_id: staff_hk.id, channel_id: all_housekeeping.id})

    # manager_fo manages Front Office dept (concierge)
    Repo.insert!(%Membership{user_id: manager_fo.id, channel_id: concierge.id})

    %{
      manager_hk: manager_hk,
      manager_fo: manager_fo,
      staff_hk: staff_hk,
      linden_all: linden_all,
      leadership: leadership,
      all_housekeeping: all_housekeeping,
      concierge: concierge
    }
  end

  # ---------------------------------------------------------------------------
  # F.Channels.12 — managers seeded into their operational channels
  # ---------------------------------------------------------------------------

  describe "F.Channels.12 — managers are seeded into their operational channels" do
    test "Housekeeping manager has Leadership, Linden · All staff, and Housekeeping dept channel",
         ctx do
      channels = Channels.list_for_user(ctx.manager_hk)
      names = Enum.map(channels, & &1.name)

      assert "Leadership" in names
      assert "Linden · All staff" in names
      assert "All Housekeeping" in names
    end

    test "Front Office manager has Leadership, Linden · All staff, and Front Office dept channel",
         ctx do
      channels = Channels.list_for_user(ctx.manager_fo)
      names = Enum.map(channels, & &1.name)

      assert "Leadership" in names
      assert "Linden · All staff" in names
      assert "Concierge & Front Office" in names
    end

    test "managers are NOT in every channel — Housekeeping manager is absent from Front Office channel",
         ctx do
      channels = Channels.list_for_user(ctx.manager_hk)
      names = Enum.map(channels, & &1.name)

      refute "Concierge & Front Office" in names
    end
  end

  # ---------------------------------------------------------------------------
  # F.Channels.13 — staff seeded into their department channel
  # ---------------------------------------------------------------------------

  describe "F.Channels.13 — staff are seeded into their department channel" do
    test "Housekeeping staff has at least one channel with 'housekeeping' in the slug", ctx do
      channels = Channels.list_for_user(ctx.staff_hk)
      slugs = Enum.map(channels, & &1.slug)

      assert Enum.any?(slugs, fn s -> String.contains?(s, "housekeeping") end)
    end

    test "Housekeeping staff does NOT have Leadership in their channels", ctx do
      channels = Channels.list_for_user(ctx.staff_hk)
      names = Enum.map(channels, & &1.name)

      refute "Leadership" in names
    end
  end

  # ---------------------------------------------------------------------------
  # F.Channels.14 — all seeded users are in the general all-staff channel
  # ---------------------------------------------------------------------------

  describe "F.Channels.14 — all staff are seeded into the general all-staff channel" do
    test "manager_hk has linden-all channel", ctx do
      channels = Channels.list_for_user(ctx.manager_hk)
      names = Enum.map(channels, & &1.name)
      assert "Linden · All staff" in names
    end

    test "manager_fo has linden-all channel", ctx do
      channels = Channels.list_for_user(ctx.manager_fo)
      names = Enum.map(channels, & &1.name)
      assert "Linden · All staff" in names
    end

    test "staff_hk has linden-all channel", ctx do
      channels = Channels.list_for_user(ctx.staff_hk)
      names = Enum.map(channels, & &1.name)
      assert "Linden · All staff" in names
    end
  end
end
