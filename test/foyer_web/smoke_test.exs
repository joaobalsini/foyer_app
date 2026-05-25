defmodule FoyerWeb.SmokeTest do
  @moduledoc """
  Thin route wiring smoke tests.

  These tests prove the seeded app can mount each major surface through the real
  router, session plugs, on-mount hooks, and Repo-backed ports. The Mox ports are
  stubbed to the real contexts so this is an end-to-end DB-backed wiring suite;
  feature behavior belongs in focused LiveView or context tests.
  """
  use FoyerWeb.ConnCase, async: true

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

    {:ok, seed_scaffold!()}
  end

  describe "public entry" do
    test "user picker mounts", %{conn: conn, maya: maya} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#user-picker")
      assert has_element?(view, "#pick-btn-#{maya.id}")
    end
  end

  describe "route gates" do
    test "F.Recognitions.1 / F.Chat.10 — off-shift users are redirected away from on-shift surfaces",
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
    end
  end

  describe "desktop rail" do
    test "primary authenticated surfaces render the desktop rail with active state", ctx do
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
    end

    test "manager today mounts", ctx do
      {:ok, view, _html} = ctx.conn |> sign_in(ctx.charlotte) |> live(~p"/today")

      assert has_element?(view, "#manager-today")
      assert has_element?(view, "#compose-cta")
    end

    test "off-shift today mounts", ctx do
      {:ok, view, _html} = ctx.conn |> sign_in(ctx.jamal) |> live(~p"/today")

      assert has_element?(view, "#off-shift")
      assert has_element?(view, "#start-shift-btn")
    end

    test "end shift route mounts", ctx do
      {:ok, view, _html} = ctx.conn |> sign_in(ctx.maya) |> live(~p"/today/end-shift")

      assert has_element?(view, "#end-shift-form")
    end
  end

  describe "house and announcement routes" do
    test "house feed mounts", ctx do
      {:ok, view, _html} = ctx.conn |> sign_in(ctx.maya) |> live(~p"/house")

      assert has_element?(view, "#house")
      assert has_element?(view, "#recognize-cta")
    end

    test "F.Announcements.2 — manager announcement compose mounts", ctx do
      {:ok, view, _html} = ctx.conn |> sign_in(ctx.charlotte) |> live(~p"/announcements/new")

      assert has_element?(view, "#announcement-new-form")
    end

    test "F.Announcements.7 / F.Announcements.9 — announcement detail mounts", ctx do
      {:ok, view, _html} =
        ctx.conn
        |> sign_in(ctx.maya)
        |> live(~p"/announcements/#{ctx.suite_412.id}")

      assert has_element?(view, "#announcement")
      assert has_element?(view, "#back-to-house")
    end

    test "F.Announcements.3 — announcement edit mounts for author", ctx do
      {:ok, view, _html} =
        ctx.conn
        |> sign_in(ctx.charlotte)
        |> live(~p"/announcements/#{ctx.suite_412.id}/edit")

      assert has_element?(view, "#announcement-edit-form")
    end
  end

  describe "chat routes" do
    test "F.Chat.5 / F.Chat.9 — chat inbox mounts", ctx do
      {:ok, view, _html} = ctx.conn |> sign_in(ctx.maya) |> live(~p"/chat")

      assert has_element?(view, "#chat")
      assert has_element?(view, "#chat-panel-inbox")
    end

    test "F.Chat.6 / F.Chat.7 / F.Chat.10 — chat room mounts", ctx do
      {:ok, view, _html} =
        ctx.conn |> sign_in(ctx.maya) |> live(~p"/chat/#{ctx.maya_charlotte.id}")

      assert has_element?(view, "#chat-panel-room")
      assert has_element?(view, "#messages")
    end

    test "F.Chat.10 / F.Chat.11 — new message picker mounts", ctx do
      {:ok, view, _html} = ctx.conn |> sign_in(ctx.maya) |> live(~p"/chat/new")

      assert has_element?(view, "#new-message")
      assert has_element?(view, "#new-msg-tab-people")
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
    end

    test "F.Recognitions.10 — recognition detail mounts", ctx do
      {:ok, view, _html} =
        ctx.conn
        |> sign_in(ctx.maya)
        |> live(~p"/recognitions/#{ctx.maya_recognition.id}")

      assert has_element?(view, "#recognition-detail")
    end

    test "F.Recognitions.9 — recognition edit mounts for author", ctx do
      {:ok, view, _html} =
        ctx.conn
        |> sign_in(ctx.charlotte)
        |> live(~p"/recognitions/#{ctx.hugo_recognition.id}/edit")

      assert has_element?(view, "#recognition-edit-form")
    end
  end

  describe "profile and people routes" do
    test "me mounts", ctx do
      {:ok, view, _html} = ctx.conn |> sign_in(ctx.maya) |> live(~p"/me")

      assert has_element?(view, "[id^='profile-']")
    end

    test "people index mounts", ctx do
      {:ok, view, _html} = ctx.conn |> sign_in(ctx.charlotte) |> live(~p"/people")

      assert has_element?(view, "#people")
    end

    test "people profile mounts", ctx do
      {:ok, view, _html} = ctx.conn |> sign_in(ctx.maya) |> live(~p"/people/#{ctx.hugo.id}")

      assert has_element?(view, "#back-to-people")
    end
  end
end
