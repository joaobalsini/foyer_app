defmodule FoyerWeb.TodayLive do
  @moduledoc """
  Today surface — `/today` and `/today/end-shift`. Renders the off-shift card,
  the on-shift staff briefing, or the manager dashboard depending on
  `current_scope`. `start_shift` and `end_shift_submit` events are wired to
  real writes via `Foyer.Shifts`.
  """
  use FoyerWeb, :live_view

  alias Foyer.Shifts.Shift
  alias FoyerWeb.FoyerComponents
  alias FoyerWeb.Scope

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:briefing, nil)
     |> assign(:end_shift_form, nil)
     |> assign(:page_title, "Today")}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    scope = socket.assigns.current_scope
    briefing = FoyerWeb.LiveDeps.today().brief_for(scope.user)

    socket =
      socket
      |> assign(:briefing, briefing)
      |> maybe_assign_end_shift_form()

    {:noreply, socket}
  end

  defp maybe_assign_end_shift_form(%{assigns: %{live_action: :end_shift}} = socket) do
    assign(socket, :end_shift_form, build_end_shift_form())
  end

  defp maybe_assign_end_shift_form(socket), do: socket

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
             |> push_navigate(to: ~p"/today")}

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
        <FoyerComponents.desktop_rail active={:today} current_scope={@current_scope} />
        <div class="foyer-content">
          <div class="foyer-scroll md:max-w-2xl md:mx-auto" id="today">
            <header class="flex items-start justify-between">
              <div>
                <div class="foyer-mono">{header_eyebrow(@current_scope)}</div>
                <h1 class="foyer-serif text-3xl">{greeting(@current_scope)}</h1>
              </div>
              <div class="flex gap-2">
                <button aria-label="Search" class="foyer-btn ghost sm" id="today-search">
                  <.icon name="hero-magnifying-glass" class="size-5" />
                </button>
                <button aria-label="Notifications" class="foyer-btn ghost sm" id="today-bell">
                  <.icon name="hero-bell" class="size-5" />
                </button>
              </div>
            </header>

            <%= cond do %>
              <% not @current_scope.on_shift? -> %>
                <section
                  id="off-shift"
                  class="rounded-lg p-4 flex flex-col gap-3"
                  style="background: var(--foyer-cream-deep);"
                >
                  <div class="flex items-center gap-2">
                    <span class="foyer-tag outline">Off shift · notifications paused</span>
                  </div>
                  <p class="foyer-serif text-xl">
                    You're off the clock.<br /><em>Rest is part of the work.</em>
                  </p>
                  <p>You won't receive notifications until you start your next shift.</p>
                  <button class="foyer-btn forest" phx-click="start_shift" id="start-shift-btn">
                    <span class="foyer-pulse"></span>Start shift
                  </button>
                  <div class="foyer-mono">
                    While you were off · {@briefing.waiting_count} waiting
                  </div>
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

                  <div :if={@briefing.needs_ack != []} id="manager-needs-ack">
                    <div class="foyer-mono">Needs your acknowledgement</div>
                    <.link
                      :for={a <- @briefing.needs_ack}
                      navigate={~p"/announcements/#{a.id}"}
                      id={"manager-needs-ack-#{a.id}"}
                      class="block rounded-lg border p-3 mt-2"
                      style="border-color: var(--foyer-rule);"
                    >
                      <span class="foyer-tag claret">Pinned · Action</span>
                      <div class="foyer-serif mt-2">{a.title}</div>
                    </.link>
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
                    class="rounded-lg border p-3"
                    style="border-color: var(--foyer-rule);"
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
                    <.link
                      :for={a <- @briefing.needs_ack}
                      navigate={~p"/announcements/#{a.id}"}
                      id={"needs-ack-#{a.id}"}
                      class="block rounded-lg border p-3 mt-2"
                      style="border-color: var(--foyer-rule);"
                    >
                      <span class="foyer-tag claret">Pinned · Action</span>
                      <div class="foyer-serif mt-2">{a.title}</div>
                      <div class="flex items-center gap-2 mt-2 text-sm">
                        <FoyerComponents.avatar
                          :if={a.author}
                          initials={a.author.initials}
                          size={:sm}
                        />
                        <span>{a.author && a.author.name} · {a.channel && a.channel.name}</span>
                      </div>
                    </.link>
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
                  <button class="foyer-btn forest sm" type="submit">Clock out</button>
                </.form>
              </div>
            <% end %>

            <FoyerComponents.bottom_nav active={:today} current_scope={@current_scope} />
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
end
