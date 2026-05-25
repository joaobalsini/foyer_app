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
     |> assign(:preview_bonus_points, nil)
     |> assign(:sent?, false)
     |> assign(:sent_recognition, nil)
     |> assign(:grace_state, :open)
     |> assign(:grace_deadline_ms, nil)
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
     |> assign(:sent?, false)
     |> assign(:sent_recognition, nil)
     |> assign(:grace_state, :open)
     |> assign(:grace_deadline_ms, nil)
     |> assign(:people, FoyerWeb.LiveDeps.accounts().list_people([]))
     |> assign(:form, to_form(FoyerWeb.LiveDeps.recognitions().compose_changeset(%{})))
     |> assign(:preview_recipient_name, "")
     |> assign(:preview_body, "")
     |> assign(:preview_values, [])
     |> assign(:preview_bonus_points, nil)
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
      {:ok, recognition} ->
        recipient_name =
          socket.assigns.people
          |> Enum.find(fn p -> p.id == recognition.recipient_id end)
          |> case do
            %{name: name} -> name
            _ -> ""
          end

        {:noreply,
         socket
         |> assign(:sent?, true)
         |> assign(:sent_recognition, recognition)
         |> assign(:grace_state, :open)
         |> assign(:grace_deadline_ms, nil)
         |> assign(:preview_recipient_name, recipient_name)}

      {:error, :self_recognition} ->
        {:noreply, put_flash(socket, :error, "Choose someone else to recognize.")}

      {:error, :invalid_point_tier} ->
        {:noreply, put_flash(socket, :error, "Choose one of the available point tiers.")}

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

      {:error, :outside_grace_window} ->
        {:noreply, put_flash(socket, :error, "That recognition can no longer be edited.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Only the sender can edit this recognition.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Couldn't update recognition.")}
    end
  end

  def handle_event("remove", _params, socket) do
    scope = socket.assigns.current_scope
    recognition = socket.assigns.recognition

    case FoyerWeb.LiveDeps.recognitions().remove_recognition(recognition, scope.user) do
      {:ok, _removed} ->
        {:noreply,
         socket
         |> put_flash(:info, "Recognition removed.")
         |> push_navigate(to: ~p"/recognitions")}

      {:error, :outside_grace_window} ->
        {:noreply, put_flash(socket, :error, "That recognition can no longer be removed.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Only the sender can remove this recognition.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Couldn't remove recognition.")}
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

    bonus_points =
      case Map.get(attrs, "bonus_points") do
        nil -> nil
        "" -> nil
        v -> elem(Integer.parse(v), 0)
      end

    {:noreply,
     socket
     |> assign(:preview_recipient_name, recipient_name)
     |> assign(:preview_body, Map.get(attrs, "body", ""))
     |> assign(:preview_values, Map.get(attrs, "values", []))
     |> assign(:preview_bonus_points, bonus_points)}
  end

  def handle_event("set_bonus", %{"bonus" => "clear"}, socket) do
    {:noreply, assign(socket, :preview_bonus_points, nil)}
  end

  def handle_event("set_bonus", %{"bonus" => bonus}, socket) do
    {:noreply, assign(socket, :preview_bonus_points, String.to_integer(bonus))}
  end

  def handle_event("new_recognition", _params, socket) do
    {:noreply,
     socket
     |> assign(:sent?, false)
     |> assign(:sent_recognition, nil)
     |> assign(:grace_state, :open)
     |> assign(:grace_deadline_ms, nil)
     |> assign(:preview_recipient_name, "")
     |> assign(:preview_body, "")
     |> assign(:preview_values, [])
     |> assign(:preview_bonus_points, nil)
     |> assign(:form, to_form(FoyerWeb.LiveDeps.recognitions().compose_changeset(%{})))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main class="foyer-shell">
        <FoyerComponents.desktop_rail active={:house} current_scope={@current_scope} />
        <div class="foyer-content">
          <div class="foyer-scroll" id="recognitions">
            <FoyerComponents.desktop_topbar current_scope={@current_scope} page_title={@page_title} />
            <%= cond do %>
              <% @live_action == :index -> %>
                <header class="flex items-start justify-between">
                  <div>
                    <div class="foyer-mono">Recognition</div>
                    <FoyerComponents.editorial_heading>
                      Recognitions
                    </FoyerComponents.editorial_heading>
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
                  <div class="flex flex-wrap gap-2">
                    <span :for={value <- @recognition.values} class="foyer-tag outline">
                      {String.capitalize(value)}
                    </span>
                    <span :if={!@recognition.public} class="foyer-tag outline">Private</span>
                    <button
                      :if={
                        managed_by?(@recognition, @current_scope) and
                          FoyerWeb.LiveDeps.recognitions().within_grace_window?(@recognition)
                      }
                      class="foyer-btn sm ml-auto"
                      phx-click="remove"
                      id="recognition-remove-btn"
                      type="button"
                    >
                      <.icon name="hero-trash" class="size-4" /> Remove
                    </button>
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
                <FoyerComponents.editorial_heading>
                  Edit recognition
                </FoyerComponents.editorial_heading>
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
                  <fieldset class="foyer-fieldset">
                    <legend class="foyer-fieldset__label">House values</legend>
                    <div class="flex flex-wrap gap-2 mt-1">
                      <label :for={v <- @house_values} class="foyer-tag outline cursor-pointer">
                        <input
                          type="checkbox"
                          name="recognition[values][]"
                          value={v}
                          checked={v in (@recognition.values || [])}
                          class="mr-1"
                          id={"edit-value-#{v}"}
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
                        checked={@recognition.public}
                        id="edit-visibility-public"
                      />
                      <span>Public</span>
                    </label>
                    <label class="flex items-center gap-2">
                      <input
                        type="radio"
                        name="recognition[public]"
                        value="false"
                        checked={!@recognition.public}
                        id="edit-visibility-private"
                      />
                      <span>Private</span>
                    </label>
                  </fieldset>
                  <button class="foyer-btn forest" type="submit" id="recognition-edit-submit">
                    Save changes
                  </button>
                </.form>
              <% @live_action == :new and @sent? -> %>
                <%!-- Sent / grace-window state --%>
                <div
                  id="post-send"
                  class="card-parchment p-6 space-y-3 border-l-4 border-[color:var(--foyer-forest)]"
                >
                  <%!-- TODO: wire JS GraceCountdown hook once context exposes inserted_at --%>
                  <FoyerComponents.editorial_heading>
                    Recognition sent.
                  </FoyerComponents.editorial_heading>
                  <p class="text-sm text-stone-600">
                    Recognition for <span class="font-medium">{@preview_recipient_name}</span>
                    <span :if={
                      (Scope.manager?(@current_scope) and
                         @preview_bonus_points) && @preview_bonus_points > 0
                    }>
                      {" · #{@preview_bonus_points} Foyer points"}
                    </span>
                    — delivered.
                  </p>
                  <p
                    :if={@grace_state == :open}
                    id="grace-countdown"
                    class="text-xs text-stone-500 italic"
                  >
                    60s to edit or remove.
                  </p>
                  <p
                    :if={@grace_state == :expired}
                    data-grace-expired
                    class="text-xs text-stone-500 italic"
                  >
                    Edit window closed.
                  </p>
                  <div :if={@grace_state == :open} class="flex gap-2 pt-2">
                    <.link
                      :if={@sent_recognition}
                      navigate={~p"/recognitions/#{@sent_recognition.id}/edit"}
                      class="foyer-btn sm"
                      id="edit-recognition"
                    >
                      Edit
                    </.link>
                    <button
                      :if={@sent_recognition}
                      type="button"
                      class="foyer-btn ghost sm"
                      id="remove-recognition"
                      disabled
                    >
                      Remove
                    </button>
                    <.link navigate={~p"/recognitions"} class="foyer-btn ghost sm">
                      See it in the feed
                    </.link>
                  </div>
                  <div :if={@grace_state == :expired} class="flex gap-2 pt-2">
                    <p class="text-xs text-stone-500 italic">Edit window closed.</p>
                    <button
                      type="button"
                      phx-click="new_recognition"
                      class="foyer-btn ghost sm"
                    >
                      + Another
                    </button>
                  </div>
                </div>
              <% @live_action == :new -> %>
                <div class="space-y-4">
                  <div>
                    <FoyerComponents.editorial_heading>
                      Give recognition
                    </FoyerComponents.editorial_heading>
                    <p class="text-sm text-stone-500 mt-2">
                      Shout-out a colleague. Write it like you'd tell it at staff dinner. Specific moments land.
                    </p>
                  </div>
                </div>

                <div class="grid lg:grid-cols-[1fr_360px] gap-8 mt-6" id="recognition-form-root">
                  <div class="space-y-6">
                    <form
                      id="recognize-form"
                      phx-submit="give_submit"
                      phx-change="preview_change"
                      class="space-y-5"
                    >
                      <input type="hidden" name="recognition[_unused]" value="" />

                      <div>
                        <FoyerComponents.section_label label="Recipient" class="block mb-1" />
                        <select
                          name="recognition[recipient_id]"
                          id="recognition-recipient"
                          class="w-full px-3 py-2 rounded-lg border border-stone-300 bg-[color:var(--foyer-cream-deep)] text-sm"
                        >
                          <option value="">— Select a colleague —</option>
                          <option :for={p <- @people} value={p.id}>
                            {p.name}
                          </option>
                        </select>
                      </div>

                      <div>
                        <FoyerComponents.section_label label="House values" class="block mb-2" />
                        <div class="flex flex-wrap gap-2" id="house-values">
                          <input type="hidden" name="recognition[values][]" value="" />
                          <label
                            :for={v <- @house_values}
                            id={"house-value-chip-#{v}"}
                            class={[
                              "px-3 py-1 rounded-full text-xs font-medium border transition cursor-pointer select-none",
                              v in @preview_values &&
                                "bg-[var(--foyer-forest)] text-[var(--foyer-cream)] border-[var(--foyer-forest)]",
                              v not in @preview_values &&
                                "bg-transparent text-stone-700 border-stone-300"
                            ]}
                          >
                            <input
                              type="checkbox"
                              name="recognition[values][]"
                              value={v}
                              checked={v in @preview_values}
                              class="sr-only"
                            />
                            {String.capitalize(v)}
                          </label>
                        </div>
                        <p class="text-xs text-stone-500 mt-1 italic">Pick one or more.</p>
                      </div>

                      <div>
                        <FoyerComponents.section_label label="The story" class="block mb-1" />
                        <textarea
                          name="recognition[body]"
                          id="recognition-body"
                          rows="6"
                          placeholder="Stayed past 23:00 fixing the Garden Suite shower so the Yamada family could enjoy it on arrival…"
                          class="w-full px-4 py-3 rounded-lg border border-stone-300 bg-[color:var(--foyer-cream-deep)] text-sm leading-relaxed"
                        >{@preview_body}</textarea>
                      </div>

                      <fieldset class="space-y-2">
                        <legend class="foyer-mono">Visibility</legend>
                        <label class="flex items-start gap-2 text-sm">
                          <input
                            type="radio"
                            name="recognition[public]"
                            value="true"
                            checked
                            id="visibility-public"
                            class="mt-1"
                          />
                          <div>
                            <div class="font-medium">Public</div>
                            <div class="text-xs text-stone-500">Posted in The House.</div>
                          </div>
                        </label>
                        <label class="flex items-start gap-2 text-sm">
                          <input
                            type="radio"
                            name="recognition[public]"
                            value="false"
                            id="visibility-private"
                            class="mt-1"
                          />
                          <div>
                            <div class="font-medium">Private</div>
                            <div class="text-xs text-stone-500">Only the recipient sees it.</div>
                          </div>
                        </label>
                      </fieldset>

                      <fieldset
                        :if={Scope.manager?(@current_scope)}
                        id="bonus-points"
                        class="card-parchment p-4 space-y-3"
                      >
                        <legend class="foyer-mono">Bonus points</legend>
                        <p class="text-xs text-stone-500">
                          Foyer points roll up to staff rewards — time off, meals, charitable donations.
                        </p>
                        <div class="flex gap-2 flex-wrap">
                          <button
                            :for={tier <- [25, 50, 100]}
                            type="button"
                            phx-click="set_bonus"
                            phx-value-bonus={tier}
                            data-bonus-tier={tier}
                            class={[
                              "px-3 py-1 rounded-full text-sm font-medium border",
                              @preview_bonus_points == tier &&
                                "bg-[var(--foyer-forest)] text-[var(--foyer-cream)] border-[var(--foyer-forest)]",
                              @preview_bonus_points != tier &&
                                "bg-transparent text-stone-700 border-stone-300"
                            ]}
                          >
                            +{tier}
                          </button>
                          <input
                            type="hidden"
                            name="recognition[bonus_points]"
                            value={@preview_bonus_points || 0}
                          />
                          <button
                            :if={@preview_bonus_points}
                            type="button"
                            phx-click="set_bonus"
                            phx-value-bonus="clear"
                            class="text-xs text-stone-500 underline"
                          >
                            clear
                          </button>
                        </div>
                      </fieldset>

                      <p
                        :if={not Scope.manager?(@current_scope)}
                        id="staff-bonus-note"
                        class="text-xs text-stone-500 italic card-parchment p-3"
                      >
                        Recognition with bonus points is given by department heads. Your shout-out still lands on their phone and shows in The House.
                      </p>

                      <div class="flex gap-2 pt-4 border-t border-stone-200/70">
                        <button type="submit" class="foyer-btn forest" id="recognize-submit">
                          Send recognition
                        </button>
                        <.link navigate={~p"/recognitions"} class="foyer-btn ghost sm">
                          Cancel
                        </.link>
                      </div>
                    </form>
                  </div>

                  <aside id="recognition-preview" class="lg:sticky lg:top-6 self-start space-y-3">
                    <FoyerComponents.section_label label="Preview · The House feed" />
                    <article class="card-parchment p-5 space-y-3 max-w-[360px]">
                      <div class="flex flex-wrap gap-1.5" data-preview-values>
                        <FoyerComponents.house_value_chip
                          :for={v <- @preview_values}
                          value={v}
                          selected
                        />
                        <span :if={@preview_values == []} class="text-xs text-stone-400 italic">
                          Add values…
                        </span>
                      </div>
                      <p class="foyer-serif text-base italic leading-snug">
                        "{if @preview_body == "", do: "Tell the story…", else: @preview_body}"
                      </p>
                      <div class="flex items-center justify-between text-xs text-stone-500 pt-1">
                        <div class="flex items-center gap-2">
                          <FoyerComponents.avatar
                            initials={@current_scope.user.initials}
                            size={:sm}
                          />
                          <span>{@current_scope.user.name}</span>
                          <span>→</span>
                          <span class="font-medium text-stone-700">
                            {if @preview_recipient_name == "",
                              do: "…",
                              else: @preview_recipient_name}
                          </span>
                        </div>
                        <span
                          :if={
                            (Scope.manager?(@current_scope) and
                               @preview_bonus_points) && @preview_bonus_points > 0
                          }
                          class="foyer-tag forest"
                        >
                          +{@preview_bonus_points} pts
                        </span>
                      </div>
                    </article>
                  </aside>
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
