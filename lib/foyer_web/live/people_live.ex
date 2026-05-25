defmodule FoyerWeb.PeopleLive do
  @moduledoc """
  People directory — `/people` (index) and `/people/:id` (one colleague's
  profile card). On-shift pulses on the index row come from
  `Foyer.Shifts.users_on_shift_ids/0`. Channel membership pills come from
  `Foyer.Channels` via `FoyerWeb.LiveDeps`.

  ## LiveView discipline
  - Expensive loads happen in `handle_params/3`, not `mount/3`.
  - The people list uses LiveView streams (per AGENTS.md: "always use streams
    for collections"). Filter events re-fetch from the DB and reset the stream.
  - Channel memberships for `:show` are loaded via `Channels.list_for_user/1`
    into a dedicated `:target_channels` assign, NOT from Profile.Card preloads
    (F.Channels.22).
  """
  use FoyerWeb, :live_view

  alias FoyerWeb.FoyerComponents
  alias FoyerWeb.Scope

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> ensure_current_scope(session)
     |> assign(:on_shift_ids, MapSet.new())
     |> assign(:card, nil)
     |> assign(:target_channels, [])
     |> assign(:channel_filter_options, [])
     |> assign(:active_channel_filter, nil)
     |> assign(:people_empty?, false)
     |> assign(:page_title, "People")
     |> stream(:people, [])}
  end

  # In production, :current_scope is already set by the :ensure_on_shift on_mount hook.
  # In isolated tests (live_isolated/3), the hook does not run, so we fall back to reading
  # from the session directly. This fallback is test-only and is a no-op in production.
  @spec ensure_current_scope(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  defp ensure_current_scope(socket, session) do
    case {socket.assigns[:current_scope], session} do
      {%Scope{}, _} -> socket
      {_, %{"current_scope" => %Scope{} = scope}} -> assign(socket, :current_scope, scope)
      _ -> socket
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case socket.assigns.live_action do
      :index -> apply_index(socket)
      :show -> apply_show(socket, params)
    end
  end

  @impl true
  def handle_event("filter_channel", %{"channel_id" => channel_id}, socket) do
    people = FoyerWeb.LiveDeps.accounts().list_people(channel_id: channel_id)

    {:noreply,
     socket
     |> assign(:people_empty?, people == [])
     |> assign(:active_channel_filter, channel_id)
     |> stream(:people, people, reset: true)}
  end

  @impl true
  def handle_event("clear_filter", _params, socket) do
    apply_index(socket)
  end

  @impl true
  def handle_event("message_colleague", %{"user_id" => user_id_str}, socket) do
    current_user = socket.assigns.current_scope.user

    with {user_id, ""} <- Integer.parse(user_id_str),
         other_user <- FoyerWeb.LiveDeps.accounts().get_user!(user_id),
         {:ok, conv} <-
           FoyerWeb.LiveDeps.chat().get_or_create_direct_conversation(current_user, other_user) do
      {:noreply, push_navigate(socket, to: ~p"/chat/#{conv.id}")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not start conversation")}
    end
  end

  defp apply_index(socket) do
    people = FoyerWeb.LiveDeps.accounts().list_people([])

    {:noreply,
     socket
     |> assign(:people_empty?, people == [])
     |> assign(:on_shift_ids, FoyerWeb.LiveDeps.shifts().users_on_shift_ids())
     |> assign(
       :channel_filter_options,
       FoyerWeb.LiveDeps.channels().list_all_with_member_counts()
     )
     |> assign(:active_channel_filter, nil)
     |> assign(:card, nil)
     |> assign(:page_title, "People")
     |> stream(:people, people, reset: true)}
  end

  defp apply_show(socket, %{"id" => id}) do
    target = FoyerWeb.LiveDeps.accounts().get_user!(id)
    viewer = socket.assigns.current_scope.user
    card = FoyerWeb.LiveDeps.profile().profile_for(target, viewer)
    target_channels = FoyerWeb.LiveDeps.channels().list_for_user(target)

    {:noreply,
     socket
     |> assign(:card, card)
     |> assign(:target_channels, target_channels)
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
        <FoyerComponents.desktop_rail
          active={:people}
          current_scope={@current_scope}
          chat_unread_count={@chat_unread_count}
        />
        <div class="foyer-content">
          <FoyerComponents.desktop_topbar current_scope={@current_scope} page_title={@page_title} />
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
                <%= if @target_channels != [] do %>
                  <div class="mt-4">
                    <div class="foyer-mono mb-2">Channels</div>
                    <div class="flex flex-wrap gap-2" id="target-channels">
                      <span
                        :for={ch <- @target_channels}
                        class="foyer-tag outline"
                        id={"target-channel-#{ch.id}"}
                      >
                        {ch.name}
                      </span>
                    </div>
                  </div>
                <% end %>
              <% true -> %>
                <div class="foyer-page-wide space-y-6 md:pt-8">
                  <div>
                    <%!-- TODO: property.name not exposed on Scope in foyer_app — hardcoded to match desktop_rail default --%>
                    <FoyerComponents.editorial_heading>
                      The Linden · Mayfair
                    </FoyerComponents.editorial_heading>
                    <p class="text-sm text-stone-600 mt-1">
                      Browse the team, find a face, send a message.
                    </p>
                  </div>

                  <div class="md:flex md:gap-4">
                    <aside
                      class="hidden md:block md:w-48 md:flex-shrink-0 rounded-lg border p-3"
                      style="border-color: var(--foyer-rule);"
                      id="people-filter-sidebar"
                    >
                      <div class="foyer-mono">Filters</div>
                      <ul class="mt-2 flex flex-col gap-1 text-sm">
                        <li>
                          <button
                            phx-click="clear_filter"
                            class={[
                              "w-full text-left px-2 py-1 rounded",
                              is_nil(@active_channel_filter) && "font-semibold"
                            ]}
                            id="filter-all"
                          >
                            All
                          </button>
                        </li>
                      </ul>
                      <%= if @channel_filter_options != [] do %>
                        <div class="foyer-mono mt-3">Channels</div>
                        <ul class="mt-1 flex flex-col gap-1 text-sm" id="channel-filter-list">
                          <li :for={{ch, count} <- @channel_filter_options}>
                            <button
                              phx-click="filter_channel"
                              phx-value-channel_id={ch.id}
                              class={[
                                "w-full text-left px-2 py-1 rounded",
                                @active_channel_filter == to_string(ch.id) && "font-semibold"
                              ]}
                              id={"filter-channel-#{ch.id}"}
                            >
                              {ch.name}
                              <span class="foyer-mono ml-1">({count})</span>
                            </button>
                          </li>
                        </ul>
                      <% end %>
                    </aside>

                    <ul id="people-list" class="flex flex-col gap-2 md:flex-1" phx-update="stream">
                      <li :for={{dom_id, person} <- @streams.people} id={dom_id}>
                        <.link
                          navigate={~p"/people/#{person.id}"}
                          class="flex items-center gap-3 p-3 rounded-lg border"
                          style="border-color: var(--foyer-rule);"
                          id={"people-row-#{person.id}"}
                        >
                          <FoyerComponents.avatar initials={person.initials} />
                          <div class="flex-1">
                            <div class="foyer-serif">{person.name}</div>
                            <div class="foyer-mono">{person.title}</div>
                            <%= if person.memberships != [] do %>
                              <div class="flex flex-wrap gap-1 mt-1">
                                <span
                                  :for={m <- person.memberships}
                                  class="foyer-tag outline"
                                  id={"person-#{person.id}-channel-#{m.channel_id}"}
                                >
                                  {m.channel && m.channel.name}
                                </span>
                              </div>
                            <% end %>
                          </div>
                          <span :if={MapSet.member?(@on_shift_ids, person.id)} class="foyer-tag moss">
                            <span class="foyer-pulse"></span>On shift
                          </span>
                        </.link>
                      </li>
                    </ul>
                  </div>
                </div>
            <% end %>

            <FoyerComponents.bottom_nav
              active={:people}
              current_scope={@current_scope}
              chat_unread_count={@chat_unread_count}
            />
          </div>
        </div>
      </main>
    </Layouts.app>
    """
  end
end
