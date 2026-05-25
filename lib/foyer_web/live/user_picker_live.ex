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
        <div
          class="min-h-screen md:grid md:grid-cols-[minmax(20rem,0.85fr)_minmax(28rem,1fr)]"
          id="user-picker"
        >
          <section class="hidden border-r border-[var(--foyer-rule)] p-10 md:flex md:flex-col md:justify-between">
            <div>
              <div class="foyer-serif text-4xl">Foyer</div>
              <div class="foyer-mono mt-2">The Linden · Mayfair, London</div>
            </div>

            <div class="max-w-sm">
              <h1 class="foyer-serif text-5xl leading-tight">Staff sign in</h1>
              <p class="mt-4 text-base text-stone-600">
                Select a demo account to enter the staff workspace.
              </p>
            </div>

            <div class="foyer-mono">Prototype access · no password required</div>
          </section>

          <section class="flex min-h-screen items-center justify-center p-6">
            <div class="w-full max-w-md">
              <div class="mb-8 md:hidden">
                <div class="foyer-serif text-4xl">Foyer</div>
                <div class="foyer-mono mt-1">The Linden · Mayfair, London</div>
              </div>

              <div class="rounded-lg border border-[var(--foyer-rule)] bg-[color-mix(in_srgb,var(--foyer-cream)_88%,white)] p-5 shadow-sm">
                <div class="mb-5">
                  <h2 class="foyer-serif text-3xl">Pick a user</h2>
                  <p class="mt-1 text-sm text-stone-600">
                    Continue as one of the seeded staff accounts.
                  </p>
                </div>

                <ul class="flex flex-col gap-2">
                  <li :for={u <- @users}>
                    <.form
                      for={to_form(%{}, as: :pick)}
                      id={"pick-#{u.id}"}
                      action={~p"/session/pick/#{u.id}"}
                      method="post"
                    >
                      <button
                        class="flex w-full cursor-pointer items-center gap-3 rounded-lg border border-transparent px-3 py-3 text-left transition hover:border-[var(--foyer-rule)] hover:bg-[var(--foyer-cream-deep)]"
                        id={"pick-btn-#{u.id}"}
                        type="submit"
                      >
                        <span class="foyer-avatar">{u.initials}</span>
                        <span class="min-w-0 flex-1">
                          <span class="block font-semibold truncate">{u.name}</span>
                          <span class="foyer-mono block truncate">{u.title}</span>
                        </span>
                        <span class="hero-arrow-right size-4 text-stone-400"></span>
                      </button>
                    </.form>
                  </li>
                </ul>

                <div class="mt-5 rounded-lg border border-[var(--foyer-rule)] px-3 py-2 text-xs text-stone-500">
                  Demo login only. Session starts immediately after choosing a user.
                </div>
              </div>
            </div>
          </section>
        </div>
      </main>
    </Layouts.app>
    """
  end
end
