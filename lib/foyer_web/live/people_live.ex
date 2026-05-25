defmodule FoyerWeb.PeopleLive do
  @moduledoc """
  People directory — `/people` (index) and `/people/:id` (one colleague's
  profile card). On-shift pulses on the index row come from
  `Foyer.Shifts.users_on_shift_ids/0`.
  """
  use FoyerWeb, :live_view

  alias FoyerWeb.FoyerComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:people, [])
     |> assign(:on_shift_ids, MapSet.new())
     |> assign(:card, nil)
     |> assign(:page_title, "People")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case socket.assigns.live_action do
      :index -> apply_index(socket)
      :show -> apply_show(socket, params)
    end
  end

  defp apply_index(socket) do
    {:noreply,
     socket
     |> assign(:people, FoyerWeb.LiveDeps.accounts().list_people([]))
     |> assign(:on_shift_ids, FoyerWeb.LiveDeps.shifts().users_on_shift_ids())
     |> assign(:card, nil)
     |> assign(:page_title, "People")}
  end

  defp apply_show(socket, %{"id" => id}) do
    target = FoyerWeb.LiveDeps.accounts().get_user!(id)
    card = FoyerWeb.LiveDeps.profile().profile_for(target)

    {:noreply,
     socket
     |> assign(:card, card)
     |> assign(:page_title, target.name)}
  rescue
    Ecto.NoResultsError ->
      {:noreply,
       socket
       |> put_flash(:error, "Unknown user.")
       |> push_navigate(to: ~p"/people")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main class="foyer-shell">
        <FoyerComponents.desktop_rail active={:me} current_scope={@current_scope} />
        <div class="foyer-content">
          <div class="foyer-scroll" id="people">
            <%= cond do %>
              <% @live_action == :show and @card -> %>
                <.link
                  navigate={~p"/people"}
                  class="foyer-btn ghost sm self-start"
                  id="back-to-people"
                >
                  <.icon name="hero-arrow-left" class="size-4" /> Back
                </.link>
                <FoyerComponents.profile_card card={@card} />
              <% true -> %>
                <header class="flex items-start justify-between">
                  <div>
                    <div class="foyer-mono">The Linden · Mayfair, London</div>
                    <h1 class="foyer-serif text-3xl">People</h1>
                  </div>
                </header>

                <div class="md:flex md:gap-4">
                  <aside
                    class="hidden md:block md:w-48 md:flex-shrink-0 rounded-lg border p-3"
                    style="border-color: var(--foyer-rule);"
                  >
                    <div class="foyer-mono">Filters</div>
                    <ul class="mt-2 flex flex-col gap-1 text-sm">
                      <li>All</li>
                      <li>On shift</li>
                      <li>Off shift</li>
                      <li>Managers</li>
                    </ul>
                  </aside>

                  <ul id="people-list" class="flex flex-col gap-2 md:flex-1">
                    <li :for={p <- @people}>
                      <.link
                        navigate={~p"/people/#{p.id}"}
                        class="flex items-center gap-3 p-3 rounded-lg border"
                        style="border-color: var(--foyer-rule);"
                        id={"people-row-#{p.id}"}
                      >
                        <FoyerComponents.avatar initials={p.initials} />
                        <div class="flex-1">
                          <div class="foyer-serif">{p.name}</div>
                          <div class="foyer-mono">{p.title}</div>
                        </div>
                        <span :if={MapSet.member?(@on_shift_ids, p.id)} class="foyer-tag moss">
                          <span class="foyer-pulse"></span>On shift
                        </span>
                      </.link>
                    </li>
                  </ul>
                </div>
            <% end %>

            <FoyerComponents.bottom_nav active={:me} current_scope={@current_scope} />
          </div>
        </div>
      </main>
    </Layouts.app>
    """
  end
end
