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
     |> assign(:page_title, "The House")
     |> assign(:filter, :all)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filter =
      case params["filter"] do
        "announcements" -> :announcements
        "recognition" -> :recognition
        _ -> :all
      end

    scope = socket.assigns.current_scope
    feed = FoyerWeb.LiveDeps.house().feed_for(scope.user, [])
    recognitions = house_recognitions(scope.user)

    {:noreply,
     socket
     |> assign(:filter, filter)
     |> assign(:feed, feed)
     |> assign(:recognitions, recognitions)}
  end

  @impl true
  def handle_event("filter", %{"filter" => filter}, socket) do
    {:noreply, push_patch(socket, to: ~p"/house?filter=#{filter}")}
  end

  @impl true
  def render(assigns) do
    pinned = Enum.filter(assigns.feed, fn a -> not is_nil(a.pinned_at) end)

    announcements =
      assigns.feed
      |> Enum.reject(fn a -> not is_nil(a.pinned_at) end)
      |> Enum.map(&feed_entry(:announcement, &1))

    recognitions =
      assigns.recognitions
      |> Enum.map(&feed_entry(:recognition, &1))

    non_pinned =
      (announcements ++ recognitions)
      |> apply_filter(assigns.filter)

    day_groups =
      non_pinned
      |> Enum.group_by(fn a ->
        ts = a.ts
        day_group_label(DateTime.to_date(ts))
      end)
      |> Enum.sort_by(
        fn {_label, [first | _]} ->
          first.ts
        end,
        {:desc, DateTime}
      )

    filtered_pinned =
      pinned
      |> Enum.map(&feed_entry(:announcement, &1))
      |> apply_filter(assigns.filter)

    assigns =
      assigns
      |> assign(:pinned, filtered_pinned)
      |> assign(:day_groups, day_groups)

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main class="foyer-shell">
        <FoyerComponents.desktop_rail
          active={:house}
          current_scope={@current_scope}
          chat_unread_count={@chat_unread_count}
        />
        <div class="foyer-content">
          <FoyerComponents.desktop_topbar current_scope={@current_scope} page_title={@page_title} />
          <div class="foyer-scroll" id="house">
            <div class="foyer-page-wide space-y-6">
              <header class="flex items-start justify-between">
                <div>
                  <FoyerComponents.editorial_heading>The House</FoyerComponents.editorial_heading>
                  <p class="text-sm text-stone-600">The Linden · Mayfair, London</p>
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

              <nav id="house-filters" class="flex gap-2" role="tablist">
                <.filter_chip label="All" filter={:all} active={@filter == :all} />
                <.filter_chip
                  label="Announcements"
                  filter={:announcements}
                  active={@filter == :announcements}
                />
                <.filter_chip
                  label="Recognition"
                  filter={:recognition}
                  active={@filter == :recognition}
                />
              </nav>

              <section
                class="rounded-lg p-5 text-center flex flex-col gap-3"
                id="recognize-cta"
                style="background: var(--foyer-cream-deep); border: 1px solid var(--foyer-rule);"
              >
                <p class="foyer-serif italic text-lg">Notice a colleague going above and beyond?</p>
                <p class="text-sm" style="color: var(--foyer-stone-600, #57534e);">
                  Share a shout-out — it lands in their phone and the house feed.
                </p>
                <.link navigate={~p"/recognitions/new"} class="foyer-btn sm self-center">
                  Recognize
                </.link>
              </section>

              <section
                :if={@pinned != [] and @filter != :recognition}
                id="pinned-section"
                class="flex flex-col gap-3"
              >
                <FoyerComponents.section_label label="Pinned" />
                <div :for={entry <- @pinned}>
                  <.feed_card entry={entry} current_user_id={@current_scope.user.id} />
                </div>
              </section>

              <div id="feed" class="flex flex-col gap-6">
                <div :for={{day_label, items} <- @day_groups} class="flex flex-col gap-3">
                  <div class="flex items-center gap-3">
                    <h2 class="foyer-serif text-xl">{day_label}</h2>
                    <div class="h-px flex-1 bg-[var(--foyer-rule)]"></div>
                  </div>
                  <div :for={entry <- items}>
                    <.feed_card entry={entry} current_user_id={@current_scope.user.id} />
                  </div>
                </div>
              </div>

              <FoyerComponents.bottom_nav
                active={:house}
                current_scope={@current_scope}
                chat_unread_count={@chat_unread_count}
              />
            </div>
          </div>
        </div>
      </main>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :filter, :atom, required: true
  attr :active, :boolean, required: true

  defp filter_chip(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="filter"
      phx-value-filter={@filter}
      data-filter={@filter}
      data-active={to_string(@active)}
      class={[
        "px-3 py-1 rounded-full text-xs font-medium border",
        @active &&
          "bg-[var(--foyer-forest)] text-[var(--foyer-cream)] border-[var(--foyer-forest)]",
        !@active && "bg-transparent border-[var(--foyer-rule)]"
      ]}
    >
      {@label}
    </button>
    """
  end

  defp feed_entry(:announcement, item),
    do: %{kind: :announcement, item: item, ts: item.published_at || item.inserted_at}

  defp feed_entry(:recognition, item), do: %{kind: :recognition, item: item, ts: item.inserted_at}

  defp house_recognitions(user) do
    recognitions = FoyerWeb.LiveDeps.recognitions()
    public = recognitions.feed_public([])

    authored_private =
      recognitions.given_by(user, user)
      |> Enum.reject(& &1.public)

    received_private =
      recognitions.received_by(user, user)
      |> Enum.reject(& &1.public)

    (public ++ authored_private ++ received_private)
    |> Enum.uniq_by(& &1.id)
  end

  attr :entry, :map, required: true
  attr :current_user_id, :integer, required: true

  defp feed_card(%{entry: %{kind: :announcement}} = assigns) do
    ~H"""
    <FoyerComponents.announcement_card
      announcement={@entry.item}
      current_user_id={@current_user_id}
    />
    """
  end

  defp feed_card(%{entry: %{kind: :recognition}} = assigns) do
    ~H"""
    <FoyerComponents.recognition_card
      recognition={@entry.item}
      current_user_id={@current_user_id}
    />
    """
  end

  defp apply_filter(items, :announcements), do: Enum.filter(items, &(&1.kind == :announcement))
  defp apply_filter(items, :recognition), do: Enum.filter(items, &(&1.kind == :recognition))
  defp apply_filter(items, _all), do: items

  defp day_group_label(date) do
    today = Date.utc_today()
    diff = Date.diff(today, date)

    cond do
      diff == 0 -> "Today"
      diff == 1 -> "Yesterday"
      diff < 7 -> Calendar.strftime(date, "%a %-d %b")
      true -> Calendar.strftime(date, "%-d %b %Y")
    end
  end
end
