defmodule FoyerWeb.IsolatedRouter do
  @moduledoc """
  Test-only router used by `FoyerWeb.IsolatedHelpers` for `live_isolated/3`
  tests.

  When `Phoenix.LiveViewTest.live_isolated/3` reconnects the LiveView via
  `Phoenix.LiveView.Channel`, it runs the on-mount hooks for the
  `live_session` the route declares. The production
  `FoyerWeb.Router.live_session :authenticated_on_shift` requires a real
  user in the connection session — there isn't one in an isolated test.

  This router redeclares the routes the LiveView under test exposes, but
  under a `:isolated_test` live_session whose on_mount hook
  (`FoyerWeb.IsolatedHelpers.OnMount`) reads the `"current_scope"` straight
  out of the session map the test passes to `live_isolated/3`. Compiled in
  the test environment only (see `mix.exs` `elixirc_paths(:test)`).
  """
  use Phoenix.Router

  import Phoenix.LiveView.Router

  live_session :isolated_test,
    on_mount: {FoyerWeb.IsolatedHelpers.OnMount, :default} do
    live "/announcements/new", FoyerWeb.AnnouncementLive, :new
    live "/announcements/:id", FoyerWeb.AnnouncementLive, :show
    live "/announcements/:id/edit", FoyerWeb.AnnouncementLive, :edit
  end
end
