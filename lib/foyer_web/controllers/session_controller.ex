defmodule FoyerWeb.SessionController do
  @moduledoc """
  POC session helper. The user picker at `/` posts a user-id here; we put it on
  the session and redirect to `/today`. `delete` clears the session.

  Real authentication is out of scope for v0 — see FOYER.md.
  """
  use FoyerWeb, :controller

  alias Foyer.Accounts

  @spec pick(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def pick(conn, %{"user_id" => user_id}) do
    case Accounts.get_user(user_id) do
      nil ->
        conn
        |> put_flash(:error, "Unknown user.")
        |> redirect(to: ~p"/")

      user ->
        conn
        |> renew_session()
        |> put_session(:current_user_id, user.id)
        |> put_flash(:info, "Welcome, #{user.name}.")
        |> redirect(to: ~p"/today")
    end
  end

  @spec sign_out(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def sign_out(conn, _params) do
    conn
    |> renew_session()
    |> put_flash(:info, "Signed out.")
    |> redirect(to: ~p"/")
  end

  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end
end
