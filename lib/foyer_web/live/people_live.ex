defmodule FoyerWeb.PeopleLive do
  @moduledoc """
  People directory — `/people` (index) and `/people/:id` (full profile for
  managers, or the current user's own profile). On-shift pulses on the index row come from
  `Foyer.Shifts.users_on_shift_ids/0`. Department filters and profile channel sections come
  from `Foyer.Channels` via `FoyerWeb.LiveDeps`.

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
     |> assign(:active_people_filter, :all)
     |> assign(:people_empty?, false)
     |> assign(:people_count, 0)
     |> assign(:profile_rewards, [])
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
     |> assign(:active_people_filter, :channel)
     |> assign(:people_count, length(people))
     |> stream(:people, people, reset: true)}
  end

  @impl true
  def handle_event("clear_filter", _params, socket) do
    apply_index(socket)
  end

  @impl true
  def handle_event("filter_on_shift", _params, socket) do
    people =
      FoyerWeb.LiveDeps.accounts().list_people([])
      |> Enum.filter(&MapSet.member?(socket.assigns.on_shift_ids, &1.id))

    {:noreply,
     socket
     |> assign(:people_empty?, people == [])
     |> assign(:active_channel_filter, nil)
     |> assign(:active_people_filter, :on_shift)
     |> assign(:people_count, length(people))
     |> stream(:people, people, reset: true)}
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
     |> assign(:active_people_filter, :all)
     |> assign(:people_count, length(people))
     |> assign(:card, nil)
     |> assign(:page_title, "People")
     |> stream(:people, people, reset: true)}
  end

  defp apply_show(socket, %{"id" => id}) do
    target = FoyerWeb.LiveDeps.accounts().get_user!(id)

    if can_view_full_profile?(socket.assigns.current_scope, target) do
      own_profile? = own_profile?(socket.assigns.current_scope, target)
      profile = FoyerWeb.LiveDeps.profile()
      card = profile.own_profile_for(target)

      rewards =
        if own_profile? do
          profile.rewards_catalog()
        else
          []
        end

      target_channels = FoyerWeb.LiveDeps.channels().list_for_user(target)

      {:noreply,
       socket
       |> assign(:card, card)
       |> assign(:profile_rewards, rewards)
       |> assign(:target_channels, target_channels)
       |> assign(:page_title, target.name)}
    else
      {:noreply,
       socket
       |> put_flash(:error, "Only managers can view another colleague's full profile.")
       |> push_navigate(to: ~p"/people")}
    end
  rescue
    Ecto.NoResultsError ->
      {:noreply,
       socket
       |> put_flash(:error, "Unknown user.")
       |> push_navigate(to: ~p"/people")}
  end

  defp can_view_full_profile?(%Scope{user: %{id: user_id}}, %{id: user_id}), do: true
  defp can_view_full_profile?(%Scope{} = scope, _target), do: Scope.manager?(scope)
  defp own_profile?(%Scope{user: %{id: user_id}}, %{id: user_id}), do: true
  defp own_profile?(%Scope{}, _target), do: false

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
                  <.icon name="hero-arrow-left" class="size-4" /> Back to People
                </.link>
                <div class="foyer-page-wide" id="people-profile-view">
                  <FoyerComponents.profile_card
                    card={@card}
                    viewer={:self}
                    rewards={@profile_rewards}
                    self_service={own_profile?(@current_scope, @card.user)}
                  />
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
                </div>
              <% true -> %>
                <div class="people-directory foyer-page-wide md:pt-8">
                  <header class="people-directory__header">
                    <div>
                      <h1 class="foyer-serif text-4xl leading-tight">People</h1>
                      <p class="foyer-mono mt-1" id="people-count">
                        {@people_count} colleagues · The Linden
                      </p>
                    </div>

                    <div class="people-directory__filters" id="people-filters">
                      <button
                        phx-click="clear_filter"
                        class={[
                          "people-filter-chip",
                          @active_people_filter == :all && "is-active"
                        ]}
                        id="filter-all"
                      >
                        All
                      </button>
                      <details
                        id="filter-department-menu"
                        class="relative [&_summary::-webkit-details-marker]:hidden marker:hidden"
                      >
                        <summary class={[
                          "people-filter-chip",
                          @active_people_filter == :channel && "is-active"
                        ]}>
                          Department
                        </summary>
                        <div
                          :if={@channel_filter_options != []}
                          id="channel-filter-list"
                          class="people-filter-menu"
                        >
                          <button
                            :for={{ch, count} <- @channel_filter_options}
                            phx-click="filter_channel"
                            phx-value-channel_id={ch.id}
                            class={[
                              "people-filter-menu__item",
                              @active_channel_filter == to_string(ch.id) && "is-active"
                            ]}
                            id={"filter-channel-#{ch.id}"}
                          >
                            <span>{ch.name}</span>
                            <span class="foyer-mono">{count}</span>
                          </button>
                        </div>
                      </details>
                      <button
                        phx-click="filter_on_shift"
                        class={[
                          "people-filter-chip",
                          @active_people_filter == :on_shift && "is-active"
                        ]}
                        id="filter-on-shift"
                      >
                        On shift
                      </button>
                    </div>
                  </header>

                  <ul id="people-list" class="people-directory__list" phx-update="stream">
                    <li :for={{dom_id, person} <- @streams.people} id={dom_id}>
                      <div
                        class={[
                          "people-directory__row",
                          own_profile?(@current_scope, person) && "is-self"
                        ]}
                        id={"people-row-#{person.id}"}
                      >
                        <div class="people-directory__identity" id={"people-identity-#{person.id}"}>
                          <FoyerComponents.avatar initials={person.initials} />
                          <span class="min-w-0">
                            <span class="people-directory__name-line">
                              <span class="foyer-serif people-directory__name">{person.name}</span>
                              <span
                                :if={own_profile?(@current_scope, person)}
                                class="people-directory__self-badge"
                                id={"people-self-#{person.id}"}
                              >
                                You
                              </span>
                            </span>
                            <span class="people-directory__title">{person.title}</span>
                          </span>
                        </div>

                        <span
                          :if={MapSet.member?(@on_shift_ids, person.id)}
                          class="people-directory__status"
                          id={"people-status-#{person.id}"}
                        >
                          <span class="foyer-pulse"></span> On shift
                        </span>
                        <span
                          :if={!MapSet.member?(@on_shift_ids, person.id)}
                          class="people-directory__status is-muted"
                          id={"people-status-#{person.id}"}
                        >
                          Off shift
                        </span>

                        <div class="people-directory__actions">
                          <.link
                            :if={can_view_full_profile?(@current_scope, person)}
                            navigate={~p"/people/#{person.id}"}
                            class="people-directory__action"
                            id={"view-profile-#{person.id}"}
                          >
                            {if own_profile?(@current_scope, person),
                              do: "Your profile",
                              else: "View profile"}
                          </.link>
                          <button
                            :if={!own_profile?(@current_scope, person)}
                            type="button"
                            phx-click="message_colleague"
                            phx-value-user_id={person.id}
                            class="people-directory__action"
                            id={"message-colleague-#{person.id}"}
                          >
                            Message
                          </button>
                        </div>
                      </div>
                    </li>
                    <li :if={@people_empty?} id="people-empty" class="people-directory__empty">
                      No colleagues match this filter.
                    </li>
                  </ul>
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
