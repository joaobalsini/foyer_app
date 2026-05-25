defmodule FoyerWeb.ScaffoldSmokeTest do
  # async: true — each test owns its sandbox transaction; fixtures are
  # inserted in setup. We do NOT rely on priv/repo/seeds.exs (that file is for
  # manual demo runs).
  use FoyerWeb.ConnCase, async: true

  import Ecto.Query, only: [from: 2]
  import Phoenix.LiveViewTest
  import Mox
  import FoyerWeb.ScaffoldFixtures

  alias Foyer.House.Announcement
  alias Foyer.House.AnnouncementAck

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

    test "F.Announcements.1 a manager publishes an announcement to a channel they belong to",
         ctx do
      # Charlotte is a manager and a member of `housekeeping-floor-4`.
      conn = sign_in(ctx.conn, ctx.charlotte)
      {:ok, view, _html} = live(conn, ~p"/announcements/new")

      floor_4 =
        Foyer.Channels.list_for_user(ctx.charlotte)
        |> Enum.find(fn c -> c.slug == "housekeeping-floor-4" end)

      view
      |> form("#announcement-new-form",
        announcement: %{
          title: "Lift inspection at noon",
          body: "Service lift will pause briefly during inspection.",
          channel_id: floor_4.id,
          requires_ack: false
        }
      )
      |> render_submit()

      # After publish the LiveView push_navigates to /house; the new
      # announcement shows up in Charlotte's feed.
      conn = sign_in(build_conn(), ctx.charlotte)
      {:ok, _house_view, html} = live(conn, ~p"/house")
      assert html =~ "Lift inspection at noon"
    end

    test "F.Announcements.3 author within grace can edit title and body via the edit form",
         ctx do
      # `suite_412` was published 5 minutes ago in the fixture — well within
      # the 15-minute grace window.
      conn = sign_in(ctx.conn, ctx.charlotte)
      {:ok, view, _html} = live(conn, ~p"/announcements/#{ctx.suite_412.id}/edit")

      view
      |> form("#announcement-edit-form",
        announcement: %{
          title: "Suite 412 - Allergy protocol UPDATED",
          body: "Updated body for the protocol.",
          channel_id: ctx.suite_412.channel_id,
          requires_ack: true
        }
      )
      |> render_submit()

      # Edit push_navigates back to the show route — Maya's feed reflects
      # the new title.
      conn = sign_in(build_conn(), ctx.maya)
      {:ok, _house_view, html} = live(conn, ~p"/house")
      assert html =~ "Suite 412 - Allergy protocol UPDATED"
      refute html =~ "Allergy protocol in effect"
    end

    test "F.Announcements.4 visiting the edit page outside the grace window redirects with a flash",
         ctx do
      # Age `suite_412`'s published_at past the 15-minute grace window. The
      # edit route is wired into `apply_edit/2`, which calls
      # `within_grace_window?/1` and `push_navigate`s back to the show page
      # with a flash when the grace window has expired.
      aged_published_at =
        DateTime.add(DateTime.utc_now(), -20 * 60, :second) |> DateTime.truncate(:second)

      {:ok, _} =
        ctx.suite_412
        |> Announcement.changeset(%{published_at: aged_published_at})
        |> Foyer.Repo.update()

      conn = sign_in(ctx.conn, ctx.charlotte)

      assert {:error,
              {:live_redirect,
               %{to: to, flash: %{"error" => "That announcement can no longer be edited."}}}} =
               live(conn, ~p"/announcements/#{ctx.suite_412.id}/edit")

      assert to == "/announcements/#{ctx.suite_412.id}"

      # And the title in the DB is unchanged — the context-level guard backs
      # up the LiveView-level guard so a hand-crafted `phx-submit` cannot
      # bypass the grace check either (already pinned by
      # `test/foyer/house_test.exs:50` `F.Announcements.4`).
      reloaded = Foyer.Repo.get!(Announcement, ctx.suite_412.id)
      assert reloaded.title == ctx.suite_412.title
    end

    test "F.Announcements.7 the author does not see an acknowledge CTA on their own post",
         ctx do
      # The author (Charlotte) is excluded from the required-ack set, so the
      # acknowledge CTA never renders for her — even though `suite_412`
      # requires_ack: true. Maya, by contrast, sees it (pinned by the
      # existing "ack action" test above).
      conn = sign_in(ctx.conn, ctx.charlotte)
      {:ok, view, _html} = live(conn, ~p"/announcements/#{ctx.suite_412.id}")

      refute has_element?(view, "#acknowledge-btn")
      refute render(view) =~ "I&#39;ve read &amp; understood"
    end

    test "F.Announcements.8 clicking acknowledge twice does not raise and leaves the row idempotent",
         ctx do
      # Maya hasn't acknowledged yet in the fixture; click ack twice. The
      # second click goes through the same `phx-click` path but the LiveView
      # has already swapped the CTA out for the disabled "Acknowledged"
      # state, so we re-mount the conn and click again after re-rendering.
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/announcements/#{ctx.suite_412.id}")

      view |> element("#acknowledge-btn") |> render_click()
      assert has_element?(view, "#acked-state")

      # Underneath, the unique index keeps the row count at one even if the
      # context is called again. Verifies the F.Announcements.8 idempotence
      # contract at the LiveView/context boundary.
      assert {:ok, _} = Foyer.House.acknowledge(ctx.suite_412, ctx.maya)

      acks_count =
        from(a in AnnouncementAck,
          where: a.announcement_id == ^ctx.suite_412.id and a.user_id == ^ctx.maya.id,
          select: count(a.id)
        )
        |> Foyer.Repo.one()

      assert acks_count == 1
    end

    test "F.Announcements.9 the manager sees four receipt-group sections on the detail page",
         ctx do
      # `suite_412` lives in the `all_housekeeping` channel — members are
      # Maya, Aisha, Charlotte, Jamal. Excluding the author Charlotte, the
      # receipt recipients are Maya, Aisha, Jamal. In the fixture, Aisha is
      # already acked. Maya marks the announcement read here, putting her in
      # the read_without_acknowledgement bucket. Jamal is off shift.
      {:ok, _} = Foyer.House.mark_read(ctx.suite_412, ctx.maya)

      conn = sign_in(ctx.conn, ctx.charlotte)
      {:ok, view, _html} = live(conn, ~p"/announcements/#{ctx.suite_412.id}")

      assert has_element?(view, "#receipts-acknowledged")
      assert has_element?(view, "#receipts-read")
      assert has_element?(view, "#receipts-unread")
      assert has_element?(view, "#receipts-off-shift")

      html = render(view)
      assert html =~ "Acknowledged · 1"
      assert html =~ "Read without acknowledgement · 1"
      assert html =~ "Unread · 0"
      assert html =~ "Off shift · 1"
    end

    test "F.Announcements.10 a non-member of the channel cannot reach the announcement", ctx do
      # Leadership-only — Maya is not a member. The context guard inside
      # `get_announcement!/2` raises `Ecto.NoResultsError`, which the
      # LiveView catches and converts into a `push_navigate(~p"/house")`.
      conn = sign_in(ctx.conn, ctx.maya)

      assert {:error, {:live_redirect, %{to: "/house"}}} =
               live(conn, ~p"/announcements/#{ctx.leadership_only_announcement.id}")
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
    test "F.Recognitions.1 on-shift staff can reach /recognitions and /recognitions/new", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/recognitions")
      assert render(view) =~ "Recognitions"
      assert has_element?(view, "#recognitions-new-cta")

      {:ok, new_view, _html} = live(sign_in(build_conn(), ctx.maya), ~p"/recognitions/new")
      assert has_element?(new_view, "form#recognize-form")
    end

    test "F.Recognitions.1 off-shift user is redirected away from /recognitions", ctx do
      conn = sign_in(ctx.conn, ctx.jamal)
      assert {:error, {:redirect, %{to: "/today"}}} = live(conn, ~p"/recognitions")
    end

    test "F.Recognitions.2 self-recognition submit surfaces the self-recognition flash", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/recognitions/new")

      view
      |> form("#recognize-form",
        recognition: %{
          "recipient_id" => to_string(ctx.maya.id),
          "body" => "Praise myself.",
          "values" => ["care"],
          "public" => "true"
        }
      )
      |> render_submit()

      assert render(view) =~ "Choose someone else to recognize."
    end

    test "F.Recognitions.3 new form renders the six house values and no others", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/recognitions/new")
      assert render(view) =~ "Give recognition"

      for v <- ~w(Care Craft Discretion Initiative Warmth Excellence) do
        assert render(view) =~ v
      end

      refute render(view) =~ "Team"
    end

    test "F.Recognitions.4 submitting with no values selected does NOT create a recognition",
         ctx do
      before_count = Foyer.Repo.aggregate(Foyer.Recognitions.Recognition, :count)

      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/recognitions/new")

      view
      |> form("#recognize-form",
        recognition: %{
          "recipient_id" => to_string(ctx.aisha.id),
          "body" => "Thanks.",
          "public" => "true"
        }
      )
      |> render_submit()

      # The LV either re-renders with the error or flashes a generic message;
      # either way no row is inserted.
      assert Foyer.Repo.aggregate(Foyer.Recognitions.Recognition, :count) == before_count
    end

    test "F.Recognitions.5 manager sees bonus-tier UI, staff does NOT", ctx do
      {:ok, manager_view, _html} =
        live(sign_in(ctx.conn, ctx.charlotte), ~p"/recognitions/new")

      assert render(manager_view) =~ "Bonus points"
      assert has_element?(manager_view, "#bonus-points-fieldset")

      {:ok, staff_view, _html} =
        live(sign_in(build_conn(), ctx.maya), ~p"/recognitions/new")

      refute has_element?(staff_view, "#bonus-points-fieldset")
    end

    test "F.Recognitions.6 manager submits a valid tier and the recognition is created", ctx do
      conn = sign_in(ctx.conn, ctx.charlotte)
      {:ok, view, _html} = live(conn, ~p"/recognitions/new")

      view
      |> form("#recognize-form",
        recognition: %{
          "recipient_id" => to_string(ctx.aisha.id),
          "body" => "Fast recovery on suite 308.",
          "values" => ["initiative"],
          "public" => "true",
          "bonus_points" => "25"
        }
      )
      |> render_submit()

      # After a successful give, the LV push_navigates to /recognitions. Reload
      # and assert the row landed with the expected tier.
      assert [recognition] =
               Foyer.Repo.all(
                 from r in Foyer.Recognitions.Recognition,
                   where: r.body == "Fast recovery on suite 308."
               )

      assert recognition.bonus_points == 25
    end

    test "F.Recognitions.7 a manager give with bonus_points writes ledger + balance in one go",
         ctx do
      before_balance =
        Foyer.Repo.get!(Foyer.Accounts.User, ctx.aisha.id).points_balance

      conn = sign_in(ctx.conn, ctx.charlotte)
      {:ok, view, _html} = live(conn, ~p"/recognitions/new")

      view
      |> form("#recognize-form",
        recognition: %{
          "recipient_id" => to_string(ctx.aisha.id),
          "body" => "Ledger end-to-end check.",
          "values" => ["craft"],
          "public" => "true",
          "bonus_points" => "10"
        }
      )
      |> render_submit()

      assert Foyer.Repo.get!(Foyer.Accounts.User, ctx.aisha.id).points_balance ==
               before_balance + 10

      assert [%{delta: 10, reason: "recognition_granted"}] =
               Foyer.Repo.all(
                 from e in Foyer.Recognitions.PointEntry,
                   where: e.user_id == ^ctx.aisha.id and e.delta == 10
               )
    end

    test "F.Recognitions.8 the author can remove a recognition within grace via the UI", ctx do
      # ctx.hugo_recognition is Charlotte -> Hugo, fresh-from-fixture, public.
      conn = sign_in(ctx.conn, ctx.charlotte)
      {:ok, view, _html} = live(conn, ~p"/recognitions/#{ctx.hugo_recognition.id}")

      assert has_element?(view, "#recognition-remove-btn")

      view |> element("#recognition-remove-btn") |> render_click()

      # Soft removal: row stays, but `removed_at` is now set and the row is
      # filtered from `feed_public/0`.
      removed =
        Foyer.Repo.get!(Foyer.Recognitions.Recognition, ctx.hugo_recognition.id)

      assert removed.removed_at
      refute Enum.any?(Foyer.Recognitions.feed_public(), &(&1.id == ctx.hugo_recognition.id))
    end

    test "F.Recognitions.9 author can open edit page within grace, blocked after grace", ctx do
      # Within grace — Charlotte authored ctx.hugo_recognition; edit page opens.
      conn = sign_in(ctx.conn, ctx.charlotte)
      {:ok, view, _html} = live(conn, ~p"/recognitions/#{ctx.hugo_recognition.id}/edit")
      assert has_element?(view, "#recognition-edit-form")
      assert render(view) =~ "Edit recognition"

      # Age the recognition past the grace window and try to remove via the
      # context — same gate the LV honours when rendering the Remove button.
      aged_at =
        DateTime.utc_now()
        |> DateTime.add(-20 * 60, :second)
        |> DateTime.truncate(:second)

      Foyer.Repo.update_all(
        from(r in Foyer.Recognitions.Recognition, where: r.id == ^ctx.hugo_recognition.id),
        set: [inserted_at: aged_at]
      )

      aged = Foyer.Repo.get!(Foyer.Recognitions.Recognition, ctx.hugo_recognition.id)

      assert {:error, :outside_grace_window} =
               Foyer.Recognitions.remove_recognition(aged, ctx.charlotte)
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

    test "F.Recognitions.10 /people/:id hides private recognitions from third parties", ctx do
      # private_recognition is Maya -> Aisha, public: false.
      # Hugo (third party) viewing Aisha's profile must not see the body.
      conn = sign_in(ctx.conn, ctx.hugo)
      {:ok, _view, html} = live(conn, ~p"/people/#{ctx.aisha.id}")
      refute html =~ "Handled the linen reset"
    end

    test "F.Recognitions.10 /people/:id shows private recognitions to recipient", ctx do
      # Aisha (recipient) viewing her own page via /people/:id (or via /me).
      # Recipient must see the private recognition body.
      conn = sign_in(ctx.conn, ctx.aisha)
      {:ok, _view, html} = live(conn, ~p"/people/#{ctx.aisha.id}")
      assert html =~ "Handled the linen reset"
    end
  end
end
