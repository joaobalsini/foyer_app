defmodule FoyerWeb.ChatLiveTest do
  @moduledoc """
  Isolated LiveView tests for `FoyerWeb.ChatLive`. Per
  `docs/TESTING_GUIDE.md`, these are the primary behaviour layer: they mount
  the LV directly with `live_isolated/3`, skip the router and on-mount
  hooks, and use scenario modules to pin a particular "shape of the world."

  No database. No seeds. `Mox.stub_with/2` swaps in scenario modules per
  test, and `Mox.expect/3` asserts on exact side-effect calls (compose
  submit, mark_read, open_direct) when that's what the test cares about.

  See `test/support/scenarios/` for the world shapes used here.

  Covers:
    F.Chat.4  — open_channel unauthorized + changeset error paths
    F.Chat.5  — empty conversations excluded from rendered inbox
    F.Chat.6  — compose form fires send_message (success + error paths)
    F.Chat.7  — mark_read triggered on conversation open
    F.Chat.8  — unread count rendering flips with scenario state and
                refreshes on chat_unread_updated / chat_inbox_updated
                broadcasts
    F.Chat.9  — latest preview and unread dot rendering
    F.Chat.10 — incoming room message stream append plus open-direct /
                open-channel picker redirects, missing-conversation
                rescue, and stale chat_message broadcast ignored
    F.Chat.11 — picker off-shift tag, room header shift state, and
                direct-room off-shift delivery note
  """
  use ExUnit.Case, async: true

  @endpoint FoyerWeb.Endpoint

  import FoyerWeb.IsolatedHelpers
  import Mox
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Foyer.Chat
  alias Foyer.Chat.Conversation
  alias Foyer.Chat.Participant
  alias Foyer.ChatScenarios.EmptyInbox
  alias Foyer.ChatScenarios.Fixtures
  alias Foyer.ChatScenarios.RoomWithMessages
  alias Foyer.ChatScenarios.WithUnread

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    # Default scenario layer: empty world. Each test overrides what it needs.
    stub_with(Foyer.AccountsMock, Foyer.AccountsScenarios.PeopleWithOffShift)
    stub_with(Foyer.ChannelsMock, Foyer.ChannelsScenarios.MayaMembership)
    stub_with(Foyer.ShiftsMock, Foyer.ShiftsScenarios.MayaCharlotteHugoOn)

    {:ok, conn: build_conn()}
  end

  describe "F.Chat.5 inbox excludes empty conversations" do
    test "renders no conversation rows when the scenario inbox is empty", %{conn: conn} do
      stub_with(Foyer.ChatMock, EmptyInbox)

      {:ok, view, _html} = mount_isolated_chat(conn, Fixtures.maya(), live_action: :inbox)
      Mox.allow(Foyer.ChatMock, self(), view.pid)

      # No conversation row should render. The stream container is present but
      # holds no items.
      refute has_element?(view, "#conversation-row-50")
      refute has_element?(view, "#conversation-row-60")
      # The bottom-nav unread dot disappears when unread_count is 0.
      refute has_element?(view, "#bottom-nav-chat-unread-dot")
    end
  end

  describe "F.Chat.9 inbox renders enriched conversations" do
    test "renders the latest message preview and unread dot per conversation", %{conn: conn} do
      stub_with(Foyer.ChatMock, WithUnread)

      {:ok, view, _html} = mount_isolated_chat(conn, Fixtures.maya(), live_action: :inbox)
      Mox.allow(Foyer.ChatMock, self(), view.pid)

      assert has_element?(view, "#conversation-row-50")
      assert has_element?(view, "#conversation-unread-50")
      # The latest-message preview is part of the inbox row.
      assert render(view) =~ "Confirmed in 412."
    end
  end

  describe "F.Chat.8 unread_count rendering flips with scenario state" do
    test "renders the bottom-nav unread dot when unread_count > 0", %{conn: conn} do
      stub_with(Foyer.ChatMock, WithUnread)

      {:ok, view, _html} = mount_isolated_chat(conn, Fixtures.maya(), live_action: :inbox)
      Mox.allow(Foyer.ChatMock, self(), view.pid)

      assert has_element?(view, "#bottom-nav-chat-unread-dot")
    end

    test "omits the bottom-nav unread dot when unread_count == 0", %{conn: conn} do
      stub_with(Foyer.ChatMock, RoomWithMessages)

      {:ok, view, _html} = mount_isolated_chat(conn, Fixtures.maya(), live_action: :inbox)
      Mox.allow(Foyer.ChatMock, self(), view.pid)

      refute has_element?(view, "#bottom-nav-chat-unread-dot")
    end
  end

  describe "F.Chat.7 mark_read is triggered when a conversation is opened" do
    test "load_conversation/2 calls mark_read/2 with the open conversation and current user",
         %{conn: conn} do
      # Stub the read-side calls with a scenario, then layer an explicit
      # expect/3 on the side-effect we care about: mark_read MUST be called
      # during conversation open with the open conversation and the current
      # user. `live_isolated/3` (like `live/2`) mounts the LV twice — once
      # for the disconnected static render, once for the connected socket —
      # so mark_read is called twice with identical args. We assert both
      # calls match the expected shape.
      stub_with(Foyer.ChatMock, RoomWithMessages)

      maya = Fixtures.maya()
      conversation = Fixtures.direct_maya_charlotte()

      Foyer.ChatMock
      |> expect(:mark_read, 2, fn ^conversation, ^maya -> {:ok, 0} end)

      {:ok, _view, _html} =
        mount_isolated_chat(conn, maya,
          live_action: :show,
          conversation_id: conversation.id
        )
    end
  end

  describe "F.Chat.6 compose form submits message via the port" do
    test "submitting the compose form calls send_message/3 with the typed body",
         %{conn: conn} do
      stub_with(Foyer.ChatMock, RoomWithMessages)

      maya = Fixtures.maya()
      conversation = Fixtures.direct_maya_charlotte()
      body = "Fresh towels are staged."

      {:ok, view, _html} =
        mount_isolated_chat(conn, maya,
          live_action: :show,
          conversation_id: conversation.id
        )

      Mox.allow(Foyer.ChatMock, self(), view.pid)

      # Pin the exact side effect: the form submit MUST call send_message/3
      # on the port with the conversation, user, and attrs holding the body.
      Foyer.ChatMock
      |> expect(:send_message, fn conv, ^maya, %{"body" => ^body} = _attrs ->
        assert conv.id == conversation.id
        {:ok, Fixtures.direct_message(900, conversation.id, maya.id, body)}
      end)

      # send_message triggers a mark_read on the broadcast hop, but in
      # isolated mode the PubSub fan-out is process-local — allow zero or
      # more follow-up mark_read calls via the scenario stub.

      view
      |> form("#chat-compose", message: %{body: body})
      |> render_submit()

      assert_push_event(view, "clear-chat-compose", %{form_id: "chat-compose"})
    end
  end

  describe "F.Chat.10 picker open events redirect" do
    test "room appends incoming chat_message broadcasts", %{conn: conn} do
      stub_with(Foyer.ChatMock, RoomWithMessages)

      maya = Fixtures.maya()
      conversation = Fixtures.direct_maya_charlotte()

      {:ok, view, _html} =
        mount_isolated_chat(conn, maya,
          live_action: :show,
          conversation_id: conversation.id
        )

      Mox.allow(Foyer.ChatMock, self(), view.pid)

      message =
        Fixtures.direct_message(
          901,
          conversation.id,
          Fixtures.charlotte().id,
          "Turndown tray is staged."
        )

      send(view.pid, {:chat_message, message})

      assert render(view) =~ "Turndown tray is staged."
    end

    test "clicking a person triggers open_direct and redirects to /chat/<id>",
         %{conn: conn} do
      stub_with(Foyer.ChatMock, WithUnread)

      maya = Fixtures.maya()
      hugo = Fixtures.hugo()

      {:ok, view, _html} = mount_isolated_chat(conn, maya, live_action: :new_message)
      Mox.allow(Foyer.ChatMock, self(), view.pid)
      Mox.allow(Foyer.AccountsMock, self(), view.pid)

      Foyer.ChatMock
      |> expect(:open_direct, fn ^maya, %{id: hugo_id} ->
        assert hugo_id == hugo.id
        {:ok, Fixtures.direct_maya_charlotte()}
      end)

      assert {:error, {:live_redirect, %{to: to}}} =
               view
               |> element("#new-msg-person-#{hugo.id}")
               |> render_click()

      assert to == "/chat/50"
    end

    test "clicking a channel triggers open_channel and redirects to /chat/<id>",
         %{conn: conn} do
      stub_with(Foyer.ChatMock, WithUnread)

      maya = Fixtures.maya()
      floor_4 = Fixtures.floor_4()

      {:ok, view, _html} = mount_isolated_chat(conn, maya, live_action: :new_message)
      Mox.allow(Foyer.ChatMock, self(), view.pid)
      Mox.allow(Foyer.ChannelsMock, self(), view.pid)

      view
      |> element("#new-msg-tab-channels")
      |> render_click()

      assert has_element?(view, "#new-message-channels")
      refute has_element?(view, "#new-message-people")

      Foyer.ChatMock
      |> expect(:open_channel, fn ^maya, channel_id ->
        assert to_string(channel_id) == to_string(floor_4.id)
        {:ok, Fixtures.channel_floor_4()}
      end)

      assert {:error, {:live_redirect, %{to: to}}} =
               view
               |> element("#new-msg-channel-#{floor_4.id}")
               |> render_click()

      assert to == "/chat/60"
    end
  end

  describe "F.Chat.11 picker tags off-shift colleagues" do
    test "renders Off shift tag for the off-shift colleague and not for on-shift colleagues",
         %{conn: conn} do
      stub_with(Foyer.ChatMock, WithUnread)

      maya = Fixtures.maya()
      jamal = Fixtures.jamal()
      hugo = Fixtures.hugo()

      {:ok, view, _html} = mount_isolated_chat(conn, maya, live_action: :new_message)
      Mox.allow(Foyer.ChatMock, self(), view.pid)

      # Jamal is off-shift in the ShiftsScenarios.MayaCharlotteHugoOn scenario.
      assert has_element?(view, "#new-msg-person-#{jamal.id}", "Off shift")
      # Hugo is on-shift — must NOT carry the off-shift tag.
      refute view
             |> element("#new-msg-person-#{hugo.id}")
             |> render() =~ "Off shift"
    end

    test "direct room header renders 'On shift' when the other participant is on shift",
         %{conn: conn} do
      stub_with(Foyer.ChatMock, RoomWithMessages)

      maya = Fixtures.maya()
      conversation = Fixtures.direct_maya_charlotte()

      {:ok, view, _html} =
        mount_isolated_chat(conn, maya,
          live_action: :show,
          conversation_id: conversation.id
        )

      Mox.allow(Foyer.ChatMock, self(), view.pid)

      # Charlotte is on shift in MayaCharlotteHugoOn.
      assert has_element?(view, "#chat-room-shift-state", "On shift")
    end

    test "renders the off-shift delivery note when the other participant is off shift",
         %{conn: conn} do
      # Jamal is OFF in MayaCharlotteHugoOn. Build a Maya<->Jamal direct
      # conversation inline and stub the read side to return it. This pins the
      # `chat-delivery-note` :if branch in the room compose area.
      stub_with(Foyer.ChatMock, RoomWithMessages)

      maya = Fixtures.maya()
      jamal = Fixtures.jamal()

      conversation = %Conversation{
        id: 70,
        kind: :direct,
        direct_key: Conversation.direct_key([maya.id, jamal.id]),
        last_message_at: ~U[2026-05-25 08:14:00Z],
        participants: [
          %Participant{id: 300, conversation_id: 70, user_id: maya.id, user: maya},
          %Participant{id: 301, conversation_id: 70, user_id: jamal.id, user: jamal}
        ],
        messages: [],
        unread?: false,
        unread_count: 0
      }

      # live_isolated runs both the disconnected and connected mount, so
      # each load_conversation collaborator can be called twice. Use stub/3
      # (not expect/3) — we're verifying render output, not call counts.
      Mox.stub(Foyer.ChatMock, :get_conversation!, fn _id, ^maya -> conversation end)
      Mox.stub(Foyer.ChatMock, :list_messages, fn _conv -> [] end)
      Mox.stub(Foyer.ChatMock, :mark_read, fn _conv, ^maya -> {:ok, 0} end)

      {:ok, view, _html} =
        mount_isolated_chat(conn, maya, live_action: :show, conversation_id: conversation.id)

      Mox.allow(Foyer.ChatMock, self(), view.pid)

      # Header reflects the off-shift state, and the room compose pre-amble
      # shows the "We'll deliver this when they next clock in." note that
      # only renders for off-shift direct conversations.
      assert has_element?(view, "#chat-room-shift-state", "Off shift")
      assert render(view) =~ "deliver this when they next clock in."
      assert render(view) =~ "Jamal Mensah"
    end
  end

  # ---------------------------------------------------------------------------
  # F.Chat.10 — missing conversation rescue (Ecto.NoResultsError path)
  # ---------------------------------------------------------------------------

  describe "F.Chat.10 load_conversation/2 rescues missing conversations" do
    test "redirects to /chat with a flash when get_conversation!/2 raises NoResultsError",
         %{conn: conn} do
      stub_with(Foyer.ChatMock, RoomWithMessages)

      maya = Fixtures.maya()

      # Inline stub: there is no scenario module for the "not found" world.
      # live_isolated may run both the disconnected and connected mount, so
      # use stub/3 (not expect/3) — the rescue branch firing once is what
      # we care about, and the redirect short-circuits any second mount.
      Mox.stub(Foyer.ChatMock, :get_conversation!, fn _id, ^maya ->
        raise Ecto.NoResultsError, queryable: Conversation
      end)

      # mount_isolated_chat triggers handle_params which calls load_conversation
      # which rescues and push_navigates back to /chat — live_isolated surfaces
      # this as an :error {:live_redirect, _} tuple.
      assert {:error, {:live_redirect, %{to: "/chat"}}} =
               mount_isolated_chat(conn, maya, live_action: :show, conversation_id: 999)
    end
  end

  # ---------------------------------------------------------------------------
  # F.Chat.6 — compose form error branches
  # ---------------------------------------------------------------------------

  describe "F.Chat.6 send_message error paths" do
    test "renders an error flash when the port returns :unauthorized or a changeset error",
         %{conn: conn} do
      stub_with(Foyer.ChatMock, RoomWithMessages)

      maya = Fixtures.maya()
      conversation = Fixtures.direct_maya_charlotte()

      {:ok, view, _html} =
        mount_isolated_chat(conn, maya,
          live_action: :show,
          conversation_id: conversation.id
        )

      Mox.allow(Foyer.ChatMock, self(), view.pid)

      Foyer.ChatMock
      |> expect(:send_message, fn _conv, ^maya, _attrs -> {:error, :unauthorized} end)

      html =
        view
        |> form("#chat-compose", message: %{body: "first"})
        |> render_submit()

      assert html =~ "You are not a member of that conversation."

      Foyer.ChatMock
      |> expect(:send_message, fn _conv, ^maya, _attrs ->
        {:error, Chat.compose_changeset(%{})}
      end)

      html =
        view
        |> form("#chat-compose", message: %{body: "second"})
        |> render_submit()

      assert html =~ "Couldn&#39;t send message."
    end
  end

  # ---------------------------------------------------------------------------
  # F.Chat.10 — open_direct / open_channel error branches in handle_event
  # ---------------------------------------------------------------------------

  describe "F.Chat.10 picker error branches surface flashes" do
    test "open_direct surfaces flashes for :invalid_direct and changeset errors",
         %{conn: conn} do
      # WithUnread.open_direct returns {:error, :invalid_direct} when
      # user_a.id == user_b.id, so clicking Maya from Maya's own picker
      # exercises the invalid_direct branch without an inline expect.
      # A second click against Hugo is layered with an explicit changeset
      # error to pin the generic flash branch.
      stub_with(Foyer.ChatMock, WithUnread)

      maya = Fixtures.maya()
      hugo = Fixtures.hugo()

      {:ok, view, _html} = mount_isolated_chat(conn, maya, live_action: :new_message)
      Mox.allow(Foyer.ChatMock, self(), view.pid)
      Mox.allow(Foyer.AccountsMock, self(), view.pid)

      html =
        view
        |> element("#new-msg-person-#{maya.id}")
        |> render_click()

      assert html =~ "Choose a colleague to start a direct message."

      Foyer.ChatMock
      |> expect(:open_direct, fn ^maya, _colleague ->
        {:error, Chat.compose_changeset(%{})}
      end)

      html =
        view
        |> element("#new-msg-person-#{hugo.id}")
        |> render_click()

      assert html =~ "Couldn&#39;t open that conversation."
    end

    test "open_channel surfaces flashes for :unauthorized and changeset errors",
         %{conn: conn} do
      stub_with(Foyer.ChatMock, WithUnread)

      maya = Fixtures.maya()
      floor_4 = Fixtures.floor_4()

      {:ok, view, _html} = mount_isolated_chat(conn, maya, live_action: :new_message)
      Mox.allow(Foyer.ChatMock, self(), view.pid)
      Mox.allow(Foyer.ChannelsMock, self(), view.pid)

      view |> element("#new-msg-tab-channels") |> render_click()

      Foyer.ChatMock
      |> expect(:open_channel, fn ^maya, _channel_id -> {:error, :unauthorized} end)

      html =
        view
        |> element("#new-msg-channel-#{floor_4.id}")
        |> render_click()

      assert html =~ "That channel is not available to you."

      Foyer.ChatMock
      |> expect(:open_channel, fn ^maya, _channel_id ->
        {:error, Chat.compose_changeset(%{})}
      end)

      html =
        view
        |> element("#new-msg-channel-#{floor_4.id}")
        |> render_click()

      assert html =~ "Couldn&#39;t open that channel."
    end
  end

  # ---------------------------------------------------------------------------
  # F.Chat.4 — channel_id URL param error branches in apply_new_message_params
  # ---------------------------------------------------------------------------

  describe "F.Chat.4 /chat/new?channel_id=... unauthorized + error paths" do
    test "unauthorized channel_id URL param redirects to /chat with an error flash",
         %{conn: _conn} do
      # apply_new_message_params/2 reads params["channel_id"] and calls
      # open_channel/2 on the port. The IsolatedChatLive harness does not
      # plumb arbitrary params into handle_params, so we drive
      # ChatLive.handle_params/3 directly with a hand-built socket. This
      # pins the two error branches (446-450 unauthorized, 452-456 changeset).
      maya = Fixtures.maya()
      scope = FoyerWeb.IsolatedHelpers.scope_for(maya, true)

      socket = %Phoenix.LiveView.Socket{
        assigns: %{__changed__: %{}, current_scope: scope, live_action: :new_message, flash: %{}}
      }

      Foyer.ChatMock
      |> expect(:open_channel, fn ^maya, "999" -> {:error, :unauthorized} end)

      assert {:noreply, socket_after} =
               FoyerWeb.ChatLive.handle_params(%{"channel_id" => "999"}, "/chat/new", socket)

      assert socket_after.assigns.flash["error"] == "That channel is not available to you."

      Foyer.ChatMock
      |> expect(:open_channel, fn ^maya, "888" ->
        {:error, Chat.compose_changeset(%{})}
      end)

      assert {:noreply, socket_after} =
               FoyerWeb.ChatLive.handle_params(%{"channel_id" => "888"}, "/chat/new", socket)

      assert socket_after.assigns.flash["error"] == "Couldn't open that channel."
    end
  end

  # ---------------------------------------------------------------------------
  # F.Chat.8 / F.Chat.10 — PubSub handle_info paths
  # ---------------------------------------------------------------------------

  describe "F.Chat.8 / F.Chat.10 PubSub handle_info" do
    test "stale chat_message ignored and chat_inbox_updated only refreshes unread off-inbox",
         %{conn: conn} do
      stub_with(Foyer.ChatMock, RoomWithMessages)

      maya = Fixtures.maya()
      conversation = Fixtures.direct_maya_charlotte()

      {:ok, view, _html} =
        mount_isolated_chat(conn, maya, live_action: :show, conversation_id: conversation.id)

      Mox.allow(Foyer.ChatMock, self(), view.pid)

      # Message belongs to a *different* conversation — the else branch of
      # handle_info({:chat_message, ...}) must drop it without touching the
      # stream or calling mark_read.
      stray =
        Fixtures.direct_message(902, conversation.id + 999, Fixtures.charlotte().id, "elsewhere")

      send(view.pid, {:chat_message, stray})
      refute render(view) =~ "elsewhere"

      # chat_inbox_updated arrives while on the room panel — refresh_inbox
      # hits the else-branch (not on :inbox) and only updates @unread_count.
      stub_with(Foyer.ChatMock, WithUnread)
      send(view.pid, {:chat_inbox_updated, conversation.id})
      assert has_element?(view, "#bottom-nav-chat-unread-dot")

      # Unknown handle_info clause — the catch-all clause keeps the LV alive.
      send(view.pid, :unrelated_message)
      assert Process.alive?(view.pid)
    end

    test "chat_inbox_updated refreshes the inbox stream when viewing the inbox panel",
         %{conn: conn} do
      maya = Fixtures.maya()

      # Start in an empty inbox so we can verify the refresh hydrates new
      # rows when the broadcast arrives — pinning both refresh_inbox
      # branches in one mount (here: live_action == :inbox).
      stub_with(Foyer.ChatMock, EmptyInbox)

      {:ok, view, _html} = mount_isolated_chat(conn, maya, live_action: :inbox)
      Mox.allow(Foyer.ChatMock, self(), view.pid)

      refute has_element?(view, "#conversation-row-50")
      refute has_element?(view, "#bottom-nav-chat-unread-dot")

      # Switch the scenario to WithUnread mid-flight so the next inbox_for/1
      # call inside refresh_inbox returns the populated conversation.
      stub_with(Foyer.ChatMock, WithUnread)

      send(view.pid, {:chat_inbox_updated, 50})

      assert has_element?(view, "#conversation-row-50")
      assert has_element?(view, "#bottom-nav-chat-unread-dot")

      # chat_unread_updated reuses the unread_count read and pins the
      # dedicated handle_info clause.
      send(view.pid, {:chat_unread_updated, maya.id})
      assert has_element?(view, "#bottom-nav-chat-unread-dot")
    end
  end
end
