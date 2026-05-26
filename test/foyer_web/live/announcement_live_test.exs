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

  Covers:
    F.Announcements.1 — managers publish to their own channels (compose submit)
    F.Announcements.2 — staff cannot compose announcements
    F.Announcements.3 — author may edit within the 5-minute grace window
    F.Announcements.4 — edit/remove rejected after grace or by non-authors
    F.Announcements.5 — managers pin/unpin announcements in their channel
    F.Announcements.7 — authors are excluded from the required-ack set
    F.Announcements.8 — acknowledge is idempotent (and rejected for author)
    F.Announcements.9 — receipts bucket every channel member exactly once
  """
  use ExUnit.Case, async: true

  @endpoint FoyerWeb.Endpoint

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Mox

  alias Foyer.House.Announcement
  alias Foyer.House.AnnouncementAck
  alias Foyer.HouseScenarios.Fixtures
  alias FoyerWeb.IsolatedHelpers
  alias Phoenix.LiveView.Utils

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    # Channels port is consumed by `apply_new/1`, `apply_edit/2`, and
    # `can_pin?/2`; bind a tiny default so isolated tests that don't care
    # about audience selection still have a non-empty channel list.
    stub_with(Foyer.ChannelsMock, Foyer.ChannelsScenarios.SingleChannel)

    {:ok, conn: build_conn()}
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
    test "author within grace sees Edit and Remove buttons on the detail page", %{conn: conn} do
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

      assert has_element?(view, "#desktop-topbar")
      assert has_element?(view, "#announcement-edit-link.foyer-btn:not(.ghost)", "Edit")
      assert has_element?(view, "#announcement-remove-btn:not([disabled])", "Remove")

      html = render(view)
      body_pos = html |> :binary.match("Guest in 412 has severe tree-nut allergy.") |> elem(0)
      unpin_pos = html |> :binary.match("announcement-unpin-btn") |> elem(0)
      edit_pos = html |> :binary.match("announcement-edit-link") |> elem(0)
      remove_pos = html |> :binary.match("announcement-remove-btn") |> elem(0)

      assert body_pos < unpin_pos
      assert unpin_pos < edit_pos
      assert edit_pos < remove_pos
    end

    test "author outside grace sees disabled Edit and Remove buttons with tooltip copy",
         %{conn: conn} do
      # Bind to Empty for the baseline, then override the four callbacks the
      # show path actually hits with one-off `expect/3`s — this asserts the
      # specific UI change for the outside-grace branch (per
      # docs/TESTING_GUIDE.md "When to keep expect/3 instead").
      stub_with(Foyer.HouseMock, Foyer.HouseScenarios.Empty)

      # Each callback runs twice — once during the static render in the test
      # process, once during the channel mount in the LiveView process — so
      # the expected counts are 2.
      Mox.expect(Foyer.HouseMock, :get_announcement, 2, fn _id, _user ->
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

      tooltip = "Editing and removal are only available for 5 minutes after publishing."

      assert has_element?(view, "[title='#{tooltip}'] #announcement-edit-link[disabled]", "Edit")

      assert has_element?(
               view,
               "[title='#{tooltip}'] #announcement-remove-btn[disabled]",
               "Remove"
             )
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

  describe "F.Announcements.1 — compose submit" do
    test "manager submitting a valid compose form is redirected to the announcement show page",
         %{conn: conn} do
      stub_with(Foyer.HouseMock, Foyer.HouseScenarios.WithReceipts)

      scope = IsolatedHelpers.scope_for(Fixtures.manager(), true)

      {conn, opts} =
        IsolatedHelpers.prepare_isolated(conn, FoyerWeb.AnnouncementLive, scope, action: :new)

      {:ok, view, _html} = live_isolated(conn, FoyerWeb.AnnouncementLive, opts)
      Mox.allow(Foyer.HouseMock, self(), view.pid)
      Mox.allow(Foyer.ChannelsMock, self(), view.pid)

      # Drive preview_change first so the live preview path is exercised
      # before the submit, then assert the submit triggers a push_navigate
      # to the detail page via the {:ok, announcement} branch of create_announcement.
      view
      |> form("#announcement-new-form",
        announcement: %{
          "title" => "Roof access",
          "body" => "Roof closed for inspection until 14:00.",
          "channel_id" => to_string(Fixtures.channel().id),
          "requires_ack" => "true",
          "pinned" => "true"
        }
      )
      |> render_change()

      preview_html = render(view)
      assert has_element?(view, "#announcement-pinned")
      assert preview_html =~ "Roof access"
      assert preview_html =~ "Roof closed for inspection until 14:00."
      assert preview_html =~ "Pinned"
      assert preview_html =~ "Ack required"
      refute has_element?(view, "#announcement-preview-col #announcement-card-link-0")

      assert {:error, {:live_redirect, %{to: "/announcements/100", flash: flash}}} =
               view
               |> form("#announcement-new-form",
                 announcement: %{
                   "title" => "Roof access",
                   "body" => "Roof closed for inspection until 14:00.",
                   "channel_id" => to_string(Fixtures.channel().id),
                   "requires_ack" => "true",
                   "pinned" => "true"
                 }
               )
               |> render_submit()

      assert is_binary(flash)

      assert Utils.verify_flash(@endpoint, flash) == %{
               "info" => "Announcement published."
             }
    end

    test "compose submit surfaces flashes for :unauthorized and changeset errors",
         %{conn: conn} do
      # Mount as a manager so apply_new/1 lets us reach the form, then drive
      # both error branches of create_announcement via per-call expect/3.
      stub_with(Foyer.HouseMock, Foyer.HouseScenarios.WithReceipts)

      scope = IsolatedHelpers.scope_for(Fixtures.manager(), true)

      {conn, opts} =
        IsolatedHelpers.prepare_isolated(conn, FoyerWeb.AnnouncementLive, scope, action: :new)

      {:ok, view, _html} = live_isolated(conn, FoyerWeb.AnnouncementLive, opts)
      Mox.allow(Foyer.HouseMock, self(), view.pid)
      Mox.allow(Foyer.ChannelsMock, self(), view.pid)

      submit = fn ->
        view
        |> form("#announcement-new-form",
          announcement: %{
            "title" => "x",
            "body" => "y",
            "channel_id" => to_string(Fixtures.channel().id)
          }
        )
        |> render_submit()
      end

      # Error: unauthorized — covers the manager-gate-in-depth flash.
      Mox.expect(Foyer.HouseMock, :create_announcement, fn _user, _attrs ->
        {:error, :unauthorized}
      end)

      assert submit.() =~ "Only managers can publish announcements."

      # Error: changeset — covers the generic catch-all flash.
      Mox.expect(Foyer.HouseMock, :create_announcement, fn _user, attrs ->
        {:error,
         Announcement.changeset(%Announcement{}, attrs)
         |> Ecto.Changeset.add_error(:title, "is invalid")}
      end)

      assert submit.() =~ "Couldn&#39;t publish announcement."
    end
  end

  describe "F.Announcements.3 — edit submit" do
    test "author within grace submitting valid edits is redirected to detail", %{conn: conn} do
      stub_with(Foyer.HouseMock, Foyer.HouseScenarios.WithReceipts)

      scope = IsolatedHelpers.scope_for(Fixtures.manager(), true)

      {conn, opts} =
        IsolatedHelpers.prepare_isolated(conn, FoyerWeb.AnnouncementLive, scope,
          action: :edit,
          params: %{"id" => "100"}
        )

      {:ok, view, _html} = live_isolated(conn, FoyerWeb.AnnouncementLive, opts)
      Mox.allow(Foyer.HouseMock, self(), view.pid)
      Mox.allow(Foyer.ChannelsMock, self(), view.pid)

      # WithReceipts.update_announcement/3 returns {:ok, announcement}, so
      # the LV must push_navigate to /announcements/100 (the existing id).
      assert {:error, {:live_redirect, %{to: "/announcements/100"}}} =
               view
               |> form("#announcement-edit-form",
                 announcement: %{
                   "title" => "Updated title",
                   "body" => "Updated body",
                   "channel_id" => to_string(Fixtures.channel().id)
                 }
               )
               |> render_submit()
    end

    test "edit submit surfaces error flashes for each error return", %{conn: conn} do
      # Start with WithReceipts so apply_edit/2 mounts (within_grace_window?
      # returns true), then override update_announcement/3 per call.
      stub_with(Foyer.HouseMock, Foyer.HouseScenarios.WithReceipts)

      scope = IsolatedHelpers.scope_for(Fixtures.manager(), true)

      {conn, opts} =
        IsolatedHelpers.prepare_isolated(conn, FoyerWeb.AnnouncementLive, scope,
          action: :edit,
          params: %{"id" => "100"}
        )

      {:ok, view, _html} = live_isolated(conn, FoyerWeb.AnnouncementLive, opts)
      Mox.allow(Foyer.HouseMock, self(), view.pid)
      Mox.allow(Foyer.ChannelsMock, self(), view.pid)

      submit = fn ->
        view
        |> form("#announcement-edit-form",
          announcement: %{
            "title" => "t",
            "body" => "b",
            "channel_id" => to_string(Fixtures.channel().id)
          }
        )
        |> render_submit()
      end

      Mox.expect(Foyer.HouseMock, :update_announcement, fn _a, _u, _attrs ->
        {:error, :outside_grace_window}
      end)

      assert submit.() =~ "That announcement can no longer be edited."

      Mox.expect(Foyer.HouseMock, :update_announcement, fn _a, _u, _attrs ->
        {:error, :unauthorized}
      end)

      assert submit.() =~ "Only the author can edit this announcement."

      Mox.expect(Foyer.HouseMock, :update_announcement, fn _a, _u, attrs ->
        {:error,
         Announcement.changeset(%Announcement{}, attrs)
         |> Ecto.Changeset.add_error(:title, "is invalid")}
      end)

      assert submit.() =~ "Couldn&#39;t update announcement."
    end
  end

  describe "F.Announcements.4 — edit route rejects outside grace" do
    test "author visiting /announcements/:id/edit outside grace is redirected to detail",
         %{conn: conn} do
      # Empty scenario returns within_grace_window? = false, so apply_edit/2
      # hits the else branch and push_navigates to the detail page. The
      # author's identity is satisfied (managed_by? compares author_id), but
      # we need get_announcement to return a real fixture so the conditional
      # is reached at all.
      stub_with(Foyer.HouseMock, Foyer.HouseScenarios.Empty)

      # Empty.get_announcement/2 returns nil; override so apply_edit/2 reaches
      # the conditional. within_grace_window?/1 stays false (from Empty), so
      # the else branch fires and push_navigates back to the detail page.
      Mox.stub(Foyer.HouseMock, :get_announcement, fn _id, _u -> Fixtures.announcement() end)

      scope = IsolatedHelpers.scope_for(Fixtures.manager(), true)

      {conn, opts} =
        IsolatedHelpers.prepare_isolated(conn, FoyerWeb.AnnouncementLive, scope,
          action: :edit,
          params: %{"id" => "100"}
        )

      assert {:error, {:live_redirect, %{to: "/announcements/100"}}} =
               live_isolated(conn, FoyerWeb.AnnouncementLive, opts)
    end
  end

  describe "F.Announcements.4 — remove handler branches" do
    test "remove click surfaces success and each error flash", %{conn: conn} do
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

      # Error: outside grace window
      Mox.expect(Foyer.HouseMock, :remove_announcement, fn _a, _u ->
        {:error, :outside_grace_window}
      end)

      assert view |> element("#announcement-remove-btn") |> render_click() =~
               "That announcement can no longer be removed."

      # Error: unauthorized
      Mox.expect(Foyer.HouseMock, :remove_announcement, fn _a, _u ->
        {:error, :unauthorized}
      end)

      assert view |> element("#announcement-remove-btn") |> render_click() =~
               "Only the author can remove this announcement."

      # Error: catch-all
      Mox.expect(Foyer.HouseMock, :remove_announcement, fn _a, _u ->
        {:error, :boom}
      end)

      assert view |> element("#announcement-remove-btn") |> render_click() =~
               "Couldn&#39;t remove announcement."

      # Success: redirects to /house
      Mox.expect(Foyer.HouseMock, :remove_announcement, fn _a, _u ->
        {:ok, %{Fixtures.announcement() | removed_at: DateTime.utc_now()}}
      end)

      assert {:error, {:live_redirect, %{to: "/house"}}} =
               view |> element("#announcement-remove-btn") |> render_click()
    end
  end

  describe "F.Announcements.5 — pin/unpin handlers" do
    test "unpin click succeeds and renders pin button; pin error surfaces flash",
         %{conn: conn} do
      # The canonical fixture announcement starts pinned, so the unpin button
      # renders. WithReceipts.unpin_announcement/2 returns {:ok, …} which
      # clears `pinned_at` — covering update_pin_state's {:ok, updated}
      # branch (lines 231-237).
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

      # Unpin success — after this the pin button must render and the unpin
      # button must be gone.
      html_after_unpin = view |> element("#announcement-unpin-btn") |> render_click()
      assert html_after_unpin =~ "Announcement unpinned."
      assert has_element?(view, "#announcement-pin-btn")
      refute has_element?(view, "#announcement-unpin-btn")

      # Pin error: unauthorized — covers update_pin_state's
      # {:error, :unauthorized} branch (lines 239-240).
      Mox.expect(Foyer.HouseMock, :pin_announcement, fn _a, _u ->
        {:error, :unauthorized}
      end)

      assert view |> element("#announcement-pin-btn") |> render_click() =~
               "Only managers can pin announcements."

      # Pin error: catch-all (lines 242-243).
      Mox.expect(Foyer.HouseMock, :pin_announcement, fn _a, _u -> {:error, :boom} end)

      assert view |> element("#announcement-pin-btn") |> render_click() =~
               "Couldn&#39;t update pin."
    end
  end

  describe "F.Announcements.8 — acknowledge handler branches" do
    test "ack click renders Acknowledged on success and surfaces flashes on errors",
         %{conn: conn} do
      # Mount as a non-author staff user so the acknowledge CTA renders.
      # First two clicks force the error branches via per-call expect/3, then
      # the final click falls through to WithUnacked.acknowledge/2's
      # {:ok, _} return — covering all three branches of handle_event/3.
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

      # Three explicit expectations in order: :not_required, catch-all, ok.
      # Mox consumes expects in declaration order, so each click hits the next.
      Mox.expect(Foyer.HouseMock, :acknowledge, fn _a, _u -> {:error, :not_required} end)
      Mox.expect(Foyer.HouseMock, :acknowledge, fn _a, _u -> {:error, :boom} end)

      Mox.expect(Foyer.HouseMock, :acknowledge, fn _a, _u ->
        {:ok, %AnnouncementAck{}}
      end)

      assert view |> element("#acknowledge-btn") |> render_click() =~
               "No acknowledgement is required from you."

      assert view |> element("#acknowledge-btn") |> render_click() =~
               "Couldn&#39;t acknowledge announcement."

      html_after_ack = view |> element("#acknowledge-btn") |> render_click()
      assert html_after_ack =~ "Acknowledged."
      assert has_element?(view, "#acked-state")
      refute has_element?(view, "#acknowledge-btn")
    end
  end
end
