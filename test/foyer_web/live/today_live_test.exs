defmodule FoyerWeb.TodayLiveTest do
  use FoyerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Mox

  alias FoyerWeb.IsolatedHelpers

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    stub(Foyer.ShiftsMock, :start_shift, fn user ->
      {:ok, %Foyer.Shifts.Shift{user_id: user.id, started_at: DateTime.utc_now(:second)}}
    end)

    stub(Foyer.ShiftsMock, :end_shift, fn shift, attrs ->
      ended_at = Map.get(attrs, "ended_at", DateTime.utc_now(:second))
      {:ok, %{shift | ended_at: ended_at}}
    end)

    stub(Foyer.ChannelsMock, :list_for_user, fn _user -> [] end)
    :ok
  end

  # ──────────────────────────────────────────────────────────
  # F.Today.1 — Off-shift paused state banner
  # ──────────────────────────────────────────────────────────

  describe "F.Today.1 — off-shift paused state banner" do
    test "renders off-shift tag, copy, Start shift button, and waiting line", %{conn: conn} do
      {:ok, view, _html} =
        mount_today(conn, Today.Scenarios.OffShift, on_shift?: false)

      html = render(view)
      assert html =~ "Off shift · notifications paused"
      assert html =~ "off the clock"
      assert html =~ "Rest is part of the work"
      assert html =~ "You won&#39;t receive notifications until you start your next shift."
      assert has_element?(view, "#start-shift-btn", "Start shift")
      assert html =~ "While you were off"
      assert html =~ "0 waiting"

      # Needs-ack section absent when off shift
      refute has_element?(view, "#needs-ack")
    end
  end

  # ──────────────────────────────────────────────────────────
  # F.Today.1 + F.Today.16 — Off-shift with waiting counts
  # ──────────────────────────────────────────────────────────

  describe "F.Today.16 — waiting counts reflect work since last shift" do
    test "shows total waiting count and breakdown for announcements, messages, recognitions", %{
      conn: conn
    } do
      {:ok, view, _html} =
        mount_today(conn, Today.Scenarios.OffShiftWithWaiting, on_shift?: false)

      html = render(view)
      # Total = 3 + 2 + 1 = 6
      assert html =~ "6 waiting"
      assert html =~ "3 announcements"
      assert html =~ "2 messages"
      assert html =~ "1 recognitions"
    end
  end

  # ──────────────────────────────────────────────────────────
  # F.Today.3 — Start shift transition
  # ──────────────────────────────────────────────────────────

  describe "F.Today.3 — start shift transition" do
    test "clicking Start shift fires start_shift event and redirects to /today", %{conn: conn} do
      {:ok, view, _html} =
        mount_today(conn, Today.Scenarios.OffShift, on_shift?: false)

      assert has_element?(view, "#start-shift-btn")

      view |> element("#start-shift-btn") |> render_click()
      assert_redirected(view, ~p"/today")
    end
  end

  # ──────────────────────────────────────────────────────────
  # F.Today.4 — On-shift staff: priority content order
  # ──────────────────────────────────────────────────────────

  describe "F.Today.4 — on-shift staff content order" do
    test "handoff card precedes needs-ack section which precedes recognition section", %{
      conn: conn
    } do
      {:ok, _view, html} = mount_today(conn, Today.Scenarios.OnShiftStaff)

      handoff_pos = html |> :binary.match("handoff-card") |> elem(0)
      needs_ack_pos = html |> :binary.match("needs-ack") |> elem(0)
      recognition_pos = html |> :binary.match("recent-recognition") |> elem(0)

      assert handoff_pos < needs_ack_pos
      assert needs_ack_pos < recognition_pos
    end
  end

  # ──────────────────────────────────────────────────────────
  # F.Today.6 / F.Today.7 — Needs-ack: empty means section absent
  # ──────────────────────────────────────────────────────────

  describe "F.Today.7 — all acknowledged: needs-ack section absent" do
    test "needs-ack section absent when all announcements are acknowledged", %{conn: conn} do
      {:ok, view, _html} = mount_today(conn, Today.Scenarios.OnShiftAllAcked)

      refute has_element?(view, "#needs-ack")
    end
  end

  # ──────────────────────────────────────────────────────────
  # F.Today.8 — Handoff card content
  # ──────────────────────────────────────────────────────────

  describe "F.Today.8 — handoff card content" do
    test "handoff card shows sender name, ended-at time, and handoff note", %{conn: conn} do
      {:ok, view, _html} = mount_today(conn, Today.Scenarios.OnShiftStaff)

      assert has_element?(view, "#handoff-card")
      html = render(view)
      assert html =~ "Rafael Mendes"
      assert html =~ "Quiet night, 206 settled."
    end
  end

  # ──────────────────────────────────────────────────────────
  # F.Today.9 — No handoff card when no relevant handoff
  # ──────────────────────────────────────────────────────────

  describe "F.Today.9 — no handoff card when no relevant handoff" do
    test "handoff-card element absent when handoff is nil", %{conn: conn} do
      {:ok, view, _html} = mount_today(conn, Today.Scenarios.OnShiftNoHandoff)

      refute has_element?(view, "#handoff-card")
    end
  end

  # ──────────────────────────────────────────────────────────
  # F.Today.10 / F.Today.11 — End shift form
  # ──────────────────────────────────────────────────────────

  describe "F.Today.10 / F.Today.11 — end-shift form" do
    test "end-shift form has textarea, channel picker, and skip link", %{conn: conn} do
      {:ok, view, _html} =
        mount_today(conn, Today.Scenarios.OnShiftStaff,
          action: :end_shift,
          path: "/today/end-shift"
        )

      assert has_element?(view, "#end-shift-form")
      assert has_element?(view, "#handoff-channel-select")
      assert has_element?(view, "#skip-clock-out")
    end

    test "F.Today.12 — skip clock out ends shift and redirects", %{conn: conn} do
      {:ok, view, _html} =
        mount_today(conn, Today.Scenarios.OnShiftStaff,
          action: :end_shift,
          path: "/today/end-shift"
        )

      view |> element("#skip-clock-out") |> render_click()
      assert_redirected(view, ~p"/today?state=shift_complete")
    end
  end

  # ──────────────────────────────────────────────────────────
  # F.Today.5 — Needs-ack items link to announcement detail
  # ──────────────────────────────────────────────────────────

  describe "F.Today.5 — needs-ack item links to announcement detail" do
    test "needs-ack link navigates to /announcements/:id", %{conn: conn} do
      {:ok, view, html} = mount_today(conn, Today.Scenarios.OnShiftStaff)

      # The scenario has announcement id 10
      assert has_element?(view, "#needs-ack-10")
      assert html =~ ~p"/announcements/10"
    end
  end

  # ──────────────────────────────────────────────────────────
  # F.Today.13 — On-shift manager: New announcement CTA
  # ──────────────────────────────────────────────────────────

  describe "F.Today.13 — manager sees New announcement CTA" do
    test "compose-cta present for on-shift manager", %{conn: conn} do
      {:ok, view, _html} =
        mount_today(conn, Today.Scenarios.OnShiftManager, role: :manager)

      assert has_element?(view, "#compose-cta")
    end
  end

  # ──────────────────────────────────────────────────────────
  # F.Today.14 — On-shift manager: live posts section
  # ──────────────────────────────────────────────────────────

  describe "F.Today.14 — manager live posts section" do
    test "manager-live-posts section present when manager has published announcements", %{
      conn: conn
    } do
      {:ok, view, _html} =
        mount_today(conn, Today.Scenarios.OnShiftManager, role: :manager)

      assert has_element?(view, "#manager-live-posts")
      # Scenario has 2 live posts (IDs 11 and 12)
      assert has_element?(view, "#live-post-11")
      assert has_element?(view, "#live-post-12")
    end
  end

  # ──────────────────────────────────────────────────────────
  # F.Today.17 — Mobile-first rendering
  # ──────────────────────────────────────────────────────────

  describe "F.Today.17 — mobile-first rendering" do
    test "rendered HTML has no explicit fixed width exceeding 390px", %{conn: conn} do
      {:ok, _view, html} = mount_today(conn, Today.Scenarios.OnShiftStaff)

      # No inline style with width > 390px
      refute html =~ ~r/width:\s*[4-9]\d\d|width:\s*[1-9]\d{3}/
      # No overflow-x: scroll
      refute html =~ "overflow-x: scroll"
    end
  end

  # ──────────────────────────────────────────────────────────
  # F.Today.18 — Recent recognition cards
  # ──────────────────────────────────────────────────────────

  describe "F.Today.18 — recent recognition cards" do
    test "recognition section shows sender name, body, and values", %{conn: conn} do
      {:ok, view, html} = mount_today(conn, Today.Scenarios.OnShiftStaff)

      assert has_element?(view, "#recent-recognition")
      assert has_element?(view, "#recognition-1")
      assert html =~ "Rafael Mendes"
      assert html =~ "Quietly handled a 02:14 guest issue with grace."
      assert html =~ "care"
      assert html =~ "discretion"
    end
  end

  # ──────────────────────────────────────────────────────────
  # F.Today.19 — No recognition section when none received
  # ──────────────────────────────────────────────────────────

  describe "F.Today.19 — no recognition section when none received" do
    test "recent-recognition section absent when recognitions list is empty", %{conn: conn} do
      {:ok, view, _html} = mount_today(conn, Today.Scenarios.OnShiftAllAcked)

      refute has_element?(view, "#recent-recognition")
    end
  end

  # ──────────────────────────────────────────────────────────
  # Shift-complete variant (just_clocked_out)
  # ──────────────────────────────────────────────────────────

  describe "shift-complete transient state (F.Today.10 / F.Today.12 redirect)" do
    test "renders shift-complete banner when state=shift_complete param is present", %{conn: conn} do
      {:ok, view, _html} =
        mount_today(conn, Today.Scenarios.AfterClockOut,
          on_shift?: false,
          path: "/today?state=shift_complete"
        )

      assert has_element?(view, "#shift-complete-banner")
      html = render(view)
      assert html =~ "Shift complete"
      assert html =~ "Eight hours well held"
      assert html =~ "Notifications will quiet down"
    end

    test "renders normal off-shift banner when state param absent", %{conn: conn} do
      {:ok, view, _html} =
        mount_today(conn, Today.Scenarios.AfterClockOut, on_shift?: false)

      assert has_element?(view, "#off-shift-banner")
      refute has_element?(view, "#shift-complete-banner")
    end
  end

  # ──────────────────────────────────────────────────────────
  # F.Today.21 — Handoff card de-emphasis on re-load (UI-only flag)
  # ──────────────────────────────────────────────────────────

  describe "F.Today.21 — handoff card gets quieter on subsequent load" do
    test "handoff card has opacity class after push_navigate re-renders same session", %{
      conn: conn
    } do
      {:ok, view, _html} = mount_today(conn, Today.Scenarios.OnShiftStaff)

      # First render: handoff card full attention (no opacity class)
      html_first = render(view)
      # First render has full-attention border (not opacity-60 yet)
      refute html_first =~ ~r/id="handoff-card"[^>]*opacity-60/

      # Patch within the same LiveView session to trigger the UI-only seen flag.
      render_patch(view, ~p"/today/end-shift")
      html_second = render_patch(view, ~p"/today")

      assert html_second =~ ~r/id="handoff-card"[^>]*opacity-60/
    end
  end

  defp mount_today(conn, scenario, opts \\ []) do
    stub_with(Foyer.TodayMock, scenario)

    action = Keyword.get(opts, :action, :index)
    path = Keyword.get(opts, :path, "/today")
    role = Keyword.get(opts, :role, :staff)
    on_shift? = Keyword.get(opts, :on_shift?, true)

    scope =
      IsolatedHelpers.build_scope(
        id: if(role == :manager, do: 2, else: 1),
        role: role,
        on_shift?: on_shift?,
        name: if(role == :manager, do: "Test Manager", else: "Test User"),
        initials: if(role == :manager, do: "TM", else: "TU"),
        title: if(role == :manager, do: "Manager", else: "Housekeeper")
      )

    {conn, live_opts} =
      IsolatedHelpers.prepare_isolated(conn, FoyerWeb.TodayLive, scope,
        action: action,
        path: path
      )

    live_isolated(conn, FoyerWeb.TodayLive, live_opts)
  end
end
