defmodule FoyerWeb.ProfileLive do
  @moduledoc """
  Profile surface — `/me`. Renders the current user's avatar, role, languages,
  on-shift tag, Received / Given recognitions, points balance, and a static
  rewards catalog. Other people's profiles live on `PeopleLive :show`.

  Data is loaded in `handle_params/3` (not `mount/3`) per ARCHITECTURE.md:
  expensive work belongs in handle_params so the first HTTP render stays cheap.
  The rewards catalog is fetched via `Profile.Behavior.rewards_catalog/0` so isolated
  tests can inject a controlled list via Mox.
  """
  use FoyerWeb, :live_view

  alias FoyerWeb.FoyerComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:card, nil)
     |> assign(:rewards, [])
     |> assign(:page_title, "Me")}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    scope = socket.assigns.current_scope
    profile = FoyerWeb.LiveDeps.profile()
    card = profile.own_profile_for(scope.user)
    rewards = profile.rewards_catalog()

    {:noreply,
     socket
     |> assign(:card, card)
     |> assign(:rewards, rewards)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main class="foyer-shell">
        <FoyerComponents.desktop_rail
          active={:me}
          current_scope={@current_scope}
          chat_unread_count={@chat_unread_count}
        />
        <div class="foyer-content">
          <div class="foyer-scroll" id="profile">
            <button
              type="button"
              phx-click={JS.dispatch("foyer:history-back")}
              class="foyer-btn ghost sm self-start"
              id="back-from-profile"
            >
              <.icon name="hero-arrow-left" class="size-4" /> Back
            </button>
            <div class="foyer-page-wide" id="profile-view">
              <FoyerComponents.profile_card
                :if={@card}
                card={@card}
                rewards={@rewards}
                viewer={:self}
              />
              <.link
                href={~p"/session"}
                method="delete"
                id="profile-sign-out"
                class="foyer-btn forest w-full justify-center"
              >
                <.icon name="hero-arrow-left-on-rectangle" class="size-4" /> Sign out
              </.link>
            </div>
            <FoyerComponents.bottom_nav active={:me} current_scope={@current_scope} />
          </div>
        </div>
      </main>
    </Layouts.app>
    """
  end
end
