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
     |> assign(:channels, [])
     |> assign(:page_title, "Today")}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    scope = socket.assigns.current_scope
    briefing = FoyerWeb.LiveDeps.today().brief_for(scope.user)

    channels = FoyerWeb.LiveDeps.channels().list_for_user(scope.user)

    socket =
      socket
      |> assign(:briefing, briefing)
      |> assign(:channels, channels)
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
    end_shift(socket, attrs)
  end

  def handle_event("end_shift_without_handoff", _params, socket) do
    end_shift(socket, %{"handoff_note" => ""})
  end

  defp end_shift(socket, attrs) do
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
        <FoyerComponents.desktop_rail
          active={:today}
          current_scope={@current_scope}
          chat_unread_count={@chat_unread_count}
        />
        <div class="foyer-content">
          <FoyerComponents.desktop_topbar current_scope={@current_scope} page_title={@page_title} />
          <div class="foyer-scroll" id="today">
            <div
              :if={not @current_scope.on_shift? and @live_action != :end_shift}
              id="off-shift"
              class="foyer-page-narrow space-y-6"
            >
              <div>
                <FoyerComponents.editorial_heading>
                  Hello, {first_name(@current_scope.user.name)}.
                </FoyerComponents.editorial_heading>
                <p class="foyer-serif text-2xl italic mt-1">You're off the clock.</p>
                <p class="text-sm mt-2">Rest is part of the work.</p>
              </div>

              <div class="flex items-center gap-3">
                <FoyerComponents.status_pill kind={:off_shift} />
                <button
                  phx-click="start_shift"
                  class="foyer-btn sm"
                  id="start-shift-btn"
                >
                  Start shift
                </button>
              </div>

              <section id="queued" class="space-y-3">
                <FoyerComponents.section_label label={"Quietly held for you · #{@briefing.waiting_count} waiting"} />
                <p class="text-xs italic" style="color: var(--foyer-stone);">
                  These will be marked unread the moment you start your shift.
                </p>
              </section>
            </div>

            <div
              :if={
                @current_scope.on_shift? and not Scope.manager?(@current_scope) and
                  @live_action != :end_shift
              }
              id="today-on-shift-staff"
              class="foyer-page-narrow space-y-6"
            >
              <div class="flex items-start justify-between gap-3">
                <div>
                  <FoyerComponents.editorial_heading>
                    Good morning, {first_name(@current_scope.user.name)}.
                  </FoyerComponents.editorial_heading>
                  <p class="foyer-serif text-2xl mt-1">Today · your morning briefing</p>
                </div>
                <div class="flex flex-col items-end gap-2">
                  <FoyerComponents.status_pill kind={:on_shift} />
                  <.link
                    patch={~p"/today/end-shift"}
                    class="foyer-btn sm"
                    id="end-shift-link"
                  >
                    End shift
                  </.link>
                </div>
              </div>

              <section :if={@briefing.handoff} id="handoff" class="space-y-3">
                <FoyerComponents.section_label label={"Handoff from your last shift · ended #{FoyerComponents.format_time(@briefing.handoff.ended_at)}"} />
                <article
                  class="rounded-lg border p-4 text-sm space-y-1"
                  style="background: var(--foyer-cream-deep); border-color: var(--foyer-rule);"
                >
                  <p>{@briefing.handoff.handoff_note}</p>
                </article>
              </section>

              <section id="needs-ack" class="space-y-3">
                <FoyerComponents.section_label label={"Needs your acknowledgement · #{length(@briefing.needs_ack)} to go"} />
                <div
                  :if={@briefing.needs_ack == []}
                  class="text-sm italic"
                  style="color: var(--foyer-stone);"
                >
                  You're caught up.
                </div>
                <FoyerComponents.announcement_card
                  :for={ann <- @briefing.needs_ack}
                  announcement={ann}
                  current_user_id={@current_scope.user.id}
                />
              </section>

              <section
                :if={@briefing.recent_recognition != []}
                id="recognition-received"
                class="space-y-3"
              >
                <FoyerComponents.section_label label="Recognition received" />
                <FoyerComponents.recognition_card
                  :for={rec <- Enum.take(@briefing.recent_recognition, 2)}
                  recognition={rec}
                />
              </section>
            </div>

            <div
              :if={
                @current_scope.on_shift? and Scope.manager?(@current_scope) and
                  @live_action != :end_shift
              }
              id="today-on-shift-manager"
              class="foyer-page-narrow space-y-6"
            >
              <div class="flex items-start justify-between gap-3">
                <div>
                  <FoyerComponents.editorial_heading>
                    Good morning, {first_name(@current_scope.user.name)}.
                  </FoyerComponents.editorial_heading>
                  <p class="foyer-serif text-2xl mt-1">Today · your morning briefing</p>
                </div>
                <div class="flex flex-col items-end gap-2">
                  <FoyerComponents.status_pill kind={:on_shift} />
                  <.link
                    patch={~p"/today/end-shift"}
                    class="foyer-btn sm"
                    id="end-shift-link"
                  >
                    End shift
                  </.link>
                </div>
              </div>

              <section id="acks-you-owe" class="space-y-2">
                <FoyerComponents.section_label label="Acks you owe others" />
                <div
                  :if={@briefing.needs_ack == []}
                  class="text-sm italic"
                  style="color: var(--foyer-stone);"
                >
                  Nothing waiting on you right now. You're caught up.
                </div>
                <FoyerComponents.announcement_card
                  :for={ann <- @briefing.needs_ack}
                  announcement={ann}
                  current_user_id={@current_scope.user.id}
                />
              </section>

              <section id="new-announcement" class="space-y-2">
                <FoyerComponents.section_label label="Publish to your team" />
                <.link navigate={~p"/announcements/new"} id="compose-cta" class="foyer-btn forest">
                  <.icon name="hero-pencil-square" class="size-4" /> New announcement
                </.link>
              </section>
            </div>

            <%= if @live_action == :end_shift do %>
              <div
                id="end-shift-modal"
                class="foyer-page-narrow space-y-5 md:pt-8"
              >
                <div>
                  <FoyerComponents.editorial_heading>
                    Shift complete.
                  </FoyerComponents.editorial_heading>
                  <p class="foyer-serif text-2xl italic">Leave a note for the next shift?</p>
                  <p class="text-sm text-stone-500">
                    Started at {FoyerComponents.format_time(
                      @current_scope.shift && @current_scope.shift.started_at
                    )}
                  </p>
                </div>
                <.form
                  for={@end_shift_form}
                  id="end-shift-form"
                  phx-submit="end_shift_submit"
                  class="flex flex-col gap-4"
                >
                  <.input
                    field={@end_shift_form[:handoff_note]}
                    type="textarea"
                    label="Handoff note"
                    placeholder="What does the next shift need to know?"
                  />
                  <.input
                    field={@end_shift_form[:handoff_channel_id]}
                    type="select"
                    label="Who should see this?"
                    options={Enum.map(@channels, &{&1.name, &1.id})}
                  />
                  <button class="foyer-btn forest w-full" type="submit">
                    End shift with handoff
                  </button>
                  <button
                    type="button"
                    phx-click="end_shift_without_handoff"
                    id="end-shift-no-handoff"
                    class="foyer-btn ghost w-full border-[var(--foyer-rule)]"
                  >
                    End shift, no handoff
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

  defp first_name(nil), do: "there"

  defp first_name(name) when is_binary(name) do
    name
    |> String.split(" ", parts: 2)
    |> List.first()
  end
end
