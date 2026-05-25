defmodule FoyerWeb.ScaffoldSmokeTest do
  # async: true — each test owns its sandbox transaction; fixtures are
  # inserted in setup. We do NOT rely on priv/repo/seeds.exs (that file is for
  # manual demo runs).
  use FoyerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Mox
  import FoyerWeb.ScaffoldFixtures

  @moduletag :integration

  # Mox verifies any expectations set per test on exit. Smoke tests only use
  # `stub_with` (no `expect`), so this is a guard for future edits.
  setup :verify_on_exit!

  # set_mox_from_context lets the LiveView process (a separate pid) see the
  # stubs we register on the test process. Without it, LiveView->LiveDeps
  # calls hit Mox in `:private` mode and fail.
  setup :set_mox_from_context

  setup do
    # config/test.exs points LiveDeps at Foyer.*Mock modules. We bind each
    # mock to the real context so the smoke test exercises the real Repo
    # path. Future isolated tests should `stub_with` a scenario module
    # instead of a real context — they MUST NOT use Application.put_env/3
    # (forbidden by docs/TESTING_GUIDE.md).
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

  describe "user picker" do
    test "lists every seeded user with their initials", %{conn: conn, maya: maya} do
      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ "Pick a user"
      assert html =~ maya.name
      assert html =~ maya.initials
    end
  end

  describe "Today — on-shift staff (Maya)" do
    test "renders briefing and bottom-nav, with on-shift status pill", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/today")

      assert has_element?(view, "#today")
      assert render(view) =~ "Good morning"
      assert render(view) =~ "Maya"
      assert render(view) =~ "Housekeeping"
      assert render(view) =~ "Floor 4"
      assert render(view) =~ "Handoff from your last shift"
      assert render(view) =~ "Suite 412"
      assert render(view) =~ "Allergy protocol in effect"
      assert render(view) =~ "Pinned"

      # Bottom-nav assertions: stable IDs.
      assert has_element?(view, "#bottom-nav-today")
      assert has_element?(view, "#bottom-nav-house")
      assert has_element?(view, "#bottom-nav-chat")
      assert has_element?(view, "#bottom-nav-me")
    end
  end

  describe "Today — manager (Charlotte)" do
    test "shows compose CTA", ctx do
      conn = sign_in(ctx.conn, ctx.charlotte)
      {:ok, view, _html} = live(conn, ~p"/today")

      assert has_element?(view, "#compose-cta")
      assert render(view) =~ "Good morning"
      assert render(view) =~ "Charlotte"
    end
  end

  describe "Today — off-shift (Jamal)" do
    test "renders the off-shift card with Start shift, and starts shift on click", ctx do
      conn = sign_in(ctx.conn, ctx.jamal)
      {:ok, view, _html} = live(conn, ~p"/today")

      assert has_element?(view, "#off-shift")
      # The apostrophe is HTML-escaped in the rendered output; match without it.
      assert render(view) =~ "off the clock"
      assert has_element?(view, "#start-shift-btn", "Start shift")

      # Bottom-nav House/Chat/Me are disabled buttons (defence in depth).
      assert has_element?(view, "#bottom-nav-house[disabled]")
      assert has_element?(view, "#bottom-nav-chat[disabled]")

      # Click Start shift -> Jamal is now on shift -> can reach /house.
      view |> element("#start-shift-btn") |> render_click()

      conn = sign_in(build_conn(), ctx.jamal)
      {:ok, _house_view, _html} = live(conn, ~p"/house")
    end

    test "off-shift gate redirects /house to /today", ctx do
      conn = sign_in(ctx.conn, ctx.jamal)
      assert {:error, {:redirect, %{to: "/today"}}} = live(conn, ~p"/house")
    end

    test "off-shift gate redirects /chat to /today", ctx do
      conn = sign_in(ctx.conn, ctx.jamal)
      assert {:error, {:redirect, %{to: "/today"}}} = live(conn, ~p"/chat")
    end
  end

  describe "End shift" do
    test "Maya can submit the end-shift form", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/today/end-shift")

      assert has_element?(view, "#end-shift-form")

      view
      |> form("#end-shift-form", shift: %{handoff_note: "All clear in 412."})
      |> render_submit()

      # Maya is now off shift -> /house redirects to /today.
      conn = sign_in(build_conn(), ctx.maya)
      assert {:error, {:redirect, %{to: "/today"}}} = live(conn, ~p"/house")
    end
  end

  describe "House" do
    test "lists feed with pinned + non-pinned posts", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/house")

      assert render(view) =~ "The House"
      assert render(view) =~ "Suite 412"
      assert render(view) =~ "Allergy protocol in effect"
      assert render(view) =~ "Pinned"
      assert has_element?(view, "#recognize-cta")
    end

    test "compose page opens (for manager)", ctx do
      conn = sign_in(ctx.conn, ctx.charlotte)
      {:ok, view, _html} = live(conn, ~p"/announcements/new")
      assert has_element?(view, "#announcement-new-form")
      assert render(view) =~ "New announcement"
    end

    test "announcement detail renders ack action and click acks the announcement", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/announcements/#{ctx.suite_412.id}")

      assert render(view) =~ "Requires acknowledgement"
      assert has_element?(view, "button", "I've read & understood")

      view |> element("button", "I've read & understood") |> render_click()
      assert render(view) =~ "Acknowledged"
    end

    test "announcement author does not see acknowledgement CTA", ctx do
      conn = sign_in(ctx.conn, ctx.charlotte)
      {:ok, view, _html} = live(conn, ~p"/announcements/#{ctx.suite_412.id}")

      refute has_element?(view, "#acknowledge-btn")
    end

    test "edit page opens for the author", ctx do
      conn = sign_in(ctx.conn, ctx.charlotte)
      {:ok, view, _html} = live(conn, ~p"/announcements/#{ctx.suite_412.id}/edit")
      assert has_element?(view, "#announcement-edit-form")
      assert render(view) =~ "Edit announcement"
    end

    test "unauthorized: Maya cannot open a Leadership-only announcement", ctx do
      conn = sign_in(ctx.conn, ctx.maya)

      # The redirect happens inside handle_params/3 via push_navigate/2, which
      # produces a `:live_redirect` (not the `:redirect` the on-mount gates
      # produce — see plan §3.3 vs §7.4).
      assert {:error, {:live_redirect, %{to: "/house"}}} =
               live(conn, ~p"/announcements/#{ctx.leadership_only_announcement.id}")
    end

    test "F.Announcements.2 staff visiting /announcements/new is redirected and no form renders",
         ctx do
      conn = sign_in(ctx.conn, ctx.maya)

      # Staff are on-shift here, so the route admits them; the LiveView gate
      # in apply_new/1 must redirect with a flash. If a future change replaces
      # this redirect with a render-only gate, this assertion still passes —
      # but if the gate is dropped entirely, the form will render and live/2
      # will return {:ok, _, _}, failing the redirect match below.
      assert {:error, {:live_redirect, %{to: "/house"}}} = live(conn, ~p"/announcements/new")
    end

    test "F.Announcements.5 manager can pin and unpin an announcement", ctx do
      # suite_412 is pinned in the fixture; start by unpinning it.
      conn = sign_in(ctx.conn, ctx.charlotte)
      {:ok, view, _html} = live(conn, ~p"/announcements/#{ctx.suite_412.id}")

      assert has_element?(view, "#announcement-unpin-btn")
      view |> element("#announcement-unpin-btn") |> render_click()
      assert has_element?(view, "#announcement-pin-btn")

      view |> element("#announcement-pin-btn") |> render_click()
      assert has_element?(view, "#announcement-unpin-btn")
    end

    test "F.Announcements.6 removing an announcement drops it from feeds and back to /house",
         ctx do
      conn = sign_in(ctx.conn, ctx.charlotte)
      {:ok, view, _html} = live(conn, ~p"/announcements/#{ctx.suite_412.id}")

      assert has_element?(view, "#announcement-remove-btn")
      result = view |> element("#announcement-remove-btn") |> render_click()
      assert {:error, {:live_redirect, %{to: "/house"}}} = result

      # Maya can no longer see the announcement in her feed.
      conn = sign_in(build_conn(), ctx.maya)
      {:ok, _house_view, html} = live(conn, ~p"/house")
      refute html =~ "Allergy protocol in effect"
    end
  end

  describe "Chat" do
    test "inbox lists the seeded conversations", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/chat")

      assert render(view) =~ "Messages"
      assert render(view) =~ "Charlotte Voss"
    end

    test "room renders messages", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/chat/#{ctx.maya_charlotte.id}")
      assert render(view) =~ "Morning Maya"
    end

    test "new message picker lists colleagues", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/chat/new")
      assert render(view) =~ "New message"
      assert render(view) =~ "Hugo Brandt"
    end
  end

  describe "Recognitions" do
    test "index lists public recognitions", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/recognitions")
      assert render(view) =~ "Recognitions"
      assert has_element?(view, "#recognitions-new-cta")
    end

    test "new form renders with house values", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/recognitions/new")
      assert render(view) =~ "Give recognition"

      for v <- ~w(Care Craft Discretion Initiative Warmth Excellence Team) do
        assert render(view) =~ v
      end
    end

    test "manager sees bonus points tiers", ctx do
      conn = sign_in(ctx.conn, ctx.charlotte)
      {:ok, view, _html} = live(conn, ~p"/recognitions/new")
      assert render(view) =~ "Bonus points"
      assert render(view) =~ "+50"
    end

    test "show renders a single recognition", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/recognitions/#{ctx.maya_recognition.id}")
      assert render(view) =~ "Quietly handled a 02:14 guest issue"
    end

    test "edit page opens for the author", ctx do
      conn = sign_in(ctx.conn, ctx.charlotte)
      {:ok, view, _html} = live(conn, ~p"/recognitions/#{ctx.hugo_recognition.id}/edit")
      assert has_element?(view, "#recognition-edit-form")
      assert render(view) =~ "Edit recognition"
    end
  end

  describe "Profile / Me" do
    test "Me opens current user profile with received recognitions", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/me")
      assert render(view) =~ "Maya Okafor"
      assert render(view) =~ "Quietly handled a 02:14 guest issue"
      assert render(view) =~ "Foyer points"
    end
  end

  describe "People directory" do
    test "lists the cast", ctx do
      conn = sign_in(ctx.conn, ctx.charlotte)
      {:ok, view, _html} = live(conn, ~p"/people")
      assert render(view) =~ "People"
      assert render(view) =~ "Maya Okafor"
      assert render(view) =~ "bastien Roy"
    end

    test "/people/:id renders the colleague's profile card", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/people/#{ctx.hugo.id}")
      assert render(view) =~ "Hugo Brandt"
      assert has_element?(view, "#back-to-people")
    end
  end
end
