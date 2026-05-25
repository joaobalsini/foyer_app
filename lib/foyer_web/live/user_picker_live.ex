defmodule FoyerWeb.UserPickerLive do
  @moduledoc """
  POC user picker at `/`. Lists every seeded user; clicking a row POSTs to
  `SessionController.pick/2` which puts the user_id in the session and
  redirects to `/today`.
  """
  use FoyerWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, users: [], page_title: "Pick a user")}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, :users, FoyerWeb.LiveDeps.accounts().list_pickable_users())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main class="foyer-root">
        <div class="foyer-scroll" id="user-picker">
          <div class="foyer-mono">Foyer · The Linden, Mayfair, London</div>
          <h1 class="foyer-serif text-3xl">Pick a user</h1>
          <p>POC demo - no password.</p>
          <ul class="flex flex-col gap-2">
            <li :for={u <- @users}>
              <.form
                for={to_form(%{}, as: :pick)}
                id={"pick-#{u.id}"}
                action={~p"/session/pick/#{u.id}"}
                method="post"
              >
                <button
                  class="foyer-btn w-full text-left"
                  id={"pick-btn-#{u.id}"}
                  type="submit"
                >
                  <span class="foyer-avatar">{u.initials}</span>
                  <span class="flex-1 ml-2">
                    <span class="foyer-serif block">{u.name}</span>
                    <span class="foyer-mono block">{u.title}</span>
                  </span>
                </button>
              </.form>
            </li>
          </ul>
        </div>
      </main>
    </Layouts.app>
    """
  end
end
