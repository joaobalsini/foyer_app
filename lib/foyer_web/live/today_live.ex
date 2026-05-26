defmodule FoyerWeb.TodayLive do
  @moduledoc """
  Today surface — `/today` and `/today/end-shift`. Renders the off-shift card,
  the on-shift staff briefing, or the manager dashboard depending on
  `current_scope`. `start_shift` and `end_shift_submit` events are wired to
  real writes via `Foyer.Shifts`.
  """
  use FoyerWeb, :live_view

  alias Foyer.Shifts.Shift
  alias Foyer.Today.Briefing
  alias FoyerWeb.FoyerComponents
  alias FoyerWeb.Scope

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:briefing, nil)
     |> assign(:end_shift_form, nil)
     |> assign(:channel_options, [])
     |> assign(:just_clocked_out, false)
     |> assign(:handoff_seen, false)
     |> assign(:page_title, "Today")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    scope = socket.assigns.current_scope
    briefing = FoyerWeb.LiveDeps.today().brief_for(scope.user)

    # F.Today.21: handoff_seen tracks whether this session has already rendered
    # the handoff card once. On subsequent handle_params calls within the same
    # LiveView session (e.g. after push_navigate from end-shift), if the
    # previous render had a handoff, mark it as seen so it renders de-emphasised.
    prev_briefing = socket.assigns.briefing

    handoff_seen =
      socket.assigns.handoff_seen || (prev_briefing != nil and prev_briefing.handoff != nil)

    socket =
      socket
      |> assign(:briefing, briefing)
      |> assign(:just_clocked_out, params["state"] == "shift_complete")
      |> assign(:handoff_seen, handoff_seen)
      |> maybe_assign_end_shift_form(scope)

    {:noreply, socket}
  end

  defp maybe_assign_end_shift_form(%{assigns: %{live_action: :end_shift}} = socket, scope) do
    channels = FoyerWeb.LiveDeps.channels().list_for_user(scope.user)
    channel_options = Enum.map(channels, &{&1.name, &1.id})

    socket
    |> assign(:end_shift_form, build_end_shift_form())
    |> assign(:channel_options, channel_options)
  end

  defp maybe_assign_end_shift_form(socket, _scope), do: socket

  defp build_end_shift_form do
    %Shift{}
    |> Shift.changeset(%{handoff_note: ""})
    |> to_form(as: :shift)
  end

  @impl true
  def handle_event("start_shift", _params, socket) do
    scope = socket.assigns.current_scope

    case FoyerWeb.LiveDeps.shifts().start_shift(scope.user) do
      {:ok, _shift} ->
        {:noreply,
         socket
         |> put_flash(:info, "Shift started.")
         |> push_navigate(to: ~p"/today")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not start shift.")}
    end
  end

  def handle_event("skip_clock_out", _params, socket) do
    scope = socket.assigns.current_scope

    case scope.shift do
      nil ->
        {:noreply, put_flash(socket, :error, "No active shift to end.")}

      shift ->
        case FoyerWeb.LiveDeps.shifts().end_shift(shift, %{}) do
          {:ok, _ended} ->
            {:noreply,
             socket
             |> put_flash(:info, "Shift ended. Rest well.")
             |> push_navigate(to: ~p"/today?state=shift_complete")}

          {:error, changeset} ->
            {:noreply, assign(socket, :end_shift_form, to_form(changeset, as: :shift))}
        end
    end
  end

  def handle_event("end_shift_submit", %{"shift" => attrs}, socket) do
    scope = socket.assigns.current_scope

    case scope.shift do
      nil ->
        {:noreply, put_flash(socket, :error, "No active shift to end.")}

      shift ->
        case FoyerWeb.LiveDeps.shifts().end_shift(shift, attrs) do
          {:ok, _ended} ->
            {:noreply,
             socket
             |> put_flash(:info, "Shift ended. Rest well.")
             |> push_navigate(to: ~p"/today?state=shift_complete")}

          {:error, changeset} ->
            {:noreply, assign(socket, :end_shift_form, to_form(changeset, as: :shift))}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main class="foyer-shell">
        <FoyerComponents.desktop_rail
          active={:today}
          current_scope={@current_scope}
          chat_unread_count={@chat_unread_count}
        />
        <div class="foyer-content">
          <FoyerComponents.desktop_topbar current_scope={@current_scope} page_title={@page_title} />
          <div class="foyer-scroll foyer-page-wide" id="today">
            <header>
              <div class="foyer-mono">{header_eyebrow(@current_scope)}</div>
              <h1 class="foyer-serif text-3xl">{greeting(@current_scope)}</h1>
            </header>

            <%= cond do %>
              <% not @current_scope.on_shift? -> %>
                <section
                  id="off-shift"
                  class="rounded-lg p-6 flex flex-col gap-5"
                  style="background: var(--foyer-cream-deep);"
                >
                  <%= if @just_clocked_out do %>
                    <div id="shift-complete-banner" class="flex flex-col gap-4">
                      <span class="foyer-tag moss self-start">Shift complete</span>
                      <h2 class="foyer-serif text-2xl">Eight hours well held.</h2>
                      <p class="foyer-mono">Notifications will quiet down.</p>
                      <div class="foyer-mono text-sm flex flex-col gap-1">
                        <div>Announcements acked</div>
                        <div>What happens next: start your next shift when you're ready.</div>
                      </div>
                    </div>
                  <% else %>
                    <div id="off-shift-banner" class="flex flex-col gap-4">
                      <span class="foyer-tag outline self-start">
                        Off shift · notifications paused
                      </span>
                      <p class="foyer-serif text-xl leading-snug">
                        You're off the clock.<br /><em>Rest is part of the work.</em>
                      </p>
                      <p>You won't receive notifications until you start your next shift.</p>
                      <div class="flex flex-col gap-1">
                        <div class="foyer-mono">
                          While you were off · {Briefing.waiting_total(@briefing)} waiting
                        </div>
                        <div :if={Briefing.waiting_total(@briefing) > 0} class="foyer-mono text-sm">
                          {waiting_breakdown(@briefing)}
                        </div>
                      </div>
                    </div>
                  <% end %>
                  <button
                    class="foyer-btn forest"
                    phx-click="start_shift"
                    id="start-shift-btn"
                    aria-label="Start shift"
                  >
                    <span class="foyer-pulse"></span>Start shift
                  </button>
                </section>
              <% Scope.manager?(@current_scope) -> %>
                <section id="manager-today" class="flex flex-col gap-3">
                  <div class="flex items-center gap-3">
                    <span class="foyer-pulse"></span>
                    <div>On shift · {@current_scope.user.title}</div>
                    <.link
                      patch={~p"/today/end-shift"}
                      class="foyer-btn sm ml-auto"
                      id="end-shift-link"
                    >
                      End shift
                    </.link>
                  </div>
                  <.link navigate={~p"/announcements/new"} id="compose-cta" class="foyer-btn forest">
                    <.icon name="hero-pencil-square" class="size-4" /> New announcement
                  </.link>

                  <div
                    :if={@briefing.handoff}
                    id="handoff-card"
                    class={handoff_card_class(@handoff_seen)}
                  >
                    <div class="foyer-mono">Handoff from your last shift</div>
                    <div class="flex items-center gap-2 mt-2">
                      <FoyerComponents.avatar
                        initials={@briefing.handoff.user.initials}
                        size={:sm}
                      />
                      <div>
                        <div>{@briefing.handoff.user.name}</div>
                        <div class="foyer-mono">
                          Night · ended {format_time(@briefing.handoff.ended_at)}
                        </div>
                      </div>
                    </div>
                    <p class="foyer-serif mt-2">"{@briefing.handoff.handoff_note}"</p>
                  </div>

                  <div :if={@briefing.needs_ack != []} id="manager-needs-ack">
                    <div class="foyer-mono">Needs your acknowledgement</div>
                    <div :for={a <- @briefing.needs_ack} id={"needs-ack-#{a.id}"} class="mt-2">
                      <FoyerComponents.announcement_card
                        announcement={a}
                        current_user_id={@current_scope.user.id}
                      />
                    </div>
                  </div>

                  <div :if={@briefing.own_announcements != []} id="manager-live-posts">
                    <div class="foyer-mono">Your live posts</div>
                    <div
                      :for={a <- @briefing.own_announcements}
                      id={"live-post-#{a.id}"}
                      class="mt-2"
                    >
                      <FoyerComponents.announcement_card
                        announcement={a}
                        current_user_id={@current_scope.user.id}
                      />
                    </div>
                  </div>

                  <div :if={@briefing.recent_recognitions != []} id="recent-recognition">
                    <div class="foyer-mono">Recognition for you</div>
                    <div
                      :for={r <- @briefing.recent_recognitions}
                      id={"recognition-#{r.id}"}
                      class="rounded-lg border p-3 mt-2"
                      style="border-color: var(--foyer-rule);"
                    >
                      <div class="flex items-center gap-2">
                        <FoyerComponents.avatar initials={r.sender.initials} size={:sm} />
                        <span class="foyer-mono">{r.sender.name}</span>
                      </div>
                      <p class="foyer-serif mt-2">{r.body}</p>
                      <div class="flex items-center justify-between gap-2 mt-2">
                        <div class="flex gap-1 flex-wrap">
                          <span :for={v <- r.values} class="foyer-tag outline">{v}</span>
                        </div>
                        <.link
                          :if={r.sender_id == @current_scope.user.id}
                          navigate={~p"/recognitions/#{r.id}"}
                          class="foyer-btn sm shrink-0"
                          id={"today-recognition-view-#{r.id}"}
                        >
                          View
                        </.link>
                      </div>
                    </div>
                  </div>
                </section>
              <% true -> %>
                <section id="on-shift-staff" class="flex flex-col gap-3">
                  <div class="flex items-center gap-3">
                    <span class="foyer-pulse"></span>
                    <div>On shift · {@current_scope.user.title}</div>
                    <.link
                      patch={~p"/today/end-shift"}
                      class="foyer-btn sm ml-auto"
                      id="end-shift-link"
                    >
                      End shift
                    </.link>
                  </div>

                  <div
                    :if={@briefing.handoff}
                    id="handoff-card"
                    class={handoff_card_class(@handoff_seen)}
                  >
                    <div class="foyer-mono">Handoff from your last shift</div>
                    <div class="flex items-center gap-2 mt-2">
                      <FoyerComponents.avatar
                        initials={@briefing.handoff.user.initials}
                        size={:sm}
                      />
                      <div>
                        <div>{@briefing.handoff.user.name}</div>
                        <div class="foyer-mono">
                          Night · ended {format_time(@briefing.handoff.ended_at)}
                        </div>
                      </div>
                    </div>
                    <p class="foyer-serif mt-2">"{@briefing.handoff.handoff_note}"</p>
                  </div>

                  <div :if={@briefing.needs_ack != []} id="needs-ack">
                    <div class="foyer-mono">Needs your acknowledgement</div>
                    <div :for={a <- @briefing.needs_ack} id={"needs-ack-#{a.id}"} class="mt-2">
                      <FoyerComponents.announcement_card
                        announcement={a}
                        current_user_id={@current_scope.user.id}
                      />
                    </div>
                  </div>

                  <div :if={@briefing.recent_recognitions != []} id="recent-recognition">
                    <div class="foyer-mono">Recognition for you</div>
                    <div
                      :for={r <- @briefing.recent_recognitions}
                      id={"recognition-#{r.id}"}
                      class="rounded-lg border p-3 mt-2"
                      style="border-color: var(--foyer-rule);"
                    >
                      <div class="flex items-center gap-2">
                        <FoyerComponents.avatar initials={r.sender.initials} size={:sm} />
                        <span class="foyer-mono">{r.sender.name}</span>
                      </div>
                      <p class="foyer-serif mt-2">{r.body}</p>
                      <div class="flex items-center justify-between gap-2 mt-2">
                        <div class="flex gap-1 flex-wrap">
                          <span :for={v <- r.values} class="foyer-tag outline">{v}</span>
                        </div>
                        <.link
                          :if={r.sender_id == @current_scope.user.id}
                          navigate={~p"/recognitions/#{r.id}"}
                          class="foyer-btn sm shrink-0"
                          id={"today-recognition-view-#{r.id}"}
                        >
                          View
                        </.link>
                      </div>
                    </div>
                  </div>
                </section>
            <% end %>

            <%= if @live_action == :end_shift do %>
              <div
                id="end-shift-modal"
                class="rounded-lg border p-4 mt-4"
                style="border-color: var(--foyer-rule);"
              >
                <h2 class="foyer-serif text-xl">Anything the next shift needs to know?</h2>
                <.form
                  for={@end_shift_form}
                  id="end-shift-form"
                  phx-submit="end_shift_submit"
                  class="flex flex-col gap-3 mt-3"
                >
                  <.input
                    field={@end_shift_form[:handoff_note]}
                    type="textarea"
                    label="Handoff note"
                  />
                  <.input
                    field={@end_shift_form[:handoff_channel_id]}
                    type="select"
                    label="Send to channel"
                    options={[{"— no channel —", nil} | @channel_options]}
                    id="handoff-channel-select"
                  />
                  <button class="foyer-btn forest sm" type="submit">Clock out</button>
                  <button
                    type="button"
                    phx-click="skip_clock_out"
                    id="skip-clock-out"
                    class="foyer-mono text-sm text-center"
                  >
                    Skip · clock out
                  </button>
                </.form>
              </div>
            <% end %>

            <FoyerComponents.bottom_nav
              active={:today}
              current_scope={@current_scope}
              chat_unread_count={@chat_unread_count}
            />
          </div>
        </div>
      </main>
    </Layouts.app>
    """
  end

  defp header_eyebrow(%Scope{} = scope) do
    "The Linden · #{scope.user.department}"
  end

  defp greeting(%Scope{} = scope) do
    "Good morning, #{first_name(scope.user.name)}"
  end

  defp first_name(nil), do: "there"

  defp first_name(name) when is_binary(name) do
    name
    |> String.split(" ", parts: 2)
    |> List.first()
  end

  defp format_time(nil), do: ""

  defp format_time(%DateTime{} = dt) do
    dt
    |> DateTime.to_time()
    |> Time.to_string()
    |> String.slice(0, 5)
  end

  defp handoff_card_class(true) do
    "rounded-lg border p-3 opacity-60"
  end

  defp handoff_card_class(false) do
    "rounded-lg border p-3"
  end

  defp waiting_breakdown(%Briefing{} = b) do
    parts =
      [
        if(b.waiting_announcements > 0, do: "#{b.waiting_announcements} announcements"),
        if(b.waiting_messages > 0, do: "#{b.waiting_messages} messages"),
        if(b.waiting_recognitions > 0, do: "#{b.waiting_recognitions} recognitions")
      ]
      |> Enum.reject(&is_nil/1)

    Enum.join(parts, " · ")
  end
end
