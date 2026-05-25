defmodule FoyerWeb.DesktopSmokeTest do
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

    fixtures = seed_scaffold!()
    {:ok, fixtures}
  end

  describe "desktop side-rail presence" do
    test "Today renders desktop rail with correct nav IDs", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/today")

      assert has_element?(view, "#desktop-rail")
      assert has_element?(view, "#rail-nav-today[aria-current='page']")
      assert has_element?(view, "#rail-nav-house")
      assert has_element?(view, "#rail-nav-chat")
      assert has_element?(view, "#rail-nav-me")
    end

    test "House renders desktop rail with House active", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/house")

      assert has_element?(view, "#desktop-rail")
      assert has_element?(view, "#rail-nav-house[aria-current='page']")
    end

    test "Chat renders desktop rail with Chat active", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/chat")

      assert has_element?(view, "#desktop-rail")
      assert has_element?(view, "#rail-nav-chat[aria-current='page']")
    end

    test "Profile (/me) renders desktop rail with Me active", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/me")

      assert has_element?(view, "#desktop-rail")
      assert has_element?(view, "#rail-nav-me[aria-current='page']")
    end

    test "Rail disables House/Chat/Me for off-shift user", ctx do
      conn = sign_in(ctx.conn, ctx.jamal)
      {:ok, view, _html} = live(conn, ~p"/today")

      assert has_element?(view, "#rail-nav-house[disabled]")
      assert has_element?(view, "#rail-nav-chat[disabled]")
      assert has_element?(view, "#rail-nav-me[disabled]")
    end
  end

  describe "chat desktop panels" do
    test "chat inbox includes both inbox and room panel elements", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/chat")

      assert has_element?(view, "#chat-panel-inbox")
      assert has_element?(view, "#chat-panel-room")
    end

    test "off-shift banner absent in room when other participant is on shift", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/chat/#{ctx.maya_charlotte.id}")
      # Charlotte is on shift in fixtures; banner should not appear.
      refute has_element?(view, "#off-shift-banner")
    end

    test "direct load of chat room populates inbox panel with the conversation", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/chat/#{ctx.maya_charlotte.id}")
      # The dual-load in load_conversation/2 ensures conversations are streamed
      # even on a direct room load, so the inbox panel is not empty. Asserting
      # only on the container ID would pass even if the stream were empty, so we
      # pin to the seeded conversation's dom_id (`conv-<id>`). If a future edit
      # removes the inbox load from load_conversation/2, this test must fail.
      assert has_element?(view, "#chat-panel-inbox")
      assert has_element?(view, "#inbox #conv-#{ctx.maya_charlotte.id}")
    end
  end

  describe "compose render-only gate" do
    test "staff visiting /announcements/new is redirected, no form renders", ctx do
      conn = sign_in(ctx.conn, ctx.maya)

      # Maya is staff. The Announcements feature group (F.Announcements.2)
      # redirects staff at apply_new/1 with a flash — the form is never
      # rendered. A hand-crafted phx-submit cannot reach handle_event/3
      # because the LiveView is never mounted in the show state.
      assert {:error, {:live_redirect, %{to: "/house"}}} =
               live(conn, ~p"/announcements/new")
    end

    test "manager visiting /announcements/new sees the form", ctx do
      conn = sign_in(ctx.conn, ctx.charlotte)
      {:ok, view, _html} = live(conn, ~p"/announcements/new")

      refute has_element?(view, "#compose-gated")
      assert has_element?(view, "#announcement-new-form")
    end
  end

  describe "desktop rail — sign-out CSRF" do
    test "rail sign-out link carries a CSRF token (Phoenix `<.link method='delete'>`)", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, _view, html} = live(conn, ~p"/today")

      # Phoenix `<.link method="delete" href={...}>` emits an <a> with
      # data-method="delete", data-csrf="<token>", data-to="/session". The
      # phoenix_html JS converts the click into a CSRF-protected POST. If a
      # future edit drops the `method="delete"`, the data-csrf disappears and
      # an unauthenticated sign-out becomes possible — this test pins it.
      # Phoenix's link emits attributes in the order: href, data-method,
      # data-csrf, data-to, ..., id="rail-sign-out".
      sign_out_anchor =
        ~r/<a[^>]*data-method="delete"[^>]*data-csrf="[^"]+"[^>]*data-to="\/session"[^>]*id="rail-sign-out"/

      assert Regex.match?(sign_out_anchor, html),
             "expected #rail-sign-out anchor with data-method='delete' and data-csrf to be present"
    end
  end

  describe "ack badges — preload" do
    test "ack badges render the acking user's initials (not '??')", ctx do
      # Acknowledge an announcement so it has at least one ack with a user.
      ann_id = create_acked_announcement(ctx)

      conn = sign_in(ctx.conn, ctx.charlotte)
      {:ok, view, _html} = live(conn, ~p"/announcements/#{ann_id}")

      # If get_announcement!/2 stops preloading `acks: :user`, ack_initials/1
      # falls back to "??" and this assertion fails.
      assert has_element?(view, "#ack-badge-#{ctx.maya.id}")
      refute render(view) =~ ">?? ✓"
    end
  end

  # Helper: insert an announcement requiring ack on the floor_4 channel,
  # then have Maya acknowledge it. Returns the announcement id.
  defp create_acked_announcement(ctx) do
    floor_4 =
      Foyer.Channels.list_for_user(ctx.charlotte)
      |> Enum.find(fn c -> c.slug == "housekeeping-floor-4" end)

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

    {:ok, _} = Foyer.House.acknowledge(announcement, ctx.maya)
    announcement.id
  end
end
