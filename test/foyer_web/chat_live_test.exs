defmodule FoyerWeb.ChatLiveTest do
  @moduledoc """
  Route smoke tests for `FoyerWeb.ChatLive`. Per `docs/TESTING_GUIDE.md`,
  these are the wiring layer: they use the real router, plugs, on-mount
  hooks, and seeded database to prove the app boots and the surface
  renders. UI-state behaviour lives in `chat_live_isolated_test.exs`.

  Each test pins at least one `F.Chat.<N>` clause where the behaviour is
  externally observable from the surface. Clauses that are only observable
  at the context layer (F.Chat.1, F.Chat.2, F.Chat.3, F.Chat.4) are pinned
  in `test/foyer/chat_test.exs` — see verify doc for the rationale.
  """
  use FoyerWeb.ConnCase, async: true

  import FoyerWeb.ScaffoldFixtures
  import Mox
  import Phoenix.LiveViewTest

  alias Foyer.Channels.Channel
  alias Foyer.Chat
  alias Foyer.Repo

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

  describe "wiring — inbox surface" do
    test "F.Chat.5 inbox does not render empty-conversation rows", ctx do
      # Open an empty DM in the seeded DB — it must NOT appear in the inbox.
      {:ok, empty_dm} = Chat.open_direct(ctx.maya, ctx.hugo)

      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/chat")

      # The seeded maya↔charlotte conversation has messages → row present.
      assert has_element?(view, "#conv-#{ctx.maya_charlotte.id}")
      # The freshly opened DM has no messages → row absent.
      refute has_element?(view, "#conv-#{empty_dm.id}")
    end

    test "F.Chat.8/F.Chat.9 inbox renders unread dot and bottom-nav unread dot for unread state",
         ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/chat")

      assert has_element?(view, "#conversation-unread-#{ctx.maya_charlotte.id}")
      assert has_element?(view, "#bottom-nav-chat-unread-dot")
    end
  end

  describe "wiring — picker surface" do
    test "F.Chat.10/F.Chat.11 picker renders people and channels and tags off-shift", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/chat/new")

      # F.Chat.11 — Jamal is off shift in the fixtures.
      assert has_element?(view, "#new-msg-person-#{ctx.jamal.id}", "Off shift")

      # F.Chat.10 — clicking a person opens (or creates) the conversation and
      # redirects to /chat/:id.
      assert {:error, {:live_redirect, %{to: to}}} =
               view
               |> element("#new-msg-person-#{ctx.hugo.id}")
               |> render_click()

      assert to =~ ~r"/chat/\d+"
    end

    test "F.Chat.10 picker opens channel conversations", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/chat/new")
      floor_4 = Repo.get_by!(Channel, name: "Housekeeping · Floor 4")

      assert {:error, {:live_redirect, %{to: to}}} =
               view
               |> element("#new-msg-channel-#{floor_4.id}")
               |> render_click()

      assert to =~ ~r"/chat/\d+"
    end
  end

  describe "wiring — room surface" do
    test "F.Chat.6/F.Chat.10 room sends and streams messages, header shows shift state", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/chat/#{ctx.maya_charlotte.id}")

      # F.Chat.11 — header shows the other participant's shift state.
      assert has_element?(view, "#chat-room-shift-state", "On shift")

      view
      |> form("#chat-compose", message: %{body: "Fresh towels are staged."})
      |> render_submit()

      assert render(view) =~ "Fresh towels are staged."
    end

    test "F.Chat.7 opening a room clears that user's unread state via mark_read", ctx do
      # Pre-condition: Charlotte's seeded message is unread for Maya.
      assert Chat.unread_count(ctx.maya) == 1

      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, _view, _html} = live(conn, ~p"/chat/#{ctx.maya_charlotte.id}")

      # mark_read/2 fires during load_conversation/2 → unread count drops to 0.
      assert Chat.unread_count(ctx.maya) == 0
    end
  end
end
