defmodule FoyerWeb.IsolatedHelpers do
  @moduledoc """
  Test-only harnesses for `Phoenix.LiveViewTest.live_isolated/3`.

  `live_isolated/3` skips the router, plugs, `live_session`, and `on_mount`
  hooks. Foyer LiveViews rely on a `@current_scope` assign that the real
  on_mount hook installs, so isolated tests use this module to provide it
  without booting the production router.

  This module is compiled in the test environment only (see
  `mix.exs :elixirc_paths`).
  """

  alias Foyer.Accounts.User
  alias FoyerWeb.Scope
  alias Phoenix.LiveView.Lifecycle

  require Phoenix.LiveViewTest

  defmodule OnMount do
    @moduledoc false

    import Phoenix.Component, only: [assign: 3]

    @spec on_mount(:default, map(), map(), Phoenix.LiveView.Socket.t()) ::
            {:cont, Phoenix.LiveView.Socket.t()}
    def on_mount(:default, _params, %{"current_scope" => %Scope{} = scope}, socket) do
      {:cont,
       socket
       |> assign(:current_scope, scope)
       |> assign(:chat_unread_count, 0)}
    end
  end

  @doc """
  Mounts `FoyerWeb.ChatLive` in isolation against the provided user and
  live_action, with `current_scope` pinned by `FoyerWeb.IsolatedChatLive`.
  """
  defmacro mount_isolated_chat(conn, user, opts \\ []) do
    quote bind_quoted: [conn: conn, user: user, opts: opts] do
      live_action = Keyword.get(opts, :live_action, :inbox)
      conversation_id = Keyword.get(opts, :conversation_id)
      on_shift? = Keyword.get(opts, :on_shift?, true)

      session = %{
        "foyer_isolated_user" => user,
        "foyer_isolated_on_shift?" => on_shift?,
        "foyer_isolated_live_action" => live_action,
        "foyer_isolated_conversation_id" => conversation_id
      }

      Phoenix.LiveViewTest.live_isolated(conn, FoyerWeb.IsolatedChatLive, session: session)
    end
  end

  @doc """
  Mounts `FoyerWeb.RecognitionsLive` in isolation with the same route/session
  plumbing used by the real authenticated on-shift routes.

  `:action` and `:scope` are required. For `:show` / `:edit`, pass `:path`
  and `:params` when the test needs a concrete recognition id.
  """
  defmacro mount_isolated_recognitions(conn, opts) do
    quote bind_quoted: [conn: conn, opts: opts] do
      scope = Keyword.fetch!(opts, :scope)
      action = Keyword.fetch!(opts, :action)
      params = Keyword.get(opts, :params, %{})
      path = Keyword.get(opts, :path, FoyerWeb.IsolatedHelpers.recognitions_path_for(action))

      conn =
        conn
        |> Map.put(:params, params)
        |> FoyerWeb.IsolatedHelpers.prepare_conn(
          FoyerWeb.RecognitionsLive,
          :isolated_test,
          path,
          [{FoyerWeb.IsolatedHelpers.OnMount, :default}]
        )

      Phoenix.LiveViewTest.live_isolated(conn, FoyerWeb.RecognitionsLive,
        session: FoyerWeb.IsolatedHelpers.session_for(scope),
        action: action,
        router: FoyerWeb.IsolatedRouter
      )
    end
  end

  @doc """
  Mount `FoyerWeb.ProfileLive` in isolation against the provided user.
  Returns the same shape as `Phoenix.LiveViewTest.live_isolated/3`.
  """
  defmacro mount_isolated_profile(conn, user, opts \\ []) do
    quote bind_quoted: [conn: conn, user: user, opts: opts] do
      on_shift? = Keyword.get(opts, :on_shift?, true)

      session = %{
        "foyer_isolated_user" => user,
        "foyer_isolated_on_shift?" => on_shift?
      }

      Phoenix.LiveViewTest.live_isolated(conn, FoyerWeb.IsolatedProfileLive, session: session)
    end
  end

  @doc """
  Mount `FoyerWeb.PeopleLive` in `:show` action in isolation against the
  provided viewer and a subject_id. Returns the same shape as
  `Phoenix.LiveViewTest.live_isolated/3`.
  """
  defmacro mount_isolated_people_show(conn, viewer, subject_id, opts \\ []) do
    quote bind_quoted: [conn: conn, viewer: viewer, subject_id: subject_id, opts: opts] do
      on_shift? = Keyword.get(opts, :on_shift?, true)

      session = %{
        "foyer_isolated_user" => viewer,
        "foyer_isolated_on_shift?" => on_shift?,
        "foyer_isolated_live_action" => :show,
        "foyer_isolated_subject_id" => subject_id
      }

      Phoenix.LiveViewTest.live_isolated(conn, FoyerWeb.IsolatedPeopleLive, session: session)
    end
  end

  @doc """
  Mount `FoyerWeb.PeopleLive` in `:index` action in isolation.
  """
  defmacro mount_isolated_people_index(conn, viewer, opts \\ []) do
    quote bind_quoted: [conn: conn, viewer: viewer, opts: opts] do
      on_shift? = Keyword.get(opts, :on_shift?, true)

      session = %{
        "foyer_isolated_user" => viewer,
        "foyer_isolated_on_shift?" => on_shift?,
        "foyer_isolated_live_action" => :index
      }

      Phoenix.LiveViewTest.live_isolated(conn, FoyerWeb.IsolatedPeopleLive, session: session)
    end
  end

  @doc """
  Prepares a conn for `live_isolated/3` and produces the matching opts.
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

    {conn, [session: session_for(scope), router: router, action: action]}
  end

  defp default_path_for(:new, _params), do: "/announcements/new"
  defp default_path_for(:show, %{"id" => id}), do: "/announcements/#{id}"
  defp default_path_for(:edit, %{"id" => id}), do: "/announcements/#{id}/edit"
  defp default_path_for(_action, _params), do: "/"

  @doc false
  @spec recognitions_path_for(atom()) :: String.t()
  def recognitions_path_for(:index), do: "/recognitions"
  def recognitions_path_for(:new), do: "/recognitions/new"
  def recognitions_path_for(:show), do: "/recognitions/1"
  def recognitions_path_for(:edit), do: "/recognitions/1/edit"

  @doc """
  Builds a `%Scope{}` for a `%User{}` and on-shift state.
  """
  @spec scope_for(User.t(), boolean()) :: Scope.t()
  def scope_for(%User{} = user, on_shift?) do
    shift =
      if on_shift? do
        %Foyer.Shifts.Shift{user_id: user.id}
      end

    Scope.for_user(user, shift)
  end

  @doc """
  Builds a `FoyerWeb.Scope` for an in-memory user. Pass `:role`, `:on_shift?`,
  and any other `User` field as keyword overrides.

  ## Examples

      scope = build_scope(id: 1, name: "Maya", role: :staff, on_shift?: true)
  """
  @spec build_scope(keyword()) :: Scope.t()
  def build_scope(opts \\ []) do
    on_shift? = Keyword.get(opts, :on_shift?, true)

    user_fields =
      opts
      |> Keyword.drop([:on_shift?])
      |> Keyword.put_new(:id, 1)
      |> Keyword.put_new(:name, "Maya Okafor")
      |> Keyword.put_new(:initials, "MO")
      |> Keyword.put_new(:role, :staff)
      |> Keyword.put_new(:department, "Housekeeping")
      |> Keyword.put_new(:title, "Senior Housekeeper · Floor 4")
      |> Keyword.put_new(:languages, ["EN"])
      |> Keyword.put_new(:points_balance, 0)

    user = struct!(User, user_fields)
    scope_for(user, on_shift?)
  end

  @doc """
  Builds a scope struct from a user and on-shift flag.
  """
  @spec build_scope(User.t(), boolean()) :: Scope.t()
  def build_scope(%User{} = user, on_shift?), do: scope_for(user, on_shift?)

  @doc """
  Returns a session map ready for `live_isolated/3`.
  """
  @spec session_for(Scope.t()) :: %{required(String.t()) => term()}
  def session_for(%Scope{} = scope), do: %{"current_scope" => scope}

  @doc """
  Prepares a `Plug.Conn` for `live_isolated/3` by setting `request_path` and
  `private[:phoenix_live_view]` to match the LiveView's intended route.
  """
  @spec prepare_conn(Plug.Conn.t(), module(), atom(), String.t(), [{module(), atom()}]) ::
          Plug.Conn.t()
  def prepare_conn(%Plug.Conn{} = conn, live_view, live_session_name, path, on_mount \\ []) do
    hooks =
      on_mount
      |> Enum.map(&Lifecycle.validate_on_mount!(live_view, &1))
      |> Lifecycle.prepare_on_mount!()

    live_session = %{
      name: live_session_name,
      extra: %{on_mount: hooks}
    }

    %{conn | request_path: path}
    |> Plug.Conn.put_private(:phoenix_live_view, {live_view, [], live_session})
  end
end
