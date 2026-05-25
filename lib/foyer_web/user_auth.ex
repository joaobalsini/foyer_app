defmodule FoyerWeb.UserAuth do
  @moduledoc """
  Authentication helpers for Foyer.

  - `fetch_current_user/2` is a plug that hydrates `conn.assigns.current_user`
    and `conn.assigns.current_shift` from the session.
  - `on_mount/4` has three clauses (`:mount_public`, `:ensure_authenticated`,
    `:ensure_on_shift`) used by the three `live_session` blocks declared in
    `FoyerWeb.Router`.

  POC v1: no password — the user picker at `/` sets `:current_user_id` in the
  session via `FoyerWeb.SessionController`.
  """
  use FoyerWeb, :verified_routes

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias Foyer.Accounts
  alias Foyer.Shifts
  alias FoyerWeb.Scope
  alias Plug.Conn

  @doc """
  Plug. Reads `:current_user_id` from the session and assigns `:current_user`
  and `:current_shift` on the conn (or nil for both if unauthenticated).
  """
  @spec fetch_current_user(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def fetch_current_user(conn, _opts) do
    case Conn.get_session(conn, :current_user_id) do
      nil ->
        conn
        |> Conn.assign(:current_user, nil)
        |> Conn.assign(:current_shift, nil)

      user_id ->
        case Accounts.get_user(user_id) do
          nil ->
            conn
            |> Conn.assign(:current_user, nil)
            |> Conn.assign(:current_shift, nil)

          user ->
            conn
            |> Conn.assign(:current_user, user)
            |> Conn.assign(:current_shift, Shifts.current_shift_for(user))
        end
    end
  end

  @doc """
  LiveView on_mount hook. Three clauses, one per `live_session` block. The
  block decides which clause runs — no `socket.view` introspection.
  """
  @spec on_mount(atom(), map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()} | {:halt, Phoenix.LiveView.Socket.t()}
  def on_mount(:mount_public, _params, session, socket) do
    {:cont, assign(socket, :current_scope, load_scope(session))}
  end

  def on_mount(:ensure_authenticated, _params, session, socket) do
    case load_scope(session) do
      nil ->
        {:halt,
         socket
         |> put_flash(:error, "Please pick a user.")
         |> Phoenix.LiveView.redirect(to: ~p"/")}

      %Scope{} = scope ->
        {:cont, assign(socket, :current_scope, scope)}
    end
  end

  def on_mount(:ensure_on_shift, _params, session, socket) do
    case load_scope(session) do
      nil ->
        {:halt,
         socket
         |> put_flash(:error, "Please pick a user.")
         |> Phoenix.LiveView.redirect(to: ~p"/")}

      %Scope{on_shift?: false} ->
        {:halt,
         socket
         |> put_flash(:info, "Start your shift to enter the rest of Foyer.")
         |> Phoenix.LiveView.redirect(to: ~p"/today")}

      %Scope{} = scope ->
        {:cont, assign(socket, :current_scope, scope)}
    end
  end

  @spec load_scope(map()) :: Scope.t() | nil
  # Isolated-test fallback. Production paths set `current_user_id` (see the
  # `:current_user_id` clause below). `FoyerWeb.IsolatedHelpers` stuffs a
  # pre-built `Scope` into the session so `live_isolated/3` tests don't need a
  # real DB user. This clause is unreachable from production code paths
  # because no controller / live_session puts `"current_scope"` in the
  # session.
  defp load_scope(%{"current_scope" => %Scope{} = scope}), do: scope

  defp load_scope(%{"current_user_id" => user_id}) when not is_nil(user_id) do
    case Accounts.get_user(user_id) do
      nil ->
        nil

      user ->
        shift = Shifts.current_shift_for(user)
        Scope.for_user(user, shift)
    end
  end

  defp load_scope(_), do: nil
end
