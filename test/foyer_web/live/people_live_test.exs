defmodule FoyerWeb.PeopleLiveTest do
  @moduledoc """
  Isolated tests for `FoyerWeb.PeopleLive`.

  Covers:
    F.Channels.22 — Profile.Card must not expose channel memberships
    F.Profile.6  — private recognitions hidden on colleague profile view
    F.Profile.8  — Given section absent on colleague's profile
    F.Profile.19 — colleague profile reuses profile_card, rewards hidden
  """
  use ExUnit.Case, async: true

  @endpoint FoyerWeb.Endpoint

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Mox
  import FoyerWeb.IsolatedHelpers

  alias Foyer.ProfileScenarios

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    {:ok, conn: build_conn()}
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

  describe "F.Profile.8 — Given section absent on colleague view" do
    setup do
      stub(Foyer.AccountsMock, :get_user!, fn _id ->
        ProfileScenarios.user_maya()
      end)

      stub(Foyer.ProfileMock, :profile_for, fn _subject, _viewer ->
        %Foyer.Profile.Card{
          user: ProfileScenarios.user_maya(),
          received: [ProfileScenarios.recognition_public()],
          given: [],
          points: 245,
          on_shift?: true,
          received_this_month: 1,
          points_earned: []
        }
      end)

      stub(Foyer.ChannelsMock, :list_for_user, fn _user -> [] end)

      :ok
    end

    test "does not render the recognitions-given section", %{conn: conn} do
      viewer = ProfileScenarios.user_charlotte()
      subject_id = ProfileScenarios.user_maya().id

      {:ok, view, _html} = mount_isolated_people_show(conn, viewer, subject_id)

      refute has_element?(view, "#recognitions-given")
    end

    test "F.Profile.19 — rewards catalog absent on colleague view", %{conn: conn} do
      viewer = ProfileScenarios.user_charlotte()
      subject_id = ProfileScenarios.user_maya().id

      {:ok, view, _html} = mount_isolated_people_show(conn, viewer, subject_id)

      refute has_element?(view, "#rewards")
    end

    test "F.Profile.6 — only public recognitions visible in received section", %{conn: conn} do
      viewer = ProfileScenarios.user_charlotte()
      subject_id = ProfileScenarios.user_maya().id

      {:ok, view, _html} = mount_isolated_people_show(conn, viewer, subject_id)

      html = render(view)
      assert html =~ "Quietly handled a 02:14 guest issue"
      refute html =~ "Private: handled a sensitive situation"
    end
  end

  describe "F.Profile.19 — colleague profile reuses profile_card component" do
    setup do
      stub(Foyer.AccountsMock, :get_user!, fn _id ->
        ProfileScenarios.user_maya()
      end)

      stub(Foyer.ProfileMock, :profile_for, fn _subject, _viewer ->
        %Foyer.Profile.Card{
          user: ProfileScenarios.user_maya(),
          received: [ProfileScenarios.recognition_public()],
          given: [],
          points: 245,
          on_shift?: true,
          received_this_month: 1,
          points_earned: []
        }
      end)

      stub(Foyer.ChannelsMock, :list_for_user, fn _user -> [] end)

      :ok
    end

    test "renders the colleague's name in the profile card", %{conn: conn} do
      viewer = ProfileScenarios.user_charlotte()
      subject_id = ProfileScenarios.user_maya().id

      {:ok, view, _html} = mount_isolated_people_show(conn, viewer, subject_id)

      assert render(view) =~ "Maya Okafor"
    end

    test "renders the received recognitions section", %{conn: conn} do
      viewer = ProfileScenarios.user_charlotte()
      subject_id = ProfileScenarios.user_maya().id

      {:ok, view, _html} = mount_isolated_people_show(conn, viewer, subject_id)

      assert has_element?(view, "#recognitions-received")
    end

    test "renders the on-shift tag for the colleague (on_shift? true)", %{conn: conn} do
      viewer = ProfileScenarios.user_charlotte()
      subject_id = ProfileScenarios.user_maya().id

      {:ok, view, _html} = mount_isolated_people_show(conn, viewer, subject_id)

      assert render(view) =~ "On shift"
    end
  end
end
