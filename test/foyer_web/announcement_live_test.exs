defmodule FoyerWeb.AnnouncementLiveTest do
  @moduledoc """
  Isolated LiveView tests for `FoyerWeb.AnnouncementLive`, mounted via
  `Phoenix.LiveViewTest.live_isolated/3` and `FoyerWeb.IsolatedHelpers`.

  These tests run without the production router, plugs, or database — every
  dependency is a Mox-backed scenario module under `test/support/scenarios/`,
  the on_mount hook is the synthetic `FoyerWeb.IsolatedHelpers.OnMount`, and
  the routing context is provided by `FoyerWeb.IsolatedRouter`. The route
  smoke layer (see `test/foyer_web/smoke_test.exs`) covers the real
  wiring; this file covers UI-state branches per `docs/TESTING_GUIDE.md`.

  Each test pins to a single `F.Announcements.<N>` clause in its name so
  spec drift fails loudly.
  """
  use FoyerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Mox

  alias Foyer.HouseScenarios.Fixtures
  alias FoyerWeb.IsolatedHelpers

  @endpoint FoyerWeb.Endpoint

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    # Channels port is consumed by `apply_new/1`, `apply_edit/2`, and
    # `can_pin?/2`; bind a tiny default so isolated tests that don't care
    # about audience selection still have a non-empty channel list.
    stub_with(Foyer.ChannelsMock, Foyer.ChannelsScenarios.SingleChannel)

    :ok
  end

  describe "F.Announcements.2 — staff compose gate" do
    setup do
      stub_with(Foyer.HouseMock, Foyer.HouseScenarios.Empty)
      :ok
    end

    test "staff visiting /announcements/new is redirected and no form is rendered", %{conn: conn} do
      scope = IsolatedHelpers.scope_for(Fixtures.staff(), true)

      {conn, opts} =
        IsolatedHelpers.prepare_isolated(conn, FoyerWeb.AnnouncementLive, scope, action: :new)

      # apply_new/1 calls push_navigate on a non-manager — live_isolated
      # surfaces that as {:error, {:live_redirect, ...}}. No form mount, so
      # `#announcement-new-form` is unreachable for staff.
      assert {:error, {:live_redirect, %{to: "/house"}}} =
               live_isolated(conn, FoyerWeb.AnnouncementLive, opts)
    end

    test "manager visiting /announcements/new sees the compose form", %{conn: conn} do
      scope = IsolatedHelpers.scope_for(Fixtures.manager(), true)

      {conn, opts} =
        IsolatedHelpers.prepare_isolated(conn, FoyerWeb.AnnouncementLive, scope, action: :new)

      {:ok, view, _html} = live_isolated(conn, FoyerWeb.AnnouncementLive, opts)
      Mox.allow(Foyer.HouseMock, self(), view.pid)
      Mox.allow(Foyer.ChannelsMock, self(), view.pid)

      assert has_element?(view, "#announcement-new-form")
      refute has_element?(view, "#compose-gated")
    end
  end

  describe "F.Announcements.3 — edit affordance within grace window" do
    test "author within grace sees the Edit link on the detail page", %{conn: conn} do
      stub_with(Foyer.HouseMock, Foyer.HouseScenarios.WithReceipts)

      scope = IsolatedHelpers.scope_for(Fixtures.manager(), true)

      {conn, opts} =
        IsolatedHelpers.prepare_isolated(conn, FoyerWeb.AnnouncementLive, scope,
          action: :show,
          params: %{"id" => "100"}
        )

      {:ok, view, _html} = live_isolated(conn, FoyerWeb.AnnouncementLive, opts)
      Mox.allow(Foyer.HouseMock, self(), view.pid)
      Mox.allow(Foyer.ChannelsMock, self(), view.pid)

      # The author (the manager from Fixtures) is within grace
      # (`within_grace_window?/1` returns true on this scenario), so the
      # Edit link is rendered.
      assert has_element?(view, "#announcement-edit-link")
    end

    test "author outside grace does not see the Remove button", %{conn: conn} do
      # Bind to Empty for the baseline, then override the four callbacks the
      # show path actually hits with one-off `expect/3`s — this asserts the
      # specific UI change for the outside-grace branch (per
      # docs/TESTING_GUIDE.md "When to keep expect/3 instead").
      stub_with(Foyer.HouseMock, Foyer.HouseScenarios.Empty)

      # Each callback runs twice — once during the static render in the test
      # process, once during the channel mount in the LiveView process — so
      # the expected counts are 2.
      Mox.expect(Foyer.HouseMock, :get_announcement!, 2, fn _id, _user ->
        Fixtures.announcement()
      end)

      Mox.expect(Foyer.HouseMock, :mark_read, 2, fn _a, _u -> {:ok, :marked} end)
      Mox.expect(Foyer.HouseMock, :within_grace_window?, 2, fn _a -> false end)

      Mox.expect(Foyer.HouseMock, :receipts_for, 2, fn _a, _u ->
        {:ok, Fixtures.empty_receipts()}
      end)

      scope = IsolatedHelpers.scope_for(Fixtures.manager(), true)

      {conn, opts} =
        IsolatedHelpers.prepare_isolated(conn, FoyerWeb.AnnouncementLive, scope,
          action: :show,
          params: %{"id" => "100"}
        )

      {:ok, view, _html} = live_isolated(conn, FoyerWeb.AnnouncementLive, opts)
      Mox.allow(Foyer.HouseMock, self(), view.pid)
      Mox.allow(Foyer.ChannelsMock, self(), view.pid)

      # Edit link is rendered for the author at any time (it's gated only by
      # author identity, not grace), but the Remove button — which IS
      # grace-gated by `within_grace_window?/1` returning false — is absent.
      assert has_element?(view, "#announcement-edit-link")
      refute has_element?(view, "#announcement-remove-btn")
    end
  end

  describe "F.Announcements.5 — pin/unpin button visibility" do
    test "manager who manages the channel sees the unpin button on a pinned announcement",
         %{conn: conn} do
      stub_with(Foyer.HouseMock, Foyer.HouseScenarios.WithReceipts)

      scope = IsolatedHelpers.scope_for(Fixtures.manager(), true)

      {conn, opts} =
        IsolatedHelpers.prepare_isolated(conn, FoyerWeb.AnnouncementLive, scope,
          action: :show,
          params: %{"id" => "100"}
        )

      {:ok, view, _html} = live_isolated(conn, FoyerWeb.AnnouncementLive, opts)
      Mox.allow(Foyer.HouseMock, self(), view.pid)
      Mox.allow(Foyer.ChannelsMock, self(), view.pid)

      # The canonical fixture announcement is pinned — managers in the
      # channel see the unpin affordance.
      assert has_element?(view, "#announcement-unpin-btn")
      refute has_element?(view, "#announcement-pin-btn")
    end

    test "staff (non-manager) does not see pin or unpin buttons", %{conn: conn} do
      stub_with(Foyer.HouseMock, Foyer.HouseScenarios.WithUnacked)

      scope = IsolatedHelpers.scope_for(Fixtures.staff(), true)

      {conn, opts} =
        IsolatedHelpers.prepare_isolated(conn, FoyerWeb.AnnouncementLive, scope,
          action: :show,
          params: %{"id" => "100"}
        )

      {:ok, view, _html} = live_isolated(conn, FoyerWeb.AnnouncementLive, opts)
      Mox.allow(Foyer.HouseMock, self(), view.pid)
      Mox.allow(Foyer.ChannelsMock, self(), view.pid)

      refute has_element?(view, "#announcement-pin-btn")
      refute has_element?(view, "#announcement-unpin-btn")
    end
  end

  describe "F.Announcements.7 — author is excluded from required-ack rendering" do
    test "author does not see the acknowledge CTA on their own ack-required post",
         %{conn: conn} do
      stub_with(Foyer.HouseMock, Foyer.HouseScenarios.WithReceipts)

      scope = IsolatedHelpers.scope_for(Fixtures.manager(), true)

      {conn, opts} =
        IsolatedHelpers.prepare_isolated(conn, FoyerWeb.AnnouncementLive, scope,
          action: :show,
          params: %{"id" => "100"}
        )

      {:ok, view, _html} = live_isolated(conn, FoyerWeb.AnnouncementLive, opts)
      Mox.allow(Foyer.HouseMock, self(), view.pid)
      Mox.allow(Foyer.ChannelsMock, self(), view.pid)

      # Author (Fixtures.manager/0) authored the announcement — the ack CTA
      # must never render for them, even though the announcement requires
      # acknowledgement.
      refute has_element?(view, "#acknowledge-btn")
    end

    test "non-author sees the acknowledge CTA on an ack-required post they haven't acked",
         %{conn: conn} do
      stub_with(Foyer.HouseMock, Foyer.HouseScenarios.WithUnacked)

      scope = IsolatedHelpers.scope_for(Fixtures.staff(), true)

      {conn, opts} =
        IsolatedHelpers.prepare_isolated(conn, FoyerWeb.AnnouncementLive, scope,
          action: :show,
          params: %{"id" => "100"}
        )

      {:ok, view, _html} = live_isolated(conn, FoyerWeb.AnnouncementLive, opts)
      Mox.allow(Foyer.HouseMock, self(), view.pid)
      Mox.allow(Foyer.ChannelsMock, self(), view.pid)

      # Staff (non-author) who has not acked yet — CTA renders.
      assert has_element?(view, "#acknowledge-btn")
    end
  end

  describe "F.Announcements.9 — receipt groups render the four buckets" do
    test "the detail page renders all four bucket sections with their labels and counts",
         %{conn: conn} do
      # WithReceipts: one acknowledged, one read_without_acknowledgement, zero
      # unread, zero off_shift. The four sections must all render — even the
      # empty ones, with "None" inside.
      stub_with(Foyer.HouseMock, Foyer.HouseScenarios.WithReceipts)

      scope = IsolatedHelpers.scope_for(Fixtures.manager(), true)

      {conn, opts} =
        IsolatedHelpers.prepare_isolated(conn, FoyerWeb.AnnouncementLive, scope,
          action: :show,
          params: %{"id" => "100"}
        )

      {:ok, view, html} = live_isolated(conn, FoyerWeb.AnnouncementLive, opts)
      Mox.allow(Foyer.HouseMock, self(), view.pid)
      Mox.allow(Foyer.ChannelsMock, self(), view.pid)

      assert has_element?(view, "#receipts-acknowledged")
      assert has_element?(view, "#receipts-read")
      assert has_element?(view, "#receipts-unread")
      assert has_element?(view, "#receipts-off-shift")
      assert has_element?(view, "#ack-badge-#{Fixtures.other_staff().id}", "AB")

      assert html =~ "Acknowledged · 1"
      assert html =~ "Read without acknowledgement · 1"
      assert html =~ "Unread · 0"
      assert html =~ "Off shift · 0"
      refute html =~ ">?? ✓"
      refute html =~ "confirmed /"
    end

    test "staff do not see manager read receipt UI", %{conn: conn} do
      stub_with(Foyer.HouseMock, Foyer.HouseScenarios.WithUnacked)

      scope = IsolatedHelpers.scope_for(Fixtures.staff(), true)

      {conn, opts} =
        IsolatedHelpers.prepare_isolated(conn, FoyerWeb.AnnouncementLive, scope,
          action: :show,
          params: %{"id" => "100"}
        )

      {:ok, view, html} = live_isolated(conn, FoyerWeb.AnnouncementLive, opts)
      Mox.allow(Foyer.HouseMock, self(), view.pid)
      Mox.allow(Foyer.ChannelsMock, self(), view.pid)

      refute has_element?(view, "#read-receipts-col")
      refute has_element?(view, "#announcement-receipts")
      refute html =~ "Read receipts"
    end
  end
end
