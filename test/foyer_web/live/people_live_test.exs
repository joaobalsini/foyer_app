defmodule FoyerWeb.PeopleLiveTest do
  @moduledoc """
  Isolated tests for `FoyerWeb.PeopleLive`.

  Covers:
    F.Channels.15 — People directory desktop list matches the design structure
    F.Channels.16 — on-shift status renders in the row status slot
    F.Channels.17 — Department filters come from channel counts; rows omit channel pills
    F.Channels.21 — Department and On shift filters prune the stream
    F.Channels.22 — Profile.Card must not expose channel memberships
    F.Profile.8  — staff cannot access another user's profile view
    F.Profile.19 — managers can open full profiles from People
  """
  use ExUnit.Case, async: true

  @endpoint FoyerWeb.Endpoint

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Mox
  import FoyerWeb.IsolatedHelpers

  alias Foyer.AccountsScenarios.WithPeople
  alias Foyer.ProfileScenarios
  alias Foyer.ProfileScenarios.LineStaff

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    {:ok, conn: build_conn()}
  end

  describe "F.Channels.15 / F.Channels.17 — desktop People directory design" do
    setup do
      stub_with(Foyer.AccountsMock, WithPeople)
      stub_with(Foyer.ChannelsMock, Foyer.ChannelsScenarios.TwoChannels)
      stub_with(Foyer.ShiftsMock, Foyer.ShiftsScenarios.WithOnShift)
      :ok
    end

    test "renders the design header, filter chips, rows, and explicit row actions", %{conn: conn} do
      viewer = ProfileScenarios.user_charlotte()

      {:ok, view, _html} = mount_isolated_people_index(conn, viewer)

      assert has_element?(view, ".people-directory.foyer-page-wide")
      assert has_element?(view, "#people-count", "3 colleagues · The Linden")
      assert has_element?(view, "#people-filters")
      assert has_element?(view, "#filter-department-menu")
      assert has_element?(view, "#filter-on-shift")
      assert has_element?(view, "#people-row-1")
      assert has_element?(view, "#people-identity-1")
      refute has_element?(view, "#people-profile-link-1")
      assert has_element?(view, "#people-self-2", "You")
      assert has_element?(view, "#view-profile-2", "Your profile")
      refute has_element?(view, "#message-colleague-2")
      assert has_element?(view, "#view-profile-1", "View profile")
      assert has_element?(view, "#message-colleague-1", "Message")
    end

    test "F.Channels.17 — department menu uses channel counts and rows omit channel pills",
         %{conn: conn} do
      viewer = ProfileScenarios.user_charlotte()

      {:ok, view, _html} = mount_isolated_people_index(conn, viewer)

      assert has_element?(view, "#filter-channel-101", "Housekeeping · Floor 4")
      assert has_element?(view, "#filter-channel-102", "All Housekeeping")
      refute has_element?(view, "#people-row-1 [id^='person-1-channel-']")
    end

    test "F.Profile.8 / F.Profile.19 — staff see View profile only for themselves",
         %{conn: conn} do
      viewer = WithPeople.people() |> Enum.find(&(&1.id == 2))

      {:ok, view, _html} = mount_isolated_people_index(conn, viewer)

      refute has_element?(view, "#view-profile-1")
      assert has_element?(view, "#view-profile-2", "Your profile")
      refute has_element?(view, "#view-profile-3")
      assert has_element?(view, "#people-self-2", "You")
      refute has_element?(view, "#message-colleague-2")
    end
  end

  describe "F.Channels.16 / F.Channels.21 — People directory filters" do
    setup do
      stub_with(Foyer.AccountsMock, WithPeople)
      stub_with(Foyer.ChannelsMock, Foyer.ChannelsScenarios.TwoChannels)
      stub_with(Foyer.ShiftsMock, Foyer.ShiftsScenarios.WithOnShift)
      :ok
    end

    test "F.Channels.16 — on-shift and off-shift statuses render in row status slots",
         %{conn: conn} do
      viewer = ProfileScenarios.user_charlotte()

      {:ok, view, _html} = mount_isolated_people_index(conn, viewer)

      assert has_element?(view, "#people-status-1", "On shift")
      assert has_element?(view, "#people-status-2", "Off shift")
    end

    test "F.Channels.21 — department filter narrows and All restores rows", %{conn: conn} do
      viewer = ProfileScenarios.user_charlotte()

      {:ok, view, _html} = mount_isolated_people_index(conn, viewer)

      assert has_element?(view, "#people-row-1")
      assert has_element?(view, "#people-row-2")

      view |> element("#filter-channel-101") |> render_click()

      assert has_element?(view, "#people-row-1")
      assert has_element?(view, "#people-row-3")
      refute has_element?(view, "#people-row-2")

      view |> element("#filter-all") |> render_click()
      assert has_element?(view, "#people-row-2")
    end

    test "F.Channels.21 — on-shift filter shows only users on shift", %{conn: conn} do
      viewer = ProfileScenarios.user_charlotte()

      {:ok, view, _html} = mount_isolated_people_index(conn, viewer)

      view |> element("#filter-on-shift") |> render_click()

      assert has_element?(view, "#people-row-1")
      assert has_element?(view, "#people-row-3")
      refute has_element?(view, "#people-row-2")
    end
  end

  describe "F.Channels.22 — channel memberships are NOT sourced from Profile.Card" do
    test "Foyer.Profile.Card struct has no :memberships field" do
      card_fields =
        Map.keys(%Foyer.Profile.Card{
          user: %Foyer.Accounts.User{
            name: "x",
            initials: "X",
            role: :staff,
            department: "X",
            title: "X"
          },
          received: [],
          given: [],
          points: 0,
          on_shift?: false,
          received_this_month: 0,
          points_earned: []
        })

      refute :memberships in card_fields,
             "Profile.Card must NOT have a :memberships field; channel memberships " <>
               "belong to PeopleLive :target_channels (F.Channels.22)"
    end
  end

  describe "F.Profile.8 — staff cannot access another user's profile view" do
    setup do
      stub(Foyer.AccountsMock, :get_user, fn _id ->
        ProfileScenarios.user_maya()
      end)

      :ok
    end

    test "redirects staff away from a colleague profile", %{conn: conn} do
      viewer = WithPeople.people() |> Enum.find(&(&1.id == 2))
      subject_id = ProfileScenarios.user_maya().id

      assert {:error, {:live_redirect, %{to: "/people"}}} =
               mount_isolated_people_show(conn, viewer, subject_id)
    end
  end

  describe "F.Profile.19 — managers can open full People profiles" do
    setup do
      stub(Foyer.AccountsMock, :get_user, fn _id ->
        ProfileScenarios.user_maya()
      end)

      stub(Foyer.ProfileMock, :own_profile_for, fn _subject ->
        LineStaff.own_profile_for(ProfileScenarios.user_maya())
      end)

      stub(Foyer.ChannelsMock, :list_for_user, fn _user -> [] end)

      :ok
    end

    test "renders the colleague's full profile card", %{conn: conn} do
      viewer = ProfileScenarios.user_charlotte()
      subject_id = ProfileScenarios.user_maya().id

      {:ok, view, _html} = mount_isolated_people_show(conn, viewer, subject_id)

      html = render(view)
      assert html =~ "Maya Okafor"
      assert has_element?(view, "#back-to-people[href='/people']", "Back to People")
      assert has_element?(view, "#people-profile-view.foyer-page-wide")
      assert has_element?(view, "#recognitions-received")
      assert has_element?(view, "#recognitions-given")
      refute has_element?(view, "#rewards")
      refute has_element?(view, "#profile-settings")
      assert html =~ "Private: handled a sensitive situation"
    end
  end
end
