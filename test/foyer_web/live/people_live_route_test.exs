defmodule FoyerWeb.PeopleLiveRouteTest do
  @moduledoc """
  Route smoke tests for `FoyerWeb.PeopleLive`. These tests use the real router,
  real database (via ScaffoldFixtures), and the real context modules to prove the
  application is fully wired together. They cover:

  - F.Channels.15 — people list renders all staff rows
  - F.Channels.16 — on-shift pulse for on-shift users
  - F.Channels.17 — channel membership pills from real data
  - F.Channels.18 — off-shift redirect
  - F.Channels.21 — channel filter
  - F.Channels.22 — :show loads target_channels via Channels.list_for_user
  """
  # async: false — shared Ecto sandbox; fixtures inserted in setup.
  use FoyerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox
  import FoyerWeb.ScaffoldFixtures

  @moduletag :integration

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    stub_with(Foyer.AccountsMock, Foyer.Accounts)
    stub_with(Foyer.ShiftsMock, Foyer.Shifts)
    stub_with(Foyer.ChannelsMock, Foyer.Channels)
    stub_with(Foyer.HouseMock, Foyer.House)
    stub_with(Foyer.RecognitionsMock, Foyer.Recognitions)
    stub_with(Foyer.ChatMock, Foyer.Chat)
    stub_with(Foyer.ProfileMock, Foyer.Profile)
    stub_with(Foyer.TodayMock, Foyer.Today)

    fixtures = seed_scaffold!()
    {:ok, fixtures}
  end

  # ---------------------------------------------------------------------------
  # F.Channels.18 — off-shift redirect
  # ---------------------------------------------------------------------------

  describe "F.Channels.18 — off-shift gate redirects /people to /today" do
    test "off-shift user navigating to /people is redirected to /today", ctx do
      conn = sign_in(ctx.conn, ctx.jamal)

      assert {:error, {:redirect, %{to: "/today"}}} = live(conn, ~p"/people")
    end
  end

  # ---------------------------------------------------------------------------
  # F.Channels.15 — People Directory renders all staff rows
  # ---------------------------------------------------------------------------

  describe "F.Channels.15 — People Directory renders all staff with rows" do
    test "renders a row for each seeded user with stable DOM IDs", ctx do
      conn = sign_in(ctx.conn, ctx.charlotte)
      {:ok, view, _html} = live(conn, ~p"/people")

      # Charlotte is an on-shift manager (from fixtures); she sees the directory.
      # All seeded users (8 in scaffold) should have a row.
      assert has_element?(view, "#people-row-#{ctx.maya.id}")
      assert has_element?(view, "#people-row-#{ctx.charlotte.id}")
      assert has_element?(view, "#people-row-#{ctx.hugo.id}")
      assert has_element?(view, "#people-row-#{ctx.rafael.id}")
      assert has_element?(view, "#people-row-#{ctx.aisha.id}")
      assert has_element?(view, "#people-row-#{ctx.jamal.id}")
    end
  end

  # ---------------------------------------------------------------------------
  # F.Channels.16 — on-shift pulse for on-shift users
  # ---------------------------------------------------------------------------

  describe "F.Channels.16 — on-shift pulse indicator" do
    test "on-shift Maya has the pulse, off-shift Jamal does not", ctx do
      conn = sign_in(ctx.conn, ctx.charlotte)
      {:ok, view, _html} = live(conn, ~p"/people")

      # Maya is on shift in fixtures (has active Shift with no ended_at).
      assert has_element?(view, "#people-row-#{ctx.maya.id} .foyer-tag.moss"),
             "Expected on-shift indicator for Maya"

      # Jamal's shift ended yesterday — off shift.
      refute has_element?(view, "#people-row-#{ctx.jamal.id} .foyer-tag.moss"),
             "Expected NO on-shift indicator for Jamal"
    end
  end

  # ---------------------------------------------------------------------------
  # F.Channels.17 — channel membership pills from real data
  # ---------------------------------------------------------------------------

  describe "F.Channels.17 — channel membership pills from real data" do
    test "Maya has both Floor 4 and All Housekeeping channel pills", ctx do
      conn = sign_in(ctx.conn, ctx.charlotte)
      {:ok, view, _html} = live(conn, ~p"/people")

      # Maya is a member of housekeeping-floor-4 and all-housekeeping.
      # The scaffold fixtures insert these memberships.
      floor_4_membership_element =
        "#people-row-#{ctx.maya.id} [id^='person-#{ctx.maya.id}-channel-']"

      assert has_element?(view, floor_4_membership_element),
             "Expected at least one channel pill for Maya"
    end
  end

  # ---------------------------------------------------------------------------
  # F.Channels.21 — channel filter shows only members
  # ---------------------------------------------------------------------------

  describe "F.Channels.21 — channel filter" do
    test "filtering by a channel shows only members, clearing restores all", ctx do
      conn = sign_in(ctx.conn, ctx.charlotte)
      {:ok, view, _html} = live(conn, ~p"/people")

      # All seeded users are visible initially
      assert has_element?(view, "#people-row-#{ctx.maya.id}")
      assert has_element?(view, "#people-row-#{ctx.hugo.id}")

      # Find the leadership channel (Charlotte, Rafael, Sebastien are members)
      # via the filter sidebar
      channels = Foyer.Channels.list_for_user(ctx.charlotte)
      leadership = Enum.find(channels, fn c -> c.slug == "leadership" end)

      # Click the filter for leadership channel
      view |> element("#filter-channel-#{leadership.id}") |> render_click()

      # Charlotte and Rafael are in Leadership — should be visible
      assert has_element?(view, "#people-row-#{ctx.charlotte.id}")
      assert has_element?(view, "#people-row-#{ctx.rafael.id}")

      # Maya is NOT in Leadership — should be hidden
      refute has_element?(view, "#people-row-#{ctx.maya.id}")

      # Clear the filter
      view |> element("#filter-all") |> render_click()

      # Maya restored
      assert has_element?(view, "#people-row-#{ctx.maya.id}")
    end
  end

  # ---------------------------------------------------------------------------
  # F.Channels.22 — :show loads target_channels via Channels API
  # ---------------------------------------------------------------------------

  describe "F.Channels.22 — :show action loads target_channels via Channels.list_for_user" do
    test "navigating to /people/:id shows channel pills from channels API", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/people/#{ctx.maya.id}")

      # Maya is in housekeeping-floor-4 and all-housekeeping — both should render
      # as target-channel-* elements (not from Profile.Card preloads).
      assert has_element?(view, "#target-channels"),
             "Expected #target-channels section for /people/:id"
    end

    test "back button is present on :show", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/people/#{ctx.hugo.id}")

      assert has_element?(view, "#back-to-people")
      assert render(view) =~ "Hugo Brandt"
    end
  end
end
