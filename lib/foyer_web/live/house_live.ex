defmodule FoyerWeb.HouseLive do
  @moduledoc """
  House feed — `/house`. Renders the announcement + recognition feed via
  LiveView streams. Compose/edit live on `AnnouncementLive`.
  """
  use FoyerWeb, :live_view

  alias FoyerWeb.FoyerComponents
  alias FoyerWeb.Scope

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> stream_configure(:feed, dom_id: &"feed-#{&1.id}")
     |> stream(:feed, [])
     |> assign(:page_title, "The House")}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    scope = socket.assigns.current_scope
    feed = FoyerWeb.LiveDeps.house().feed_for(scope.user, [])

    {:noreply, stream(socket, :feed, feed, reset: true)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main class="foyer-shell">
        <FoyerComponents.desktop_rail active={:house} current_scope={@current_scope} />
        <div class="foyer-content">
          <div class="foyer-scroll md:max-w-3xl" id="house">
            <header class="flex items-start justify-between">
              <div>
                <div class="foyer-mono">The Linden · Mayfair, London</div>
                <h1 class="foyer-serif text-3xl">The House</h1>
              </div>
              <%= if Scope.manager?(@current_scope) do %>
                <.link
                  navigate={~p"/announcements/new"}
                  id="compose-cta"
                  class="foyer-btn forest sm"
                >
                  <.icon name="hero-pencil-square" class="size-4" /> Compose
                </.link>
              <% end %>
            </header>

            <div class="flex gap-2" role="tablist" id="house-filters">
              <button type="button" class="foyer-btn sm" id="filter-all">All</button>
              <button type="button" class="foyer-btn sm" id="filter-announcements">
                Announcements
              </button>
              <button type="button" class="foyer-btn sm" id="filter-recognition">
                Recognition
              </button>
            </div>

            <.link
              navigate={~p"/recognitions/new"}
              id="recognize-cta"
              class="foyer-btn sm self-start"
            >
              Recognize
            </.link>

            <div id="house-feed" phx-update="stream" class="flex flex-col gap-3">
              <div :for={{id, item} <- @streams.feed} id={id}>
                <FoyerComponents.announcement_card announcement={item} />
              </div>
            </div>

            <FoyerComponents.bottom_nav active={:house} current_scope={@current_scope} />
          </div>
        </div>
      </main>
    </Layouts.app>
    """
  end
end
