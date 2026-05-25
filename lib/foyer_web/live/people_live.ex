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
     |> assign(:colleagues, [])
     |> assign(:on_shift_ids, MapSet.new())
     |> assign(:card, nil)
     |> assign(:filter_department, "all")
     |> assign(:only_on_shift, false)
     |> assign(:departments, [])
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
    current_user_id = socket.assigns.current_scope.user.id
    on_shift_ids = FoyerWeb.LiveDeps.shifts().users_on_shift_ids()

    all_people =
      FoyerWeb.LiveDeps.accounts().list_people([])
      |> Enum.reject(fn u -> u.id == current_user_id end)
      |> Enum.map(fn u -> Map.put(u, :on_shift, MapSet.member?(on_shift_ids, u.id)) end)

    departments =
      all_people
      |> Enum.map(& &1.department)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    {:noreply,
     socket
     |> assign(:on_shift_ids, on_shift_ids)
     |> assign(:all_people, all_people)
     |> assign(:departments, departments)
     |> assign(:filter_department, "all")
     |> assign(:only_on_shift, false)
     |> assign(:colleagues, all_people)
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
  def handle_event("filter", params, socket) do
    dept = params["department"] || "all"
    only_on_shift = params["on_shift"] == "true"

    colleagues =
      socket.assigns.all_people
      |> filter_by_department(dept)
      |> filter_by_shift(only_on_shift)

    {:noreply,
     socket
     |> assign(:filter_department, dept)
     |> assign(:only_on_shift, only_on_shift)
     |> assign(:colleagues, colleagues)}
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

  defp filter_by_department(people, "all"), do: people
  defp filter_by_department(people, ""), do: people

  defp filter_by_department(people, dept),
    do: Enum.filter(people, fn u -> u.department == dept end)

  defp filter_by_shift(people, false), do: people
  defp filter_by_shift(people, true), do: Enum.filter(people, fn u -> u.on_shift end)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main class="foyer-shell">
        <FoyerComponents.desktop_rail active={:people} current_scope={@current_scope} />
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
              <% true -> %>
                <div class="foyer-page-wide space-y-6 md:pt-8">
                  <div>
                    <%!-- TODO: property.name not exposed on Scope in foyer_app — hardcoded to match desktop_rail default --%>
                    <FoyerComponents.editorial_heading>
                      {length(@colleagues)} colleagues · The Linden · Mayfair
                    </FoyerComponents.editorial_heading>
                    <p class="text-sm text-stone-600 mt-1">
                      Browse the team, find a face, send a message.
                    </p>
                  </div>

                  <form
                    id="people-filters"
                    phx-change="filter"
                    class="flex flex-wrap gap-3 items-center"
                  >
                    <select
                      name="department"
                      class="px-3 py-1.5 rounded-lg border border-stone-300 bg-[color:var(--color-parchment)] text-sm"
                    >
                      <option value="all" selected={@filter_department == "all"}>
                        All departments
                      </option>
                      <option
                        :for={d <- @departments}
                        value={d}
                        selected={@filter_department == d}
                      >
                        {d}
                      </option>
                    </select>
                    <label class="flex items-center gap-2 text-sm text-stone-700">
                      <input type="checkbox" name="on_shift" value="true" checked={@only_on_shift} />
                      On shift only
                    </label>
                  </form>

                  <div id="people-list" class="space-y-1">
                    <FoyerComponents.colleague_row
                      :for={c <- @colleagues}
                      user={c}
                      subtitle={c.title}
                      action="Message"
                      action_event="message_colleague"
                      action_value={c.id}
                    />
                    <div :if={@colleagues == []} class="text-sm text-stone-500 italic p-4">
                      No matches.
                    </div>
                  </div>
                </div>
            <% end %>

            <FoyerComponents.bottom_nav active={:people} current_scope={@current_scope} />
          </div>
        </div>
      </main>
    </Layouts.app>
    """
  end
end
