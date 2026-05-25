defmodule FoyerWeb.IsolatedHelpers do
  @moduledoc """
  Test-only harness for `Phoenix.LiveViewTest.live_isolated/3`.

  `live_isolated/3` skips the router, plugs, `live_session`, and `on_mount`
  hooks (see `docs/TESTING_GUIDE.md`). Foyer LiveViews rely on a
  `@current_scope` assign that the real on_mount hook installs, so isolated
  tests need a small harness to provide it without booting the router.

  The harness here installs a single test-only on_mount hook
  (`FoyerWeb.IsolatedHelpers.OnMount`) by stashing a synthetic `live_session`
  in `conn.private[:phoenix_live_view]`. The hook reads the `%FoyerWeb.Scope{}`
  out of the LiveView session (passed as a session value with string key
  `"current_scope"`).

  This module is compiled in the test environment only (see
  `mix.exs :elixirc_paths`).
  """

  alias FoyerWeb.Scope
  alias Phoenix.LiveView.Lifecycle

  defmodule OnMount do
    @moduledoc false
    # Test-only on_mount hook. Pulls `"current_scope"` out of the session and
    # assigns it on the socket so the LiveView and layout components have the
    # same shape they would have under the real `FoyerWeb.UserAuth` hook.

    import Phoenix.Component, only: [assign: 3]

    @spec on_mount(:default, map(), map(), Phoenix.LiveView.Socket.t()) ::
            {:cont, Phoenix.LiveView.Socket.t()}
    def on_mount(:default, _params, %{"current_scope" => %Scope{} = scope}, socket) do
      {:cont, assign(socket, :current_scope, scope)}
    end
  end

  @doc """
  Prepares a conn for `live_isolated/3` and produces the matching opts.

  Returns `{conn, opts}` ready to pipe into `live_isolated/3`. The conn has
  `phoenix_live_view` private set so the test on_mount hook runs during the
  static render, `params` set so `handle_params/3` receives an actual map
  (not `:not_mounted_at_router`), and `request_path` set so the channel
  mount's `live_link_info!/3` finds a matching route in the **test router**
  (`FoyerWeb.IsolatedRouter`) rather than the production router.

  Why a test router? When the LiveView channel reconnects after the static
  render, `live_link_info!/3` looks up the matching route in the configured
  router. If the route's `live_session` differs from the synthetic one set
  in `conn.private[:phoenix_live_view]`, the channel mount treats the URL
  as external and redirects. If it matches, the channel mount runs the on
  mount hooks declared on that `live_session` — which for the production
  router means `FoyerWeb.UserAuth`, which redirects unauthenticated requests
  to `/`. `FoyerWeb.IsolatedRouter` redeclares the routes under a
  `:isolated_test` live_session with the test on_mount hook, so both the
  static render and the channel mount agree on what to do.

  Required option:

    * `:action` — the `live_action` (`:new`, `:show`, `:edit`).

  Optional:

    * `:params` — map handed to `handle_params/3` (default `%{}`).
    * `:path` — the conn's request path (default inferred from action).
    * `:router` — override the test router (default `FoyerWeb.IsolatedRouter`).

  Usage:

      {conn, opts} =
        FoyerWeb.IsolatedHelpers.prepare_isolated(
          conn,
          FoyerWeb.AnnouncementLive,
          scope,
          action: :show,
          params: %{"id" => "100"},
          path: "/announcements/100"
        )

      {:ok, view, html} = live_isolated(conn, FoyerWeb.AnnouncementLive, opts)

      Mox.allow(Foyer.HouseMock, self(), view.pid)
  """
  @spec prepare_isolated(Plug.Conn.t(), module(), Scope.t(), keyword()) ::
          {Plug.Conn.t(), keyword()}
  def prepare_isolated(conn, view, %Scope{} = scope, opts) do
    action = Keyword.fetch!(opts, :action)
    params = Keyword.get(opts, :params, %{})
    path = Keyword.get(opts, :path, default_path_for(action, params))
    router = Keyword.get(opts, :router, FoyerWeb.IsolatedRouter)

    hooks =
      [{OnMount, :default}]
      |> Enum.map(&Lifecycle.validate_on_mount!(view, &1))
      |> Lifecycle.prepare_on_mount!()

    live_session = %{name: :isolated_test, extra: %{on_mount: hooks}}

    conn =
      conn
      |> Plug.Conn.put_private(:phoenix_live_view, {view, [], live_session})
      |> Map.put(:params, params)
      |> Map.put(:request_path, path)

    {conn, [session: %{"current_scope" => scope}, router: router, action: action]}
  end

  defp default_path_for(:new, _params), do: "/announcements/new"
  defp default_path_for(:show, %{"id" => id}), do: "/announcements/#{id}"
  defp default_path_for(:edit, %{"id" => id}), do: "/announcements/#{id}/edit"
  defp default_path_for(_action, _params), do: "/"

  @doc """
  Builds a `%Scope{}` for a `%User{}` and on-shift state. Convenience
  alternative to `FoyerWeb.Scope.for_user/2` when the test doesn't have a
  `%Shift{}` handy.
  """
  @spec scope_for(Foyer.Accounts.User.t(), boolean()) :: Scope.t()
  def scope_for(%Foyer.Accounts.User{} = user, on_shift?) do
    %Scope{
      user: user,
      on_shift?: on_shift?,
      shift: if(on_shift?, do: %Foyer.Shifts.Shift{user_id: user.id}, else: nil),
      role: user.role
    }
  end
end
