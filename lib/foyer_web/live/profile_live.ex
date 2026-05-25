defmodule FoyerWeb.ProfileLive do
  @moduledoc """
  Profile surface — `/me`. Renders the current user's avatar, role, languages,
  on-shift tag, Received / Given recognitions tabs, points balance, and a
  static rewards catalog. Other people's profiles live on `PeopleLive :show`.
  """
  use FoyerWeb, :live_view

  alias FoyerWeb.FoyerComponents

  # Static until Foyer exposes a Points catalog context API.
  @catalog [
    %{label: "1 hour early dismissal", cost: 100},
    %{label: "Staff meal at the Cellar", cost: 200},
    %{label: "Chef's tasting - any Tuesday", cost: 245},
    %{label: "60-min massage or facial", cost: 400},
    %{label: "A night at a sister property", cost: 900},
    %{label: "One extra paid day off", cost: 1_200},
    %{label: "Donate to the staff fund", cost: :variable}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:card, nil)
     |> assign(:catalog, @catalog)
     |> assign(:page_title, "Me")}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    scope = socket.assigns.current_scope
    card = FoyerWeb.LiveDeps.profile().profile_for(scope.user, scope.user)

    now = DateTime.utc_now()
    month_start = %{now | day: 1, hour: 0, minute: 0, second: 0, microsecond: {0, 0}}

    received_this_month =
      Enum.count(card.received, fn r ->
        DateTime.compare(r.inserted_at, month_start) != :lt
      end)

    given_this_month =
      Enum.count(card.given, fn r ->
        DateTime.compare(r.inserted_at, month_start) != :lt
      end)

    {:noreply,
     socket
     |> assign(:card, card)
     |> assign(:received_this_month, received_this_month)
     |> assign(:given_this_month, given_this_month)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main class="foyer-shell">
        <FoyerComponents.desktop_rail active={:me} current_scope={@current_scope} />
        <div class="foyer-content">
          <FoyerComponents.desktop_topbar current_scope={@current_scope} page_title={@page_title} />
          <div class="foyer-scroll" id={"profile-#{if @card, do: @card.user.initials, else: "me"}"}>
            <div class="foyer-page-wide space-y-8">
              <%!-- Header --%>
              <header :if={@card} class="flex items-center gap-4 md:pt-4">
                <FoyerComponents.avatar initials={@card.user.initials} size={:lg} />
                <div>
                  <FoyerComponents.editorial_heading>
                    {@card.user.name}
                  </FoyerComponents.editorial_heading>
                  <p class="text-sm text-stone-600">
                    {@card.user.title}
                  </p>
                  <%!-- TODO: member_since not on User; using inserted_at as fallback. property.name not available in foyer_app scope --%>
                  <p class="text-xs text-stone-500 mt-1">
                    Member since {Calendar.strftime(@card.user.inserted_at, "%B %Y")} · Languages: {Enum.join(
                      @card.user.languages || [],
                      " · "
                    )}
                  </p>
                </div>
              </header>

              <%!-- Stats grid --%>
              <section :if={@card} id="profile-stats" class="grid grid-cols-1 sm:grid-cols-3 gap-3">
                <div class="card-parchment p-4">
                  <FoyerComponents.section_label label="Received this month" />
                  <div class="font-editorial text-3xl mt-1" data-stat-received>
                    {@received_this_month}
                  </div>
                </div>
                <div class="card-parchment p-4">
                  <FoyerComponents.section_label label="Given this month" />
                  <div class="font-editorial text-3xl mt-1" data-stat-given>
                    {@given_this_month}
                  </div>
                </div>
                <div class="card-parchment p-4">
                  <FoyerComponents.section_label label="Foyer points" />
                  <div class="font-editorial text-3xl mt-1" data-stat-balance>
                    {@card.points} pts
                  </div>
                </div>
              </section>

              <%!-- Recognitions Received --%>
              <section :if={@card} id="recognitions-received" class="space-y-3">
                <FoyerComponents.section_label label="Recognitions received" />
                <div :if={@card.received == []} class="text-sm text-stone-500 italic">
                  None yet.
                </div>
                <FoyerComponents.recognition_card
                  :for={r <- @card.received}
                  recognition={r}
                />
              </section>

              <%!-- Trade Your Points / Rewards Catalog --%>
              <section id="rewards-catalog" class="space-y-3">
                <FoyerComponents.section_label label="Trade your points" />
                <p class="text-sm text-stone-600 italic">
                  Earned through recognition. Trade for time, meals, the spa, or pass it on as a donation.
                </p>
                <ul class="card-parchment divide-y divide-stone-200/70 overflow-hidden">
                  <li
                    :for={item <- @catalog}
                    class="flex items-center justify-between gap-4 p-4 text-sm"
                    data-reward-cost={item.cost}
                  >
                    <span>{item.label}</span>
                    <div class="flex items-center gap-3">
                      <span class="text-stone-500">
                        {if item.cost == :variable, do: "Any amount", else: "#{item.cost} pts"}
                      </span>
                      <button
                        type="button"
                        disabled
                        class="btn-foyer-ghost text-xs opacity-50 cursor-not-allowed"
                        data-reward-cta
                      >
                        Coming soon
                      </button>
                    </div>
                  </li>
                </ul>
              </section>
            </div>
            <FoyerComponents.bottom_nav active={:me} current_scope={@current_scope} />
          </div>
        </div>
      </main>
    </Layouts.app>
    """
  end
end
