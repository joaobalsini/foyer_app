defmodule FoyerWeb.AnnouncementLive do
  @moduledoc """
  Announcement surface — `/announcements/new`, `/announcements/:id`, and
  `/announcements/:id/edit`. Membership-authorized via
  `Foyer.House.get_announcement!/2`; an unauthorized user (e.g. Maya trying to
  open a Leadership-only announcement) is redirected back to `/house` with a
  flash. The "I've read & understood" CTA writes an `AnnouncementAck` row.
  Create/update are stubbed pending the House feature group.
  """
  use FoyerWeb, :live_view

  alias Foyer.House.Announcement
  alias FoyerWeb.FoyerComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:announcement, nil)
     |> assign(:form, nil)
     |> assign(:channel_options, [])
     |> assign(:acked?, false)
     |> assign(:preview_title, "")
     |> assign(:preview_body, "")
     |> assign(:page_title, "Announcement")}
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
    channels = FoyerWeb.LiveDeps.channels().list_for_user(scope.user)

    {:noreply,
     socket
     |> assign(:announcement, nil)
     |> assign(:form, to_form(FoyerWeb.LiveDeps.house().compose_changeset(%{})))
     |> assign(:channel_options, Enum.map(channels, &{&1.name, &1.id}))
     |> assign(:page_title, "New announcement")}
  end

  defp apply_show(socket, %{"id" => id}) do
    scope = socket.assigns.current_scope

    try do
      a = FoyerWeb.LiveDeps.house().get_announcement!(id, scope.user)
      FoyerWeb.LiveDeps.house().mark_read(a, scope.user)

      {:noreply,
       socket
       |> assign(:announcement, a)
       |> assign(:acked?, acked_by?(a, scope.user.id))
       |> assign(:page_title, a.title)}
    rescue
      Ecto.NoResultsError ->
        {:noreply,
         socket
         |> put_flash(:error, "That announcement is not available to you.")
         |> push_navigate(to: ~p"/house")}
    end
  end

  defp apply_edit(socket, %{"id" => id}) do
    scope = socket.assigns.current_scope

    try do
      a = FoyerWeb.LiveDeps.house().get_announcement!(id, scope.user)
      channels = FoyerWeb.LiveDeps.channels().list_for_user(scope.user)

      {:noreply,
       socket
       |> assign(:announcement, a)
       |> assign(:form, to_form(FoyerWeb.LiveDeps.house().change_announcement(a, %{})))
       |> assign(:channel_options, Enum.map(channels, &{&1.name, &1.id}))
       |> assign(:preview_title, a.title || "")
       |> assign(:preview_body, a.body || "")
       |> assign(:page_title, "Edit · " <> a.title)}
    rescue
      Ecto.NoResultsError ->
        {:noreply,
         socket
         |> put_flash(:error, "That announcement is not available to you.")
         |> push_navigate(to: ~p"/house")}
    end
  end

  @impl true
  def handle_event("compose_submit", %{"announcement" => attrs}, socket) do
    scope = socket.assigns.current_scope

    case FoyerWeb.LiveDeps.house().create_announcement(scope.user, attrs) do
      {:ok, _announcement} ->
        {:noreply, push_navigate(socket, to: ~p"/house")}

      {:error, :not_implemented} ->
        {:noreply,
         socket
         |> put_flash(:info, "Compose not implemented in scaffold.")
         |> push_navigate(to: ~p"/house")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Couldn't publish announcement.")}
    end
  end

  def handle_event("edit_submit", %{"announcement" => attrs}, socket) do
    scope = socket.assigns.current_scope
    %Announcement{id: id} = announcement = socket.assigns.announcement

    case FoyerWeb.LiveDeps.house().update_announcement(announcement, scope.user, attrs) do
      {:ok, _updated} ->
        {:noreply, push_navigate(socket, to: ~p"/announcements/#{id}")}

      {:error, :not_implemented} ->
        {:noreply,
         socket
         |> put_flash(:info, "Edit not implemented in scaffold.")
         |> push_navigate(to: ~p"/announcements/#{id}")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Couldn't update announcement.")}
    end
  end

  def handle_event("acknowledge", _params, socket) do
    scope = socket.assigns.current_scope
    a = socket.assigns.announcement

    FoyerWeb.LiveDeps.house().acknowledge(a, scope.user)

    refreshed = FoyerWeb.LiveDeps.house().get_announcement!(a.id, scope.user)

    {:noreply,
     socket
     |> assign(:announcement, refreshed)
     |> assign(:acked?, true)
     |> put_flash(:info, "Acknowledged.")}
  end

  def handle_event("preview_change", %{"announcement" => attrs}, socket) do
    {:noreply,
     socket
     |> assign(:preview_title, Map.get(attrs, "title", ""))
     |> assign(:preview_body, Map.get(attrs, "body", ""))}
  end

  defp acked_by?(%{acks: acks}, user_id) when is_list(acks) do
    Enum.any?(acks, fn ack -> ack.user_id == user_id end)
  end

  defp acked_by?(_, _), do: false

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main class="foyer-shell">
        <FoyerComponents.desktop_rail active={:house} current_scope={@current_scope} />
        <div class="foyer-content">
          <div class="foyer-scroll" id="announcement">
            <.link navigate={~p"/house"} class="foyer-btn ghost sm self-start" id="back-to-house">
              <.icon name="hero-arrow-left" class="size-4" /> Back
            </.link>

            <%= cond do %>
              <% @live_action == :new -> %>
                <%= if not FoyerWeb.FoyerComponents.manager?(@current_scope) do %>
                  <div id="compose-gated" class="flex flex-col items-center gap-3 mt-8">
                    <div class="foyer-mono">Manager view only</div>
                    <p class="foyer-serif text-xl">Compose is for managers.</p>
                    <.link navigate={~p"/house"} class="foyer-btn sm">
                      Back to The House
                    </.link>
                  </div>
                <% else %>
                  <h1 class="foyer-serif text-3xl">New announcement</h1>
                  <div class="foyer-content-cols">
                    <div>
                      <.form
                        for={@form}
                        id="announcement-new-form"
                        phx-submit="compose_submit"
                        phx-change="preview_change"
                        class="flex flex-col gap-3"
                      >
                        <.input field={@form[:title]} type="text" label="Title" />
                        <.input field={@form[:body]} type="textarea" label="The detail" />
                        <.input
                          field={@form[:channel_id]}
                          type="select"
                          label="To · audience"
                          options={@channel_options}
                        />
                        <button class="foyer-btn forest" type="submit">Publish</button>
                      </.form>
                    </div>
                    <div class="hidden lg:block" id="announcement-preview-col">
                      <div class="foyer-mono mb-2">Preview</div>
                      <article
                        class="rounded-lg border p-3 flex flex-col gap-2"
                        style="border-color: var(--foyer-rule);"
                      >
                        <h3 class="foyer-serif text-xl">
                          {if @preview_title != "", do: @preview_title, else: "Untitled"}
                        </h3>
                        <p class="text-sm">
                          {if @preview_body != "", do: @preview_body, else: "Body will appear here…"}
                        </p>
                      </article>
                    </div>
                  </div>
                <% end %>
              <% @live_action == :edit and @announcement -> %>
                <h1 class="foyer-serif text-3xl">Edit announcement</h1>
                <div class="foyer-content-cols">
                  <div>
                    <.form
                      for={@form}
                      id="announcement-edit-form"
                      phx-submit="edit_submit"
                      phx-change="preview_change"
                      class="flex flex-col gap-3"
                    >
                      <.input field={@form[:title]} type="text" label="Title" />
                      <.input field={@form[:body]} type="textarea" label="The detail" />
                      <.input
                        field={@form[:channel_id]}
                        type="select"
                        label="To · audience"
                        options={@channel_options}
                      />
                      <button class="foyer-btn forest" type="submit">Save changes</button>
                    </.form>
                  </div>
                  <div class="hidden lg:block" id="announcement-edit-preview-col">
                    <div class="foyer-mono mb-2">Preview</div>
                    <article
                      class="rounded-lg border p-3 flex flex-col gap-2"
                      style="border-color: var(--foyer-rule);"
                    >
                      <h3 class="foyer-serif text-xl">
                        {if @preview_title != "", do: @preview_title, else: "Untitled"}
                      </h3>
                      <p class="text-sm">
                        {if @preview_body != "", do: @preview_body, else: "Body will appear here…"}
                      </p>
                    </article>
                  </div>
                </div>
              <% @live_action == :show and @announcement -> %>
                <div class="foyer-content-cols">
                  <article class="flex flex-col gap-3">
                    <div class="flex items-center gap-2">
                      <span :if={@announcement.pinned_at} class="foyer-tag claret">Pinned</span>
                      <span :if={@announcement.requires_ack} class="foyer-tag outline">
                        Requires acknowledgement
                      </span>
                      <span class="foyer-mono ml-auto">
                        {@announcement.channel && @announcement.channel.name}
                      </span>
                    </div>

                    <h1 class="foyer-serif text-3xl">{@announcement.title}</h1>

                    <div class="flex items-center gap-2">
                      <FoyerComponents.avatar
                        :if={@announcement.author}
                        initials={@announcement.author.initials}
                        size={:sm}
                      />
                      <div>
                        <div>{@announcement.author && @announcement.author.name}</div>
                        <div class="foyer-mono">
                          Audience · {@announcement.channel && @announcement.channel.name}
                        </div>
                      </div>
                      <%= if managed_by?(@announcement, @current_scope) do %>
                        <.link
                          navigate={~p"/announcements/#{@announcement.id}/edit"}
                          class="foyer-btn ghost sm ml-auto"
                          id="announcement-edit-link"
                        >
                          Edit
                        </.link>
                      <% end %>
                    </div>

                    <p class="foyer-serif">{@announcement.body}</p>

                    <%= if @announcement.requires_ack do %>
                      <div class="foyer-mono">
                        {length(@announcement.acks)} confirmed
                      </div>

                      <%= if @acked? do %>
                        <button class="foyer-btn" disabled id="acked-state">
                          Acknowledged
                        </button>
                      <% else %>
                        <button
                          class="foyer-btn forest"
                          phx-click="acknowledge"
                          id="acknowledge-btn"
                          type="button"
                        >
                          I've read &amp; understood
                        </button>
                      <% end %>
                    <% end %>
                  </article>

                  <div class="hidden lg:block" id="read-receipts-col">
                    <div class="foyer-mono mb-2">Read receipts</div>
                    <div class="flex flex-col gap-2">
                      <div class="foyer-mono">
                        {length(@announcement.acks)} confirmed / {length(@announcement.reads)} read
                      </div>
                      <div class="flex flex-wrap gap-2">
                        <span
                          :for={ack <- @announcement.acks}
                          class="foyer-tag moss"
                          id={"ack-badge-#{ack.user_id}"}
                        >
                          {ack_initials(ack)} ✓
                        </span>
                      </div>
                    </div>
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

  defp managed_by?(%Announcement{author_id: author_id}, %FoyerWeb.Scope{user: %{id: id}}),
    do: author_id == id

  defp managed_by?(_, _), do: false

  defp ack_initials(%{user: %{initials: initials}}), do: initials
  defp ack_initials(_), do: "??"
end
