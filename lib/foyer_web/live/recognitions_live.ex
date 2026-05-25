defmodule FoyerWeb.RecognitionsLive do
  @moduledoc """
  Recognitions surface — `/recognitions` (public feed), `/recognitions/new`
  (give form), `/recognitions/:id` (show), `/recognitions/:id/edit` (author-only
  edit, stubbed). Manager scope unlocks the bonus-points tier picker on the
  give and edit forms.
  """
  use FoyerWeb, :live_view

  alias Foyer.Recognitions.Recognition
  alias FoyerWeb.FoyerComponents
  alias FoyerWeb.Scope

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:form, nil)
     |> assign(:people, [])
     |> assign(:recognition, nil)
     |> assign(:house_values, Recognition.house_values())
     |> assign(:preview_recipient_name, "")
     |> assign(:preview_body, "")
     |> assign(:preview_values, [])
     |> stream_configure(:recognitions, dom_id: &"recognition-#{&1.id}")
     |> stream(:recognitions, [])
     |> assign(:page_title, "Recognitions")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case socket.assigns.live_action do
      :index -> apply_index(socket)
      :new -> apply_new(socket)
      :show -> apply_show(socket, params)
      :edit -> apply_edit(socket, params)
    end
  end

  defp apply_index(socket) do
    feed = FoyerWeb.LiveDeps.recognitions().feed_public([])

    {:noreply,
     socket
     |> stream(:recognitions, feed, reset: true)
     |> assign(:page_title, "Recognitions")}
  end

  defp apply_new(socket) do
    {:noreply,
     socket
     |> assign(:recognition, nil)
     |> assign(:people, FoyerWeb.LiveDeps.accounts().list_people([]))
     |> assign(:form, to_form(FoyerWeb.LiveDeps.recognitions().compose_changeset(%{})))
     |> assign(:page_title, "Give recognition")}
  end

  defp apply_show(socket, %{"id" => id}) do
    scope = socket.assigns.current_scope

    try do
      r = FoyerWeb.LiveDeps.recognitions().get_recognition!(id, scope.user)

      {:noreply,
       socket
       |> assign(:recognition, r)
       |> assign(:page_title, "Recognition for " <> ((r.recipient && r.recipient.name) || ""))}
    rescue
      Ecto.NoResultsError ->
        {:noreply,
         socket
         |> put_flash(:error, "That recognition is not available to you.")
         |> push_navigate(to: ~p"/recognitions")}
    end
  end

  defp apply_edit(socket, %{"id" => id}) do
    scope = socket.assigns.current_scope

    try do
      r = FoyerWeb.LiveDeps.recognitions().get_recognition!(id, scope.user)

      {:noreply,
       socket
       |> assign(:recognition, r)
       |> assign(:people, FoyerWeb.LiveDeps.accounts().list_people([]))
       |> assign(:form, to_form(FoyerWeb.LiveDeps.recognitions().change_recognition(r, %{})))
       |> assign(:page_title, "Edit recognition")}
    rescue
      Ecto.NoResultsError ->
        {:noreply,
         socket
         |> put_flash(:error, "That recognition is not available to you.")
         |> push_navigate(to: ~p"/recognitions")}
    end
  end

  @impl true
  def handle_event("give_submit", %{"recognition" => attrs}, socket) do
    scope = socket.assigns.current_scope

    case FoyerWeb.LiveDeps.recognitions().give(scope.user, attrs) do
      {:ok, _recognition} ->
        {:noreply, push_navigate(socket, to: ~p"/recognitions")}

      {:error, :not_implemented} ->
        {:noreply,
         socket
         |> put_flash(:info, "Recognition send is not implemented in scaffold.")
         |> push_navigate(to: ~p"/recognitions")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Couldn't send recognition.")}
    end
  end

  def handle_event("edit_submit", %{"recognition" => attrs}, socket) do
    scope = socket.assigns.current_scope
    %Recognition{id: id} = recognition = socket.assigns.recognition

    case FoyerWeb.LiveDeps.recognitions().update_recognition(recognition, scope.user, attrs) do
      {:ok, _updated} ->
        {:noreply, push_navigate(socket, to: ~p"/recognitions/#{id}")}

      {:error, :not_implemented} ->
        {:noreply,
         socket
         |> put_flash(:info, "Edit not implemented in scaffold.")
         |> push_navigate(to: ~p"/recognitions/#{id}")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Couldn't update recognition.")}
    end
  end

  def handle_event("preview_change", %{"recognition" => attrs}, socket) do
    recipient_id = Map.get(attrs, "recipient_id", "")

    recipient_name =
      case Integer.parse(recipient_id) do
        {id, ""} ->
          socket.assigns.people
          |> Enum.find(fn p -> p.id == id end)
          |> case do
            %{name: name} -> name
            _ -> ""
          end

        _ ->
          ""
      end

    {:noreply,
     socket
     |> assign(:preview_recipient_name, recipient_name)
     |> assign(:preview_body, Map.get(attrs, "body", ""))
     |> assign(:preview_values, Map.get(attrs, "values", []))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main class="foyer-shell">
        <FoyerComponents.desktop_rail active={:house} current_scope={@current_scope} />
        <div class="foyer-content">
          <div class="foyer-scroll" id="recognitions">
            <%= cond do %>
              <% @live_action == :index -> %>
                <header class="flex items-start justify-between">
                  <div>
                    <div class="foyer-mono">Recognition</div>
                    <h1 class="foyer-serif text-3xl">Recognitions</h1>
                  </div>
                  <.link
                    navigate={~p"/recognitions/new"}
                    id="recognitions-new-cta"
                    class="foyer-btn forest sm"
                  >
                    <.icon name="hero-sparkles" class="size-4" /> Give recognition
                  </.link>
                </header>

                <div
                  id="recognitions-feed"
                  phx-update="stream"
                  class="flex flex-col gap-3 mt-3"
                >
                  <div :for={{dom_id, r} <- @streams.recognitions} id={dom_id}>
                    <.link
                      navigate={~p"/recognitions/#{r.id}"}
                      id={"recognition-link-#{r.id}"}
                      class="block"
                    >
                      <FoyerComponents.recognition_card recognition={r} />
                    </.link>
                  </div>
                </div>
              <% @live_action == :show and @recognition -> %>
                <.link
                  navigate={~p"/recognitions"}
                  class="foyer-btn ghost sm self-start"
                  id="back-to-recognitions"
                >
                  <.icon name="hero-arrow-left" class="size-4" /> Back
                </.link>

                <article id="recognition-detail" class="flex flex-col gap-3">
                  <div class="foyer-mono">
                    For {@recognition.recipient && @recognition.recipient.name}
                  </div>
                  <p class="foyer-serif text-2xl">{@recognition.body}</p>
                  <div class="flex items-center gap-2">
                    <FoyerComponents.avatar
                      :if={@recognition.sender}
                      initials={@recognition.sender.initials}
                      size={:sm}
                    />
                    <span>{@recognition.sender && @recognition.sender.name}</span>
                    <%= if managed_by?(@recognition, @current_scope) do %>
                      <.link
                        navigate={~p"/recognitions/#{@recognition.id}/edit"}
                        class="foyer-btn ghost sm ml-auto"
                        id="recognition-edit-link"
                      >
                        Edit
                      </.link>
                    <% end %>
                  </div>
                  <%= if @recognition.bonus_points > 0 do %>
                    <span class="foyer-tag outline">+{@recognition.bonus_points} pts</span>
                  <% end %>
                </article>
              <% @live_action == :edit and @recognition -> %>
                <.link
                  navigate={~p"/recognitions/#{@recognition.id}"}
                  class="foyer-btn ghost sm self-start"
                  id="back-to-recognition"
                >
                  <.icon name="hero-arrow-left" class="size-4" /> Back
                </.link>
                <h1 class="foyer-serif text-3xl">Edit recognition</h1>
                <.form
                  for={@form}
                  id="recognition-edit-form"
                  phx-submit="edit_submit"
                  class="flex flex-col gap-3"
                >
                  <.input
                    field={@form[:recipient_id]}
                    type="select"
                    label="To"
                    options={Enum.map(@people, &{&1.name, &1.id})}
                    prompt="Pick a colleague"
                  />
                  <.input field={@form[:body]} type="textarea" label="The story" />
                  <button class="foyer-btn forest" type="submit" id="recognition-edit-submit">
                    Save changes
                  </button>
                </.form>
              <% @live_action == :new -> %>
                <header class="flex items-start justify-between">
                  <div>
                    <div class="foyer-mono">Recognition</div>
                    <h1 class="foyer-serif text-3xl">Give recognition</h1>
                  </div>
                </header>

                <div class="foyer-content-cols">
                  <div>
                    <.form
                      for={@form}
                      id="recognize-form"
                      phx-submit="give_submit"
                      phx-change="preview_change"
                      class="flex flex-col gap-3"
                    >
                      <.input
                        field={@form[:recipient_id]}
                        type="select"
                        label="To"
                        options={Enum.map(@people, &{&1.name, &1.id})}
                        prompt="Pick a colleague"
                      />
                      <.input field={@form[:body]} type="textarea" label="The story" />

                      <fieldset class="foyer-fieldset">
                        <legend class="foyer-fieldset__label">House values</legend>
                        <div class="flex flex-wrap gap-2 mt-1">
                          <label
                            :for={v <- @house_values}
                            class="foyer-tag outline cursor-pointer"
                          >
                            <input
                              type="checkbox"
                              name="recognition[values][]"
                              value={v}
                              class="mr-1"
                              id={"value-#{v}"}
                            />
                            {String.capitalize(v)}
                          </label>
                        </div>
                      </fieldset>

                      <fieldset class="foyer-fieldset">
                        <legend class="foyer-fieldset__label">Visibility</legend>
                        <label class="flex items-center gap-2">
                          <input
                            type="radio"
                            name="recognition[public]"
                            value="true"
                            checked
                            id="visibility-public"
                          />
                          <span>Public — visible on the House feed</span>
                        </label>
                        <label class="flex items-center gap-2">
                          <input
                            type="radio"
                            name="recognition[public]"
                            value="false"
                            id="visibility-private"
                          />
                          <span>Private — just to the recipient</span>
                        </label>
                      </fieldset>

                      <%= if Scope.manager?(@current_scope) do %>
                        <fieldset class="foyer-fieldset" id="bonus-points-fieldset">
                          <legend class="foyer-fieldset__label">Bonus points</legend>
                          <div class="flex gap-2 mt-1" id="bonus-tiers">
                            <label
                              :for={pts <- [0, 10, 25, 50, 100]}
                              class="foyer-btn sm cursor-pointer"
                            >
                              <input
                                type="radio"
                                name="recognition[bonus_points]"
                                value={pts}
                                class="mr-1"
                                id={"bonus-#{pts}"}
                              /> +{pts}
                            </label>
                          </div>
                        </fieldset>
                      <% end %>

                      <button class="foyer-btn forest" type="submit" id="recognize-submit">
                        Send recognition
                      </button>
                    </.form>
                  </div>

                  <div class="hidden lg:block" id="recognition-preview-col">
                    <div class="foyer-mono mb-2">Preview</div>
                    <article
                      class="rounded-lg border p-3 flex flex-col gap-2"
                      style="border-color: var(--foyer-rule);"
                    >
                      <div class="foyer-mono">
                        For {if @preview_recipient_name != "",
                          do: @preview_recipient_name,
                          else: "…"}
                      </div>
                      <p class="foyer-serif text-lg">
                        {if @preview_body != "",
                          do: @preview_body,
                          else: "Your story will appear here…"}
                      </p>
                      <div class="flex flex-wrap gap-1">
                        <span
                          :for={v <- @preview_values}
                          class="foyer-tag outline"
                          id={"preview-value-#{v}"}
                        >
                          {String.capitalize(v)}
                        </span>
                      </div>
                    </article>
                  </div>
                </div>
            <% end %>

            <FoyerComponents.bottom_nav active={:house} current_scope={@current_scope} />
          </div>
        </div>
      </main>
    </Layouts.app>
    """
  end

  defp managed_by?(%Recognition{sender_id: sender_id}, %Scope{user: %{id: id}}),
    do: sender_id == id

  defp managed_by?(_, _), do: false
end
