defmodule FoyerWeb.SmokeTest do
  @moduledoc """
  Thin route wiring smoke tests.

  These tests prove the seeded app can mount each major surface through the real
  router, session plugs, on-mount hooks, and Repo-backed ports. The Mox ports are
  stubbed to the real contexts so this is an end-to-end DB-backed wiring suite;
  feature behavior belongs in focused LiveView or context tests.

  Covers (route-wiring layer for clauses that also have focused unit tests
  elsewhere):
    F.Announcements.2 — manager compose mounts / staff redirected
    F.Announcements.3 — author edit mounts
    F.Announcements.7 — ack flow and inaccessible-announcement redirect
    F.Announcements.9 — announcement detail mounts with ack control
    F.Channels.15     — people index renders all seeded users
    F.Channels.16     — on-shift pulse for on-shift users
    F.Channels.17     — channel pills come from real membership rows
    F.Channels.18     — off-shift gate redirects /people to /today
    F.Channels.21     — channel filter narrows and clears
    F.Channels.22     — :show renders #target-channels from Channels API
    F.Chat.5          — inbox mounts
    F.Chat.6          — room mounts with messages
    F.Chat.7          — room renders read state
    F.Chat.8          — menu unread dots reflect PubSub updates
    F.Chat.9          — inbox preview renders latest message
    F.Chat.10         — room mount / channel deep link / picker mount
    F.Chat.11         — picker tabs
    F.Profile.1       — /me renders profile content
    F.Profile.6       — colleague profile hides private recognitions
    F.Profile.8       — colleague profile hides given list
    F.Profile.11      — /me renders Foyer points section
    F.Profile.17      — desktop rail rendered on primary surfaces
    F.Profile.18      — /me gated for off-shift users
    F.Profile.25      — property code rendered from config
    F.Recognitions.1  — recognition new mounts
    F.Recognitions.9  — recognition edit mounts for author
    F.Recognitions.10 — recognition index and detail mount
    F.Today.2         — off-shift route gate redirects to /today
  """
  use FoyerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Mox
  import FoyerWeb.ScaffoldFixtures

  alias Foyer.House.Announcement

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

    {:ok, seed_scaffold!()}
  end

  describe "public entry" do
    test "user picker mounts", %{conn: conn, maya: maya} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#user-picker")
      assert has_element?(view, "#pick-btn-#{maya.id}")
    end

    test "session pick puts the user on the session and redirects to /today",
         %{conn: conn, maya: maya} do
      conn =
        conn
        |> Phoenix.ConnTest.init_test_session(%{})
        |> post(~p"/session/pick/#{maya.id}")

      assert redirected_to(conn) == ~p"/today"
      assert get_session(conn, :current_user_id) == maya.id
    end

    test "session delete clears the user and redirects to /", ctx do
      conn = ctx.conn |> sign_in(ctx.maya) |> delete(~p"/session")

      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :current_user_id)
    end
  end

  describe "route gates" do
    test "F.Today.2 / F.Recognitions.1 / F.Chat.10 / F.Profile.18 / F.Channels.18 — off-shift users are redirected away from on-shift surfaces",
         ctx do
      assert {:error, {:redirect, %{to: "/today"}}} =
               ctx.conn
               |> sign_in(ctx.jamal)
               |> live(~p"/house")

      assert {:error, {:redirect, %{to: "/today"}}} =
               build_conn()
               |> sign_in(ctx.jamal)
               |> live(~p"/chat")

      assert {:error, {:redirect, %{to: "/today"}}} =
               build_conn()
               |> sign_in(ctx.jamal)
               |> live(~p"/recognitions")

      assert {:error, {:redirect, %{to: "/today"}}} =
               build_conn()
               |> sign_in(ctx.jamal)
               |> live(~p"/me")

      assert {:error, {:redirect, %{to: "/today"}}} =
               build_conn()
               |> sign_in(ctx.jamal)
               |> live(~p"/people")
    end
  end

  describe "desktop rail" do
    test "F.Profile.17 — primary authenticated surfaces render the desktop rail with active state",
         ctx do
      {:ok, today, _html} = ctx.conn |> sign_in(ctx.maya) |> live(~p"/today")
      assert has_element?(today, "#desktop-rail")
      assert has_element?(today, "#rail-nav-today[aria-current='page']")
      assert has_element?(today, "#rail-chat-unread")
      assert has_element?(today, "#bottom-nav-chat-unread-dot")

      {:ok, house, _html} = build_conn() |> sign_in(ctx.maya) |> live(~p"/house")
      assert has_element?(house, "#rail-nav-house[aria-current='page']")
      assert has_element?(house, "#rail-chat-unread")

      {:ok, chat, _html} = build_conn() |> sign_in(ctx.maya) |> live(~p"/chat")
      assert has_element?(chat, "#rail-nav-chat[aria-current='page']")
      assert has_element?(chat, "#rail-chat-unread")

      {:ok, profile, _html} = build_conn() |> sign_in(ctx.maya) |> live(~p"/me")
      assert has_element?(profile, "#rail-nav-me[aria-current='page']")
      assert has_element?(profile, "#rail-chat-unread")
    end

    test "off-shift rail disables on-shift destinations", ctx do
      {:ok, view, _html} = ctx.conn |> sign_in(ctx.jamal) |> live(~p"/today")

      assert has_element?(view, "#rail-nav-house[disabled]")
      assert has_element?(view, "#rail-nav-chat[disabled]")
      assert has_element?(view, "#rail-nav-me[disabled]")
    end

    test "rail sign-out link carries CSRF data for delete requests", ctx do
      {:ok, _view, html} = ctx.conn |> sign_in(ctx.maya) |> live(~p"/today")

      sign_out_anchor =
        ~r/<a[^>]*data-method="delete"[^>]*data-csrf="[^"]+"[^>]*data-to="\/session"[^>]*id="rail-sign-out"/

      assert Regex.match?(sign_out_anchor, html)
    end

    test "F.Chat.8 / F.Chat.10 — menu unread dots update from chat PubSub while page is open",
         ctx do
      assert {:ok, _read} = Foyer.Chat.mark_read(ctx.maya_charlotte, ctx.maya)

      {:ok, view, _html} = ctx.conn |> sign_in(ctx.maya) |> live(~p"/today")

      refute has_element?(view, "#rail-chat-unread")
      refute has_element?(view, "#bottom-nav-chat-unread-dot")

      assert {:ok, _message} =
               Foyer.Chat.send_message(ctx.maya_charlotte, ctx.charlotte, %{
                 "body" => "Can you check 412?"
               })

      assert has_element?(view, "#rail-chat-unread")
      assert has_element?(view, "#bottom-nav-chat-unread-dot")
    end
  end

  describe "today routes" do
    test "staff today mounts", ctx do
      {:ok, view, _html} = ctx.conn |> sign_in(ctx.maya) |> live(~p"/today")

      assert has_element?(view, "#today")
      assert has_element?(view, "#on-shift-staff")
      assert has_element?(view, "#bottom-nav-today")
      assert render(view) =~ "Maya"
      assert render(view) =~ "Housekeeping"
      assert render(view) =~ "Suite 412"
    end

    test "manager today mounts", ctx do
      {:ok, view, _html} = ctx.conn |> sign_in(ctx.charlotte) |> live(~p"/today")

      assert has_element?(view, "#manager-today")
      assert has_element?(view, "#compose-cta")
      assert render(view) =~ "Charlotte"
    end

    test "off-shift today mounts and starts a shift", ctx do
      {:ok, view, _html} = ctx.conn |> sign_in(ctx.jamal) |> live(~p"/today")

      assert has_element?(view, "#off-shift")
      assert has_element?(view, "#start-shift-btn")
      assert has_element?(view, "#bottom-nav-house[disabled]")
      assert has_element?(view, "#bottom-nav-chat[disabled]")

      view |> element("#start-shift-btn") |> render_click()

      {:ok, _house_view, _html} =
        build_conn()
        |> sign_in(ctx.jamal)
        |> live(~p"/house")
    end

    test "end shift route submits handoff and gates house afterward", ctx do
      {:ok, view, _html} = ctx.conn |> sign_in(ctx.maya) |> live(~p"/today/end-shift")

      assert has_element?(view, "#end-shift-form")

      view
      |> form("#end-shift-form", shift: %{handoff_note: "All clear in 412."})
      |> render_submit()

      assert {:error, {:redirect, %{to: "/today"}}} =
               build_conn()
               |> sign_in(ctx.maya)
               |> live(~p"/house")
    end
  end

  describe "house and announcement routes" do
    test "house feed mounts", ctx do
      {:ok, view, _html} = ctx.conn |> sign_in(ctx.maya) |> live(~p"/house")

      assert has_element?(view, "#house")
      assert has_element?(view, "#recognize-cta")
      assert render(view) =~ "Suite 412"
      assert render(view) =~ "Pinned"
    end

    test "F.Announcements.2 — manager announcement compose mounts", ctx do
      {:ok, view, _html} = ctx.conn |> sign_in(ctx.charlotte) |> live(~p"/announcements/new")

      assert has_element?(view, "#announcement-new-form")
      assert render(view) =~ "New announcement"
    end

    test "F.Announcements.2 — staff announcement compose redirects to house", ctx do
      assert {:error, {:live_redirect, %{to: "/house"}}} =
               ctx.conn
               |> sign_in(ctx.maya)
               |> live(~p"/announcements/new")
    end

    test "F.Announcements.7 / F.Announcements.9 — announcement detail mounts", ctx do
      {:ok, view, _html} =
        ctx.conn
        |> sign_in(ctx.maya)
        |> live(~p"/announcements/#{ctx.suite_412.id}")

      assert has_element?(view, "#announcement")
      assert has_element?(view, "#back-to-house")
      assert has_element?(view, "button", "I've read & understood")

      view |> element("button", "I've read & understood") |> render_click()

      assert render(view) =~ "Acknowledged"
    end

    test "F.Announcements.3 — announcement edit mounts for author", ctx do
      {:ok, view, _html} =
        ctx.conn
        |> sign_in(ctx.charlotte)
        |> live(~p"/announcements/#{ctx.suite_412.id}/edit")

      assert has_element?(view, "#announcement-edit-form")
      assert render(view) =~ "Edit announcement"
    end

    test "F.Announcements.7 — users cannot open inaccessible announcements", ctx do
      assert {:error, {:live_redirect, %{to: "/house"}}} =
               ctx.conn
               |> sign_in(ctx.maya)
               |> live(~p"/announcements/#{ctx.leadership_only_announcement.id}")
    end

    test "announcement ack badges render acking user initials", ctx do
      announcement_id = create_acked_announcement(ctx)

      {:ok, view, _html} =
        ctx.conn
        |> sign_in(ctx.charlotte)
        |> live(~p"/announcements/#{announcement_id}")

      assert has_element?(view, "#ack-badge-#{ctx.maya.id}")
      refute render(view) =~ ">?? ✓"
    end
  end

  describe "chat routes" do
    test "F.Chat.5 / F.Chat.9 — chat inbox mounts", ctx do
      {:ok, view, _html} = ctx.conn |> sign_in(ctx.maya) |> live(~p"/chat")

      assert has_element?(view, "#chat")
      assert has_element?(view, "#chat-panel-inbox")
      assert render(view) =~ "Charlotte Voss"
    end

    test "F.Chat.6 / F.Chat.7 / F.Chat.10 — chat room mounts", ctx do
      {:ok, view, _html} =
        ctx.conn |> sign_in(ctx.maya) |> live(~p"/chat/#{ctx.maya_charlotte.id}")

      assert has_element?(view, "#chat-panel-room")
      assert has_element?(view, "#messages")
      refute has_element?(view, "#off-shift-banner")
      assert render(view) =~ "Morning Maya"
    end

    test "F.Chat.10 / F.Chat.11 — new message picker mounts", ctx do
      {:ok, view, _html} = ctx.conn |> sign_in(ctx.maya) |> live(~p"/chat/new")

      assert has_element?(view, "#new-message")
      assert has_element?(view, "#new-msg-tab-people")
      assert render(view) =~ "Hugo Brandt"
    end

    test "F.Chat.10 — channel deep link routes through the new message entrypoint", ctx do
      floor_4 = Foyer.Repo.get_by!(Foyer.Channels.Channel, name: "Housekeeping · Floor 4")

      assert {:error, {:live_redirect, %{to: to}}} =
               ctx.conn
               |> sign_in(ctx.maya)
               |> live(~p"/chat/new?channel_id=#{floor_4.id}")

      assert to =~ ~r"/chat/\d+"
    end
  end

  describe "recognition routes" do
    test "F.Recognitions.10 — recognitions index mounts", ctx do
      {:ok, view, _html} = ctx.conn |> sign_in(ctx.maya) |> live(~p"/recognitions")

      assert has_element?(view, "#recognitions")
      assert has_element?(view, "#recognitions-new-cta")
    end

    test "F.Recognitions.1 — new recognition mounts", ctx do
      {:ok, view, _html} = ctx.conn |> sign_in(ctx.maya) |> live(~p"/recognitions/new")

      assert has_element?(view, "#recognize-form")
      assert render(view) =~ "Give recognition"
    end

    test "F.Recognitions.10 — recognition detail mounts", ctx do
      {:ok, view, _html} =
        ctx.conn
        |> sign_in(ctx.maya)
        |> live(~p"/recognitions/#{ctx.maya_recognition.id}")

      assert has_element?(view, "#recognition-detail")
      assert render(view) =~ "Quietly handled a 02:14 guest issue"
    end

    test "F.Recognitions.9 — recognition edit mounts for author", ctx do
      {:ok, view, _html} =
        ctx.conn
        |> sign_in(ctx.charlotte)
        |> live(~p"/recognitions/#{ctx.hugo_recognition.id}/edit")

      assert has_element?(view, "#recognition-edit-form")
      assert render(view) =~ "Edit recognition"
    end
  end

  describe "profile and people routes" do
    test "F.Profile.1 / F.Profile.11 / F.Profile.25 — me mounts with profile content", ctx do
      {:ok, view, _html} = ctx.conn |> sign_in(ctx.maya) |> live(~p"/me")

      assert has_element?(view, "[id^='profile-']")
      assert has_element?(view, "#stats-recognitions-this-month")
      assert has_element?(view, "#stats-ack-on-time")
      assert render(view) =~ "Maya Okafor"
      assert render(view) =~ "Foyer points"
      assert render(view) =~ "LDN·MAY"
    end

    test "F.Channels.15 — people index renders a row for every seeded user", ctx do
      {:ok, view, _html} = ctx.conn |> sign_in(ctx.charlotte) |> live(~p"/people")

      assert has_element?(view, "#people")
      assert has_element?(view, "#people-row-#{ctx.maya.id}")
      assert has_element?(view, "#people-row-#{ctx.charlotte.id}")
      assert has_element?(view, "#people-row-#{ctx.hugo.id}")
      assert has_element?(view, "#people-row-#{ctx.rafael.id}")
      assert has_element?(view, "#people-row-#{ctx.aisha.id}")
      assert has_element?(view, "#people-row-#{ctx.jamal.id}")
      assert render(view) =~ "Sebastien Roy"
    end

    test "F.Channels.16 — on-shift Maya has the pulse, off-shift Jamal does not", ctx do
      {:ok, view, _html} = ctx.conn |> sign_in(ctx.charlotte) |> live(~p"/people")

      assert has_element?(view, "#people-row-#{ctx.maya.id} .foyer-tag.moss")
      refute has_element?(view, "#people-row-#{ctx.jamal.id} .foyer-tag.moss")
    end

    test "F.Channels.17 — channel membership pills come from real membership rows", ctx do
      {:ok, view, _html} = ctx.conn |> sign_in(ctx.charlotte) |> live(~p"/people")

      assert has_element?(
               view,
               "#people-row-#{ctx.maya.id} [id^='person-#{ctx.maya.id}-channel-']"
             )
    end

    test "F.Channels.21 — channel filter shows only members, clearing restores all", ctx do
      {:ok, view, _html} = ctx.conn |> sign_in(ctx.charlotte) |> live(~p"/people")

      assert has_element?(view, "#people-row-#{ctx.maya.id}")
      assert has_element?(view, "#people-row-#{ctx.hugo.id}")

      leadership =
        ctx.charlotte
        |> Foyer.Channels.list_for_user()
        |> Enum.find(fn c -> c.slug == "leadership" end)

      view |> element("#filter-channel-#{leadership.id}") |> render_click()

      assert has_element?(view, "#people-row-#{ctx.charlotte.id}")
      assert has_element?(view, "#people-row-#{ctx.rafael.id}")
      refute has_element?(view, "#people-row-#{ctx.maya.id}")

      view |> element("#filter-all") |> render_click()
      assert has_element?(view, "#people-row-#{ctx.maya.id}")
    end

    test "F.Channels.22 — :show renders #target-channels (channel pills from Channels API)",
         ctx do
      {:ok, view, _html} = ctx.conn |> sign_in(ctx.maya) |> live(~p"/people/#{ctx.maya.id}")

      assert has_element?(view, "#target-channels")
    end

    test "people :show renders the colleague name and back button", ctx do
      {:ok, view, _html} = ctx.conn |> sign_in(ctx.maya) |> live(~p"/people/#{ctx.hugo.id}")

      assert has_element?(view, "#back-to-people")
      assert render(view) =~ "Hugo Brandt"
    end

    test "F.Profile.6 / F.Profile.8 — colleague profile hides private recognitions and given list",
         ctx do
      {:ok, view, _html} =
        ctx.conn
        |> sign_in(ctx.maya)
        |> live(~p"/people/#{ctx.aisha.id}")

      refute has_element?(view, "#recognitions-given")
      refute render(view) =~ ctx.private_recognition.body
    end
  end

  defp create_acked_announcement(ctx) do
    floor_4 =
      Foyer.Channels.list_for_user(ctx.charlotte)
      |> Enum.find(fn channel -> channel.slug == "housekeeping-floor-4" end)

    {:ok, announcement} =
      %Announcement{}
      |> Announcement.changeset(%{
        author_id: ctx.charlotte.id,
        channel_id: floor_4.id,
        title: "Ack-required test announcement",
        body: "Please confirm.",
        requires_ack: true,
        published_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Foyer.Repo.insert()

    {:ok, _ack} = Foyer.House.acknowledge(announcement, ctx.maya)

    announcement.id
  end
end
