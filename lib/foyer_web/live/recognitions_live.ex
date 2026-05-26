defmodule FoyerWeb.RecognitionsLive do
  @moduledoc """
  Recognitions surface — `/recognitions/new` (give form), `/recognitions/:id`
  (show), and `/recognitions/:id/edit` (author-only edit, stubbed). The House
  and Today feeds are the entry points for recognition cards.
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
     |> assign(:preview_recipient_id, "")
     |> assign(:preview_recipient_name, "")
     |> assign(:preview_body, "")
     |> assign(:preview_values, [])
     |> assign(:preview_bonus_points, nil)
     |> assign(:preview_public, true)
     |> assign(:page_title, "Recognitions")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case socket.assigns.live_action do
      :new -> apply_new(socket)
      :show -> apply_show(socket, params)
      :edit -> apply_edit(socket, params)
    end
  end

  defp apply_new(socket) do
    scope = socket.assigns.current_scope

    {:noreply,
     socket
     |> assign(:recognition, nil)
     |> assign(:people, recipient_options(scope))
     |> assign(:form, to_form(FoyerWeb.LiveDeps.recognitions().compose_changeset(%{})))
     |> assign(:preview_recipient_id, "")
     |> assign(:preview_recipient_name, "")
     |> assign(:preview_body, "")
     |> assign(:preview_values, [])
     |> assign(:preview_bonus_points, nil)
     |> assign(:preview_public, true)
     |> assign(:page_title, "Give recognition")}
  end

  defp apply_show(socket, %{"id" => id}) do
    scope = socket.assigns.current_scope

    try do
      r = FoyerWeb.LiveDeps.recognitions().get_recognition!(id, scope.user)

      {:noreply,
       socket
       |> assign(:recognition, r)
       |> assign(:within_grace?, FoyerWeb.LiveDeps.recognitions().within_grace_window?(r))
       |> assign(:page_title, "Recognition for " <> ((r.recipient && r.recipient.name) || ""))}
    rescue
      Ecto.NoResultsError ->
        {:noreply,
         socket
         |> put_flash(:error, "That recognition is not available to you.")
         |> push_navigate(to: ~p"/house")}
    end
  end

  defp apply_edit(socket, %{"id" => id}) do
    scope = socket.assigns.current_scope

    try do
      r = FoyerWeb.LiveDeps.recognitions().get_recognition!(id, scope.user)

      {:noreply,
       socket
       |> assign(:recognition, r)
       |> assign(:people, recipient_options(scope))
       |> assign(:form, to_form(FoyerWeb.LiveDeps.recognitions().change_recognition(r, %{})))
       |> assign(:page_title, "Edit recognition")}
    rescue
      Ecto.NoResultsError ->
        {:noreply,
         socket
         |> put_flash(:error, "That recognition is not available to you.")
         |> push_navigate(to: ~p"/house")}
    end
  end

  @impl true
  def handle_event("give_submit", %{"recognition" => attrs}, socket) do
    scope = socket.assigns.current_scope

    case FoyerWeb.LiveDeps.recognitions().give(scope.user, attrs) do
      {:ok, recognition} ->
        {:noreply,
         socket
         |> put_flash(:info, "Recognition sent.")
         |> push_navigate(to: ~p"/recognitions/#{recognition.id}")}

      {:error, :self_recognition} ->
        {:noreply, put_flash(socket, :error, "Choose someone else to recognize.")}

      {:error, :invalid_point_tier} ->
        {:noreply, put_flash(socket, :error, "Choose one of the available point tiers.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> apply_preview_attrs(attrs)
         |> assign(:form, to_form(%{changeset | action: :insert}))
         |> put_flash(:error, "Please fix the highlighted fields.")}

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
         |> push_navigate(to: ~p"/house")}

      {:error, :outside_grace_window} ->
        {:noreply, put_flash(socket, :error, "That recognition can no longer be removed.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Only the sender can remove this recognition.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Couldn't remove recognition.")}
    end
  end

  def handle_event("preview_change", %{"recognition" => attrs}, socket) do
    {:noreply,
     socket
     |> apply_preview_attrs(attrs)
     |> assign(:form, to_form(FoyerWeb.LiveDeps.recognitions().compose_changeset(attrs)))}
  end

  def handle_event("set_bonus", %{"bonus" => "clear"}, socket) do
    {:noreply, assign(socket, :preview_bonus_points, nil)}
  end

  def handle_event("set_bonus", %{"bonus" => bonus}, socket) do
    {:noreply, assign(socket, :preview_bonus_points, String.to_integer(bonus))}
  end

  defp apply_preview_attrs(socket, attrs) do
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
        v -> parse_integer(v)
      end

    socket
    |> assign(:preview_recipient_name, recipient_name)
    |> assign(:preview_recipient_id, recipient_id)
    |> assign(:preview_body, Map.get(attrs, "body", ""))
    |> assign(:preview_values, clean_values(Map.get(attrs, "values", [])))
    |> assign(:preview_bonus_points, bonus_points)
    |> assign(:preview_public, Map.get(attrs, "public", "true") == "true")
  end

  @impl true
  def render(assigns) do
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
          <div class="foyer-scroll" id="recognitions">
            <%= cond do %>
              <% @live_action == :show and @recognition -> %>
                <.link
                  navigate={~p"/house"}
                  class="foyer-btn ghost sm self-start"
                  id="back-to-recognitions"
                >
                  <.icon name="hero-arrow-left" class="size-4" /> Back
                </.link>

                <div class="announcement-detail">
                  <article id="recognition-detail" class="announcement-detail__article">
                    <div class="flex items-center gap-2">
                      <span class="foyer-tag outline">Recognition</span>
                      <span :if={!@recognition.public} class="foyer-tag outline">Private</span>
                      <span class="foyer-mono ml-auto">
                        For {@recognition.recipient && @recognition.recipient.name}
                      </span>
                    </div>

                    <h1 class="foyer-serif text-3xl leading-tight">{@recognition.body}</h1>

                    <div class="flex items-center gap-2">
                      <FoyerComponents.avatar
                        :if={@recognition.sender}
                        initials={@recognition.sender.initials}
                        size={:sm}
                      />
                      <div>
                        <div>{@recognition.sender && @recognition.sender.name}</div>
                        <div class="foyer-mono">
                          Sent to {@recognition.recipient && @recognition.recipient.name}
                        </div>
                      </div>
                    </div>

                    <div class="flex flex-wrap gap-2">
                      <span :for={value <- @recognition.values} class="foyer-tag outline">
                        {String.capitalize(value)}
                      </span>
                      <span :if={@recognition.bonus_points > 0} class="foyer-tag claret">
                        +{@recognition.bonus_points} pts
                      </span>
                    </div>

                    <div
                      :if={managed_by?(@recognition, @current_scope)}
                      class="flex flex-wrap gap-2"
                    >
                      <%= if @within_grace? do %>
                        <.link
                          navigate={~p"/recognitions/#{@recognition.id}/edit"}
                          class="foyer-btn sm"
                          id="recognition-edit-link"
                        >
                          <.icon name="hero-pencil-square" class="size-4" /> Edit
                        </.link>
                      <% else %>
                        <span
                          class="inline-flex"
                          title="Editing and removal are only available for 15 minutes after sending."
                        >
                          <button
                            class="foyer-btn sm"
                            id="recognition-edit-link"
                            type="button"
                            disabled
                          >
                            <.icon name="hero-pencil-square" class="size-4" /> Edit
                          </button>
                        </span>
                      <% end %>

                      <%= if @within_grace? do %>
                        <button
                          class="foyer-btn sm"
                          phx-click="remove"
                          id="recognition-remove-btn"
                          type="button"
                        >
                          <.icon name="hero-trash" class="size-4" /> Remove
                        </button>
                      <% else %>
                        <span
                          class="inline-flex"
                          title="Editing and removal are only available for 15 minutes after sending."
                        >
                          <button
                            class="foyer-btn sm"
                            id="recognition-remove-btn"
                            type="button"
                            disabled
                          >
                            <.icon name="hero-trash" class="size-4" /> Remove
                          </button>
                        </span>
                      <% end %>
                    </div>
                  </article>
                </div>
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
                          <option
                            :for={p <- @people}
                            value={p.id}
                            selected={to_string(p.id) == @preview_recipient_id}
                          >
                            {p.name}
                          </option>
                        </select>
                        <.field_errors form={@form} field={:recipient_id} />
                      </div>

                      <div>
                        <FoyerComponents.section_label label="House values shown" class="block mb-2" />
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
                              id={"value-#{v}"}
                              class="sr-only"
                            />
                            {String.capitalize(v)}
                          </label>
                        </div>
                        <p class="text-xs text-stone-500 mt-1 italic">Pick one or more.</p>
                        <.field_errors form={@form} field={:values} />
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
                        <.field_errors form={@form} field={:body} />
                      </div>

                      <fieldset class="space-y-2">
                        <legend class="foyer-mono">Visibility</legend>
                        <label class="flex items-start gap-2 text-sm">
                          <input
                            type="radio"
                            name="recognition[public]"
                            value="true"
                            checked={@preview_public}
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
                            checked={!@preview_public}
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
                        id="bonus-points-fieldset"
                        class="card-parchment p-4 space-y-3"
                      >
                        <legend class="foyer-mono">Bonus points</legend>
                        <p class="text-xs text-stone-500">
                          Foyer points roll up to staff rewards — time off, meals, charitable donations.
                        </p>
                        <div class="flex gap-2 flex-wrap" id="bonus-tiers">
                          <label
                            :for={tier <- [0, 10, 25, 50, 100]}
                            class={[
                              "px-3 py-1 rounded-full text-sm font-medium border",
                              @preview_bonus_points == tier &&
                                "bg-[var(--foyer-forest)] text-[var(--foyer-cream)] border-[var(--foyer-forest)]",
                              @preview_bonus_points != tier &&
                                "bg-transparent text-stone-700 border-stone-300"
                            ]}
                          >
                            <input
                              type="radio"
                              name="recognition[bonus_points]"
                              value={tier}
                              checked={(@preview_bonus_points || 0) == tier}
                              id={"bonus-#{tier}"}
                              class="sr-only"
                            />
                            {if tier == 0, do: "0", else: "+#{tier}"}
                          </label>
                        </div>
                        <.field_errors form={@form} field={:bonus_points} />
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
                        <.link navigate={~p"/house"} class="foyer-btn ghost sm">
                          Cancel
                        </.link>
                      </div>
                    </form>
                  </div>

                  <aside id="recognition-preview" class="lg:sticky lg:top-6 self-start space-y-3">
                    <FoyerComponents.section_label label="Preview · The House feed" />
                    <div class="max-w-[360px]">
                      <FoyerComponents.recognition_card
                        recognition={preview_recognition(assigns)}
                        show_view_action={false}
                      />
                    </div>
                  </aside>
                </div>
            <% end %>

            <FoyerComponents.bottom_nav
              active={:house}
              current_scope={@current_scope}
              chat_unread_count={@chat_unread_count}
            />
          </div>
        </div>
      </main>
    </Layouts.app>
    """
  end

  defp managed_by?(%Recognition{sender_id: sender_id}, %Scope{user: %{id: id}}),
    do: sender_id == id

  defp managed_by?(_, _), do: false

  defp preview_recognition(assigns) do
    recipient =
      case Enum.find(assigns.people, &(to_string(&1.id) == assigns.preview_recipient_id)) do
        nil ->
          %Foyer.Accounts.User{name: "Add recipient...", initials: "AR"}

        person ->
          person
      end

    %Recognition{
      id: 0,
      sender_id: assigns.current_scope.user.id,
      sender: assigns.current_scope.user,
      recipient_id: recipient.id,
      recipient: recipient,
      body: if(assigns.preview_body == "", do: "Tell the story...", else: assigns.preview_body),
      values: assigns.preview_values,
      bonus_points: assigns.preview_bonus_points || 0,
      public: assigns.preview_public,
      inserted_at: DateTime.utc_now(:second)
    }
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :field, :atom, required: true

  defp field_errors(assigns) do
    ~H"""
    <div :if={@form[@field].errors != []} class="mt-1 text-sm text-[var(--foyer-claret)]">
      <p :for={error <- @form[@field].errors}>
        {translate_error(error)}
      </p>
    </div>
    """
  end

  defp recipient_options(%Scope{user: %{id: user_id}}) do
    []
    |> FoyerWeb.LiveDeps.accounts().list_people()
    |> Enum.reject(&(&1.id == user_id))
  end

  defp parse_integer(value) do
    case Integer.parse(to_string(value)) do
      {integer, ""} -> integer
      _ -> nil
    end
  end

  defp clean_values(values) when is_list(values), do: Enum.reject(values, &(&1 in [nil, ""]))
  defp clean_values(_), do: []
end
