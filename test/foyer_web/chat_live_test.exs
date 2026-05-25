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
  """
  use FoyerWeb.ConnCase, async: true

  import FoyerWeb.IsolatedHelpers
  import Mox
  import Phoenix.LiveViewTest

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
    :ok
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
  end
end
