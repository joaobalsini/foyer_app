defmodule FoyerWeb.ChatLiveTest do
  use FoyerWeb.ConnCase, async: true

  import FoyerWeb.ScaffoldFixtures
  import Mox
  import Phoenix.LiveViewTest

  alias Foyer.Channels.Channel
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

  test "F.Chat.10 picker opens direct conversations and marks off-shift colleagues", ctx do
    conn = sign_in(ctx.conn, ctx.maya)
    {:ok, view, _html} = live(conn, ~p"/chat/new")

    assert has_element?(view, "#new-msg-person-#{ctx.jamal.id}", "Off shift")

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

  test "F.Chat.6/F.Chat.10 room sends and streams messages", ctx do
    conn = sign_in(ctx.conn, ctx.maya)
    {:ok, view, _html} = live(conn, ~p"/chat/#{ctx.maya_charlotte.id}")

    assert has_element?(view, "#chat-room-shift-state", "On shift")

    view
    |> form("#chat-compose", message: %{body: "Fresh towels are staged."})
    |> render_submit()

    assert render(view) =~ "Fresh towels are staged."
  end

  test "F.Chat.9 bottom nav renders unread dot for unread inbox state", ctx do
    conn = sign_in(ctx.conn, ctx.maya)
    {:ok, view, _html} = live(conn, ~p"/chat")

    assert has_element?(view, "#conversation-unread-#{ctx.maya_charlotte.id}")
    assert has_element?(view, "#bottom-nav-chat-unread-dot")
  end
end
