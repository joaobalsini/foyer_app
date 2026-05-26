defmodule FoyerWeb.HouseLiveTest do
  @moduledoc """
  Isolated LiveView tests for `FoyerWeb.HouseLive` (`/house`) — the
  announcements + recognition feed surface.

  Uses `live_isolated/3` with `FoyerWeb.IsolatedHelpers.prepare_isolated/4`
  to mount the LiveView without the production router or `on_mount` hooks.
  Collaborators (`Foyer.HousePort`, `Foyer.RecognitionsPort`) are swapped
  per test via `Mox.stub_with/2` for the default world and per-call
  `Mox.stub/3` for tests that pin specific feed shapes (date branches,
  non-pinned items, …).

  Covers branches in `FoyerWeb.HouseLive` that aren't exercised by the
  default scenario world: the `:announcements` / `:recognition` filter
  param branches, `handle_event("filter", …)`, the manager-only Compose
  CTA, the non-pinned-announcement `feed_entry` mapping, and the
  `day_group_label/1` branches (Yesterday, this week, older).

  Reference clauses (House is the feed surface for Announcements):
    F.Announcements.2 — manager-only Compose affordance
    F.Announcements.5 — pinned vs non-pinned feed rendering
  """
  use ExUnit.Case, async: true

  @endpoint FoyerWeb.Endpoint

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Mox

  alias Foyer.HouseScenarios
  alias Foyer.HouseScenarios.Fixtures
  alias Foyer.RecognitionsScenarios
  alias FoyerWeb.IsolatedHelpers

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    # Default world: empty feeds. Tests override per-call when they need a
    # specific feed shape (e.g. an announcement from N days ago).
    stub_with(Foyer.HouseMock, HouseScenarios.Empty)
    stub_with(Foyer.RecognitionsMock, RecognitionsScenarios.Empty)
    {:ok, conn: build_conn()}
  end

  # ---------------------------------------------------------------------------
  # F.Announcements.2 — manager-only Compose CTA on /house
  # Covers lines 102, 107 (manager compose link) and the matching staff branch.
  # ---------------------------------------------------------------------------

  describe "F.Announcements.2 — Compose CTA gating" do
    test "manager sees the Compose CTA on /house", %{conn: conn} do
      {:ok, view, _html} = mount_house(conn, role: :manager)

      assert has_element?(view, "#compose-cta", "Compose")
    end

    test "staff does not see the Compose CTA on /house", %{conn: conn} do
      {:ok, view, _html} = mount_house(conn, role: :staff)

      refute has_element?(view, "#compose-cta")
    end
  end

  # ---------------------------------------------------------------------------
  # filter param branches — covers lines 23, 24 (handle_params filter
  # decoding) and 223, 224 (apply_filter for :announcements / :recognition).
  # ---------------------------------------------------------------------------

  describe "filter param decoding (handle_params)" do
    test "filter=announcements activates the Announcements chip and hides recognitions",
         %{conn: conn} do
      # World: one published non-pinned announcement + one public recognition.
      # The `:announcements` filter must keep the announcement and drop the
      # recognition.
      stub(Foyer.HouseMock, :feed_for, fn _user, _opts -> [non_pinned_announcement(0)] end)

      stub(Foyer.RecognitionsMock, :feed_public, fn _opts ->
        [RecognitionsScenarios.WithReceived.sample()]
      end)

      {:ok, view, _html} =
        mount_house(conn,
          role: :staff,
          path: "/house?filter=announcements",
          params: %{"filter" => "announcements"}
        )

      html = render(view)

      # Active filter chip is "Announcements"
      assert has_element?(view, ~s(button[data-filter="announcements"][data-active="true"]))
      # The announcement title is rendered, the recognition body is filtered out.
      assert html =~ "Suite 412 - Allergy protocol in effect"
      refute html =~ "Held the floor together."
    end

    test "filter=recognition activates the Recognition chip and hides announcements",
         %{conn: conn} do
      stub(Foyer.HouseMock, :feed_for, fn _user, _opts -> [non_pinned_announcement(0)] end)

      stub(Foyer.RecognitionsMock, :feed_public, fn _opts ->
        [RecognitionsScenarios.WithReceived.sample()]
      end)

      {:ok, view, _html} =
        mount_house(conn,
          role: :staff,
          path: "/house?filter=recognition",
          params: %{"filter" => "recognition"}
        )

      html = render(view)

      assert has_element?(view, ~s(button[data-filter="recognition"][data-active="true"]))
      assert html =~ "Held the floor together."
      refute html =~ "Suite 412 - Allergy protocol in effect"
    end
  end

  # ---------------------------------------------------------------------------
  # handle_event "filter" — covers lines 40, 41.
  # ---------------------------------------------------------------------------

  describe "filter chip click (handle_event)" do
    test "clicking the Announcements chip pushes a patch to /house?filter=announcements",
         %{conn: conn} do
      {:ok, view, _html} = mount_house(conn, role: :staff)
      Mox.allow(Foyer.HouseMock, self(), view.pid)
      Mox.allow(Foyer.RecognitionsMock, self(), view.pid)

      view
      |> element(~s(button[data-filter="announcements"]))
      |> render_click()

      # `handle_event("filter", …)` calls `push_patch(to: ~p"/house?…")`. We
      # assert the patch URL rather than re-rendering, because the
      # `IsolatedRouter` does not declare `/house` (it doesn't need to —
      # `assert_patch/2` matches against the recorded push, not the router).
      assert_patch(view, "/house?filter=announcements")
    end
  end

  # ---------------------------------------------------------------------------
  # Non-pinned announcement feed entry + day_group_label branches.
  # Covers line 51 (`feed_entry(:announcement, …)` for non-pinned items) and
  # the "Yesterday" / this-week / older branches of `day_group_label/1`
  # (lines 233-235).
  # ---------------------------------------------------------------------------

  describe "day group labels for non-pinned announcements" do
    test "renders Yesterday, this-week, and older day-group labels", %{conn: conn} do
      stub(Foyer.HouseMock, :feed_for, fn _user, _opts ->
        [
          non_pinned_announcement(1, id: 201),
          non_pinned_announcement(3, id: 203),
          non_pinned_announcement(30, id: 230)
        ]
      end)

      {:ok, _view, html} = mount_house(conn, role: :staff)

      today = Date.utc_today()

      assert html =~ "Yesterday"
      assert html =~ Calendar.strftime(Date.add(today, -3), "%a %-d %b")
      assert html =~ Calendar.strftime(Date.add(today, -30), "%-d %b %Y")
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Mount HouseLive in isolation against the given role.
  defp mount_house(conn, opts) do
    role = Keyword.get(opts, :role, :staff)
    path = Keyword.get(opts, :path, "/house")
    params = Keyword.get(opts, :params, %{})

    user =
      case role do
        :manager -> Fixtures.manager()
        :staff -> Fixtures.staff()
      end

    scope = IsolatedHelpers.scope_for(user, true)

    {conn, live_opts} =
      IsolatedHelpers.prepare_isolated(conn, FoyerWeb.HouseLive, scope,
        action: :index,
        path: path,
        params: params
      )

    live_isolated(conn, FoyerWeb.HouseLive, live_opts)
  end

  # A non-pinned announcement whose `published_at` is `days_ago` days before
  # today. Drives the `day_group_label/1` branches.
  defp non_pinned_announcement(days_ago, overrides \\ []) do
    published_at =
      DateTime.utc_now()
      |> DateTime.add(-days_ago * 86_400, :second)
      |> DateTime.truncate(:second)

    base = [pinned_at: nil, published_at: published_at, requires_ack: false]
    Fixtures.announcement(Keyword.merge(base, overrides))
  end
end
