defmodule FoyerWeb.ProfileLive do
  @moduledoc """
  Profile surface — `/me`. Renders the current user's avatar, role, languages,
  on-shift tag, Received / Given recognitions tabs, points balance, and a
  static rewards catalog. Other people's profiles live on `PeopleLive :show`.
  """
  use FoyerWeb, :live_view

  alias FoyerWeb.FoyerComponents

  @rewards [
    %{title: "Coffee for the team", cost: 100},
    %{title: "Early finish · 1 hour", cost: 250},
    %{title: "Spa treatment", cost: 500},
    %{title: "Dinner at Linden Grill", cost: 750},
    %{title: "Weekend off", cost: 1_000},
    %{title: "Two nights, anywhere in the group", cost: 2_500}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:card, nil)
     |> assign(:rewards, @rewards)
     |> assign(:page_title, "Me")}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    scope = socket.assigns.current_scope
    {:noreply, assign(socket, :card, FoyerWeb.LiveDeps.profile().profile_for(scope.user))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main class="foyer-shell">
        <FoyerComponents.desktop_rail active={:me} current_scope={@current_scope} />
        <div class="foyer-content">
          <div class="foyer-scroll" id="profile">
            <FoyerComponents.profile_card :if={@card} card={@card} rewards={@rewards} />
            <FoyerComponents.bottom_nav active={:me} current_scope={@current_scope} />
          </div>
        </div>
      </main>
    </Layouts.app>
    """
  end
end
