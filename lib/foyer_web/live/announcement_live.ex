defmodule FoyerWeb.AnnouncementLive do
  @moduledoc """
  Announcement surface — `/announcements/new`, `/announcements/:id`, and
  `/announcements/:id/edit`. Membership-authorized via
  `Foyer.House.get_announcement!/2`; an unauthorized user (e.g. Maya trying to
  open a Leadership-only announcement) is redirected back to `/house` with a
  flash. The "I've read & understood" CTA writes an `AnnouncementAck` row.
  """
  use FoyerWeb, :live_view

  alias Foyer.House.Announcement
  alias FoyerWeb.FoyerComponents
  alias FoyerWeb.Scope

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:announcement, nil)
     |> assign(:form, nil)
     |> assign(:channel_options, [])
     |> assign(:acked?, false)
     |> assign(:title, "")
     |> assign(:body, "")
     |> assign(:channel_id, nil)
     |> assign(:pinned, false)
     |> assign(:require_ack, false)
     |> assign(:grace_state, :idle)
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

    if not Scope.manager?(scope) do
      {:noreply, socket |> assign(:page_title, "New announcement")}
    else
      channels = FoyerWeb.LiveDeps.channels().list_for_user(scope.user)
      channel_options = Enum.map(channels, &{&1.name, &1.id})
      default_channel_id = channels |> List.first() |> then(&(&1 && &1.id))

      {:noreply,
       socket
       |> assign(:channel_options, channel_options)
       |> assign(:channel_id, default_channel_id)
       |> assign(:title, "")
       |> assign(:body, "")
       |> assign(:pinned, false)
       |> assign(:require_ack, false)
       |> assign(:grace_state, :idle)
       |> assign(:page_title, "New announcement")}
    end
  end

  defp apply_show(socket, %{"id" => id}) do
    scope = socket.assigns.current_scope

    try do
      a = FoyerWeb.LiveDeps.house().get_announcement!(id, scope.user)
      FoyerWeb.LiveDeps.house().mark_read(a, scope.user)
      grace_state = grace_state(a)

      {:noreply,
       socket
       |> assign(:announcement, a)
       |> assign(:acked?, acked_by?(a, scope.user.id))
       |> assign(:grace_state, grace_state)
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
      grace_state = grace_state(a)

      {:noreply,
       socket
       |> assign(:announcement, a)
       |> assign(:channel_options, Enum.map(channels, &{&1.name, &1.id}))
       |> assign(:title, a.title || "")
       |> assign(:body, a.body || "")
       |> assign(:channel_id, a.channel_id)
       |> assign(:pinned, not is_nil(a.pinned_at))
       |> assign(:require_ack, a.requires_ack || false)
       |> assign(:grace_state, grace_state)
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
  def handle_event("compose_change", params, socket) do
    channel_id =
      case params["audience"] do
        nil ->
          socket.assigns.channel_id

        id_str ->
          case Integer.parse(id_str) do
            {n, ""} -> n
            _ -> socket.assigns.channel_id
          end
      end

    {:noreply,
     socket
     |> assign(:title, params["title"] || socket.assigns.title)
     |> assign(:body, params["body"] || socket.assigns.body)
     |> assign(:channel_id, channel_id)
     |> assign(:pinned, params["pinned"] == "true")
     |> assign(:require_ack, params["require_ack"] == "true")}
  end

  def handle_event("compose_submit", _params, socket) do
    scope = socket.assigns.current_scope

    attrs = %{
      "title" => socket.assigns.title,
      "body" => socket.assigns.body,
      "channel_id" => socket.assigns.channel_id,
      "pinned_at" => if(socket.assigns.pinned, do: DateTime.utc_now(), else: nil),
      "requires_ack" => socket.assigns.require_ack
    }

    case FoyerWeb.LiveDeps.house().create_announcement(scope.user, attrs) do
      {:ok, announcement} ->
        {:noreply,
         socket
         |> put_flash(:info, "Announcement published.")
         |> push_navigate(to: ~p"/announcements/#{announcement.id}")}

      {:error, :not_implemented} ->
        {:noreply,
         socket
         |> put_flash(:info, "Compose not implemented in scaffold.")
         |> push_navigate(to: ~p"/house")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Couldn't publish announcement.")}
    end
  end

  def handle_event("edit_submit", _params, socket) do
    scope = socket.assigns.current_scope
    %Announcement{id: id} = announcement = socket.assigns.announcement

    attrs = %{
      "title" => socket.assigns.title,
      "body" => socket.assigns.body,
      "channel_id" => socket.assigns.channel_id,
      "pinned_at" =>
        if(socket.assigns.pinned, do: announcement.pinned_at || DateTime.utc_now(), else: nil),
      "requires_ack" => socket.assigns.require_ack
    }

    case FoyerWeb.LiveDeps.house().update_announcement(announcement, scope.user, attrs) do
      {:ok, _updated} ->
        {:noreply,
         socket
         |> put_flash(:info, "Announcement updated.")
         |> push_navigate(to: ~p"/announcements/#{id}")}

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

  def handle_event("unpin", _params, socket) do
    # TODO: unpin_announcement not exposed by foyer_app's HousePort — stubbed
    {:noreply, put_flash(socket, :info, "Unpin not implemented in scaffold.")}
  end

  def handle_event("remove", _params, socket) do
    # TODO: remove_announcement not exposed by foyer_app's HousePort — stubbed
    {:noreply,
     socket
     |> put_flash(:info, "Remove not implemented in scaffold.")
     |> push_navigate(to: ~p"/house")}
  end

  defp acked_by?(%{acks: acks}, user_id) when is_list(acks) do
    Enum.any?(acks, fn ack -> ack.user_id == user_id end)
  end

  defp acked_by?(_, _), do: false

  defp grace_state(%Announcement{published_at: nil}), do: :idle

  defp grace_state(%Announcement{published_at: published_at}) do
    elapsed_ms = DateTime.diff(DateTime.utc_now(), published_at, :millisecond)
    remaining_ms = max(0, 60_000 - elapsed_ms)
    if remaining_ms > 0, do: :open, else: :expired
  end

  defp audience_label(channel_options, channel_id) do
    case Enum.find(channel_options, fn {_, id} -> id == channel_id end) do
      {label, _} -> label
      _ -> ""
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main class="foyer-shell">
        <FoyerComponents.desktop_rail active={:house} current_scope={@current_scope} />
        <div class="foyer-content">
          <div class="foyer-scroll" id="announcement">
            <FoyerComponents.desktop_topbar current_scope={@current_scope} page_title={@page_title} />

            <%= cond do %>
              <% @live_action == :new -> %>
                <%= if not FoyerComponents.manager?(@current_scope) do %>
                  <div
                    id="compose-gated"
                    class="flex flex-col items-center gap-4 mt-12 max-w-md mx-auto rounded-lg p-8 text-center"
                    style="background: var(--foyer-cream-deep); border: 1px solid var(--foyer-rule);"
                  >
                    <FoyerComponents.status_pill kind={:manager_only} />
                    <h1 class="foyer-serif text-3xl">Manager view only.</h1>
                    <p class="text-sm" style="color: var(--foyer-stone-600, #57534e);">
                      Composing announcements and viewing read receipts is reserved for department heads. You can still acknowledge them and react in The House.
                    </p>
                    <.link navigate={~p"/house"} class="foyer-btn sm" id="gated-back">
                      Back to The House
                    </.link>
                  </div>
                <% else %>
                  <div class="flex flex-col gap-2">
                    <FoyerComponents.editorial_heading>
                      New announcement
                    </FoyerComponents.editorial_heading>
                    <p class="text-sm" style="color: var(--foyer-stone-600, #57534e);">
                      Composing an announcement.
                      <span class="italic">Reach the right people. Pin if it must be seen.</span>
                    </p>
                  </div>

                  <div class="foyer-content-cols" id="compose-form-root">
                    <div class="flex flex-col gap-5">
                      <form
                        id="announcement-new-form"
                        phx-change="compose_change"
                        phx-submit="compose_submit"
                        class="flex flex-col gap-5"
                      >
                        <div>
                          <label class="foyer-mono block mb-1">Title</label>
                          <input
                            type="text"
                            name="title"
                            value={@title}
                            placeholder="Suite 412 — Allergy protocol in effect"
                            class="w-full px-4 py-2.5 rounded-lg border text-base"
                            style="border-color: var(--foyer-rule); background: var(--foyer-cream-deep);"
                          />
                        </div>

                        <div>
                          <label class="foyer-mono block mb-1">Body</label>
                          <textarea
                            name="body"
                            rows="6"
                            placeholder="What needs to land?"
                            class="w-full px-4 py-3 rounded-lg border text-sm leading-relaxed"
                            style="border-color: var(--foyer-rule); background: var(--foyer-cream-deep);"
                          >{@body}</textarea>
                          <div class="foyer-mono text-right mt-1">{String.length(@body)} / 800</div>
                        </div>

                        <div>
                          <label class="foyer-mono block mb-1">Publish to</label>
                          <select
                            name="audience"
                            class="w-full px-3 py-2 rounded-lg border text-sm"
                            style="border-color: var(--foyer-rule); background: var(--foyer-cream-deep);"
                          >
                            <option
                              :for={{label, val} <- @channel_options}
                              value={val}
                              selected={@channel_id == val}
                            >
                              {label}
                            </option>
                          </select>
                        </div>

                        <fieldset class="flex flex-col gap-3">
                          <legend class="foyer-mono">Options</legend>

                          <label
                            class="flex items-start gap-3 p-3 rounded-lg cursor-pointer"
                            style="background: var(--foyer-cream-deep); border: 1px solid var(--foyer-rule);"
                          >
                            <input
                              type="checkbox"
                              name="pinned"
                              value="true"
                              checked={@pinned}
                              class="mt-1"
                            />
                            <div>
                              <div class="font-medium text-sm">Pin to top of feed</div>
                              <div class="foyer-mono">Stays pinned until you unpin manually.</div>
                            </div>
                          </label>

                          <label
                            class="flex items-start gap-3 p-3 rounded-lg cursor-pointer"
                            style="background: var(--foyer-cream-deep); border: 1px solid var(--foyer-rule);"
                          >
                            <input
                              type="checkbox"
                              name="require_ack"
                              value="true"
                              checked={@require_ack}
                              class="mt-1"
                            />
                            <div>
                              <div class="font-medium text-sm">Require acknowledgement</div>
                              <div class="foyer-mono">Each reader confirms with a tap.</div>
                            </div>
                          </label>
                        </fieldset>

                        <div class="flex gap-2 pt-4" style="border-top: 1px solid var(--foyer-rule);">
                          <button type="submit" class="foyer-btn forest" id="publish-button">
                            Publish now
                          </button>
                        </div>
                      </form>
                    </div>

                    <aside id="compose-preview" class="hidden lg:block">
                      <FoyerComponents.section_label label="Live preview" />
                      <article
                        class="rounded-lg p-5 flex flex-col gap-3 max-w-sm"
                        style="background: var(--foyer-cream-deep); border: 1px solid var(--foyer-rule);"
                      >
                        <div class="flex items-center gap-2 flex-wrap">
                          <FoyerComponents.status_pill :if={@pinned} kind={:pinned} />
                          <FoyerComponents.status_pill :if={@require_ack} kind={:ack_required} />
                          <span class="foyer-mono">
                            {audience_label(@channel_options, @channel_id)}
                          </span>
                        </div>
                        <h2 class="foyer-serif text-xl">
                          {if @title == "", do: "Untitled", else: @title}
                        </h2>
                        <p class="text-sm leading-relaxed">
                          {if @body == "", do: "Body preview…", else: @body}
                        </p>
                        <div class="foyer-mono pt-1">{@current_scope.user.name} · just now</div>
                      </article>
                    </aside>
                  </div>
                <% end %>
              <% @live_action == :edit and @announcement -> %>
                <.link
                  navigate={~p"/announcements/#{@announcement.id}"}
                  class="foyer-btn ghost sm self-start"
                  id="back-to-detail"
                >
                  <.icon name="hero-arrow-left" class="size-4" /> Back
                </.link>

                <div class="flex flex-col gap-2">
                  <FoyerComponents.editorial_heading>
                    Edit announcement
                  </FoyerComponents.editorial_heading>
                  <p
                    :if={@grace_state == :expired}
                    class="text-sm font-medium"
                    style="color: #b45309;"
                  >
                    Edit window closed.
                  </p>
                </div>

                <div class="foyer-content-cols" id="edit-form-root">
                  <div class="flex flex-col gap-5">
                    <form
                      id="announcement-edit-form"
                      phx-change="compose_change"
                      phx-submit="edit_submit"
                      class="flex flex-col gap-5"
                    >
                      <div>
                        <label class="foyer-mono block mb-1">Title</label>
                        <input
                          type="text"
                          name="title"
                          value={@title}
                          class="w-full px-4 py-2.5 rounded-lg border text-base"
                          style="border-color: var(--foyer-rule); background: var(--foyer-cream-deep);"
                          disabled={@grace_state == :expired}
                        />
                      </div>

                      <div>
                        <label class="foyer-mono block mb-1">Body</label>
                        <textarea
                          name="body"
                          rows="6"
                          class="w-full px-4 py-3 rounded-lg border text-sm leading-relaxed"
                          style="border-color: var(--foyer-rule); background: var(--foyer-cream-deep);"
                          disabled={@grace_state == :expired}
                        >{@body}</textarea>
                        <div class="foyer-mono text-right mt-1">{String.length(@body)} / 800</div>
                      </div>

                      <div>
                        <label class="foyer-mono block mb-1">Publish to</label>
                        <select
                          name="audience"
                          class="w-full px-3 py-2 rounded-lg border text-sm"
                          style="border-color: var(--foyer-rule); background: var(--foyer-cream-deep);"
                          disabled={@grace_state == :expired}
                        >
                          <option
                            :for={{label, val} <- @channel_options}
                            value={val}
                            selected={@channel_id == val}
                          >
                            {label}
                          </option>
                        </select>
                      </div>

                      <fieldset class="flex flex-col gap-3">
                        <legend class="foyer-mono">Options</legend>

                        <label
                          class="flex items-start gap-3 p-3 rounded-lg cursor-pointer"
                          style="background: var(--foyer-cream-deep); border: 1px solid var(--foyer-rule);"
                        >
                          <input
                            type="checkbox"
                            name="pinned"
                            value="true"
                            checked={@pinned}
                            class="mt-1"
                            disabled={@grace_state == :expired}
                          />
                          <div>
                            <div class="font-medium text-sm">Pin to top of feed</div>
                            <div class="foyer-mono">Stays pinned until you unpin manually.</div>
                          </div>
                        </label>

                        <label
                          class="flex items-start gap-3 p-3 rounded-lg cursor-pointer"
                          style="background: var(--foyer-cream-deep); border: 1px solid var(--foyer-rule);"
                        >
                          <input
                            type="checkbox"
                            name="require_ack"
                            value="true"
                            checked={@require_ack}
                            class="mt-1"
                            disabled={@grace_state == :expired}
                          />
                          <div>
                            <div class="font-medium text-sm">Require acknowledgement</div>
                            <div class="foyer-mono">Each reader confirms with a tap.</div>
                          </div>
                        </label>
                      </fieldset>

                      <div class="flex gap-2 pt-4" style="border-top: 1px solid var(--foyer-rule);">
                        <button
                          type="submit"
                          class="foyer-btn forest"
                          id="publish-button"
                          disabled={@grace_state == :expired}
                        >
                          Publish update
                        </button>
                        <button
                          :if={@grace_state == :open}
                          type="button"
                          phx-click="remove"
                          id="remove-button"
                          class="foyer-btn ghost"
                        >
                          Remove
                        </button>
                      </div>
                    </form>
                  </div>

                  <aside id="edit-preview" class="hidden lg:block">
                    <FoyerComponents.section_label label="Live preview" />
                    <article
                      class="rounded-lg p-5 flex flex-col gap-3 max-w-sm"
                      style="background: var(--foyer-cream-deep); border: 1px solid var(--foyer-rule);"
                    >
                      <div class="flex items-center gap-2 flex-wrap">
                        <FoyerComponents.status_pill :if={@pinned} kind={:pinned} />
                        <FoyerComponents.status_pill :if={@require_ack} kind={:ack_required} />
                        <span class="foyer-mono">
                          {audience_label(@channel_options, @channel_id)}
                        </span>
                      </div>
                      <h2 class="foyer-serif text-xl">
                        {if @title == "", do: "Untitled", else: @title}
                      </h2>
                      <p class="text-sm leading-relaxed">
                        {if @body == "", do: "Body preview…", else: @body}
                      </p>
                      <div class="foyer-mono pt-1">{@current_scope.user.name} · just now</div>
                    </article>
                  </aside>
                </div>
              <% @live_action == :show and @announcement -> %>
                <div class="flex flex-col gap-6" id={"announcement-" <> to_string(@announcement.id)}>
                  <div class="flex items-start justify-between gap-3">
                    <.link navigate={~p"/house"} class="foyer-btn ghost sm" id="back-to-house">
                      <.icon name="hero-arrow-left" class="size-4" /> Back to The House
                    </.link>
                    <button
                      :if={Scope.manager?(@current_scope) and not is_nil(@announcement.pinned_at)}
                      type="button"
                      phx-click="unpin"
                      id="unpin-button"
                      class="foyer-btn ghost sm shrink-0"
                    >
                      Unpin
                    </button>
                  </div>

                  <div class="flex items-center gap-2 flex-wrap">
                    <FoyerComponents.status_pill
                      :if={@announcement.requires_ack}
                      kind={:ack_required}
                      label="Requires acknowledgement"
                    />
                    <FoyerComponents.status_pill :if={@announcement.pinned_at} kind={:pinned} />
                    <span class="foyer-mono">
                      {@announcement.channel && @announcement.channel.name}
                    </span>
                  </div>

                  <FoyerComponents.editorial_heading>
                    {@announcement.title}
                  </FoyerComponents.editorial_heading>

                  <div class="flex items-center gap-3 text-sm">
                    <FoyerComponents.avatar
                      :if={@announcement.author}
                      initials={@announcement.author.initials}
                      size={:sm}
                    />
                    <span>
                      {@announcement.author && @announcement.author.name}
                      {if @announcement.author && @announcement.author.title,
                        do: " · #{@announcement.author.title}",
                        else: ""}
                    </span>
                    <span aria-hidden="true">·</span>
                    <time>{FoyerComponents.format_time(@announcement.published_at)}</time>
                  </div>

                  <article
                    class="rounded-lg p-6 text-base leading-relaxed"
                    style="background: var(--foyer-cream-deep); border: 1px solid var(--foyer-rule);"
                  >
                    {@announcement.body}
                  </article>

                  <section
                    :if={author?(@announcement, @current_scope) and @grace_state == :open}
                    id="author-grace-controls"
                    class="rounded-lg p-4 flex flex-col gap-3"
                    style="background: var(--foyer-cream-deep); border: 1px solid var(--foyer-rule);"
                  >
                    <p class="text-xs italic" style="color: var(--foyer-stone-500, #78716c);">
                      60s to edit or remove.
                    </p>
                    <div class="flex gap-2 flex-wrap">
                      <.link
                        navigate={~p"/announcements/#{@announcement.id}/edit"}
                        class="foyer-btn sm"
                        id="edit-button"
                      >
                        Edit
                      </.link>
                      <button
                        type="button"
                        phx-click="remove"
                        id="remove-button"
                        class="foyer-btn ghost sm"
                      >
                        Remove
                      </button>
                    </div>
                  </section>

                  <div
                    :if={@grace_state == :expired and author?(@announcement, @current_scope)}
                    class="foyer-mono"
                    id="grace-expired-note"
                  >
                    Edit window closed.
                    <.link navigate={~p"/announcements/new"} class="foyer-btn ghost sm">
                      + Another
                    </.link>
                  </div>

                  <div
                    :if={@announcement.requires_ack}
                    id="ack-section"
                    class="flex flex-col gap-3"
                  >
                    <%= if @acked? do %>
                      <div
                        id="ack-confirmation"
                        class="rounded-lg p-4 text-sm flex items-center gap-2"
                        style="background: var(--foyer-cream-deep); border: 1px solid var(--foyer-rule);"
                      >
                        <span style="color: #059669;">
                          <.icon name="hero-check-circle" class="size-5" />
                        </span>
                        Acknowledged. Thank you.
                      </div>
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
                  </div>

                  <section
                    :if={Scope.manager?(@current_scope)}
                    id="manager-receipts"
                    class="flex flex-col gap-5 pt-4"
                    style="border-top: 1px solid var(--foyer-rule);"
                  >
                    <div>
                      <FoyerComponents.section_label label="Read receipts" />
                      <p class="text-sm" style="color: var(--foyer-stone-600, #57534e);">
                        {@announcement.channel && @announcement.channel.name} · {pin_state_text(
                          @announcement
                        )}
                      </p>
                    </div>

                    <section id="receipt-metrics" class="grid grid-cols-2 md:grid-cols-3 gap-3">
                      <%!-- TODO: audience_count not exposed by foyer_app's HousePort — using read + ack count as approximation --%>
                      <%= if @announcement.requires_ack do %>
                        <div
                          class="rounded-lg p-4"
                          style="background: var(--foyer-cream-deep); border: 1px solid var(--foyer-rule);"
                        >
                          <FoyerComponents.section_label label="Acknowledged" />
                          <div class="foyer-serif text-3xl mt-1" data-metric-acked>
                            {length(@announcement.acks)}/{length(@announcement.reads) +
                              length(@announcement.acks)}
                          </div>
                          <div class="foyer-mono">target 100%</div>
                        </div>
                        <div
                          class="rounded-lg p-4"
                          style="background: var(--foyer-cream-deep); border: 1px solid var(--foyer-rule);"
                        >
                          <FoyerComponents.section_label label="Unread" />
                          <div class="foyer-serif text-3xl mt-1" data-metric-unread>
                            {unread_count(@announcement)}
                          </div>
                        </div>
                        <div
                          class="rounded-lg p-4"
                          style="background: var(--foyer-cream-deep); border: 1px solid var(--foyer-rule);"
                        >
                          <FoyerComponents.section_label label="Read · no ack" />
                          <div class="foyer-serif text-3xl mt-1" data-metric-read>
                            {length(@announcement.reads)}
                          </div>
                          <div class="foyer-mono">Opened but not confirmed.</div>
                        </div>
                      <% else %>
                        <div
                          class="rounded-lg p-4"
                          style="background: var(--foyer-cream-deep); border: 1px solid var(--foyer-rule);"
                        >
                          <FoyerComponents.section_label label="Read" />
                          <div class="foyer-serif text-3xl mt-1" data-metric-read>
                            {length(@announcement.reads)}
                          </div>
                        </div>
                        <div
                          class="rounded-lg p-4"
                          style="background: var(--foyer-cream-deep); border: 1px solid var(--foyer-rule);"
                        >
                          <FoyerComponents.section_label label="Unread" />
                          <div class="foyer-serif text-3xl mt-1" data-metric-unread>
                            {unread_count(@announcement)}
                          </div>
                        </div>
                      <% end %>
                    </section>

                    <section id="receipt-people" class="flex flex-col gap-2">
                      <FoyerComponents.section_label label="Per-person status" />
                      <div
                        class="flex gap-3 text-xs mb-2 flex-wrap"
                        id="receipt-legend"
                        style="color: var(--foyer-stone-500, #78716c);"
                      >
                        <%= if @announcement.requires_ack do %>
                          <span class="flex items-center gap-1">
                            <span class="size-2 rounded-full bg-emerald-600"></span> Acknowledged
                          </span>
                          <span class="flex items-center gap-1">
                            <span class="size-2 rounded-full bg-amber-500"></span> Read · no ack
                          </span>
                          <span class="flex items-center gap-1">
                            <span class="size-2 rounded-full bg-stone-400"></span> Unread
                          </span>
                          <span class="flex items-center gap-1">
                            <span class="size-2 rounded-full bg-stone-300"></span> Off shift
                          </span>
                        <% else %>
                          <span class="flex items-center gap-1">
                            <span class="size-2 rounded-full bg-emerald-600"></span> Read
                          </span>
                          <span class="flex items-center gap-1">
                            <span class="size-2 rounded-full bg-amber-500"></span> Unread
                          </span>
                          <span class="flex items-center gap-1">
                            <span class="size-2 rounded-full bg-stone-400"></span> Off shift
                          </span>
                        <% end %>
                      </div>
                      <ul
                        class="rounded-lg divide-y"
                        style="background: var(--foyer-cream-deep); border: 1px solid var(--foyer-rule); divide-color: var(--foyer-rule);"
                      >
                        <li
                          :for={ack <- @announcement.acks}
                          id={"ack-badge-#{ack.user_id}"}
                          class="flex items-center justify-between p-3 text-sm"
                          data-receipt-row={ack.user_id}
                          data-status="acked"
                        >
                          <div class="flex items-center gap-3">
                            <FoyerComponents.avatar
                              initials={ack_initials(ack)}
                              size={:sm}
                            />
                            <div>
                              <div class="font-medium">{ack_name(ack)}</div>
                            </div>
                          </div>
                          <span class="flex items-center gap-2 text-xs">
                            <span class="size-2 rounded-full bg-emerald-600"></span> Acknowledged
                          </span>
                        </li>
                        <li
                          :for={read <- unacked_reads(@announcement)}
                          class="flex items-center justify-between p-3 text-sm"
                          data-receipt-row={read.user_id}
                          data-status="read"
                        >
                          <div class="flex items-center gap-3">
                            <FoyerComponents.avatar
                              initials={read_initials(read)}
                              size={:sm}
                            />
                            <div>
                              <div class="font-medium">{read_name(read)}</div>
                            </div>
                          </div>
                          <span class="flex items-center gap-2 text-xs">
                            <%= if @announcement.requires_ack do %>
                              <span class="size-2 rounded-full bg-amber-500"></span> Read · no ack
                            <% else %>
                              <span class="size-2 rounded-full bg-emerald-600"></span> Read
                            <% end %>
                          </span>
                        </li>
                      </ul>
                    </section>
                  </section>
                </div>
            <% end %>

            <FoyerComponents.bottom_nav active={:house} current_scope={@current_scope} />
          </div>
        </div>
      </main>
    </Layouts.app>
    """
  end

  defp author?(%Announcement{author_id: author_id}, %FoyerWeb.Scope{user: %{id: id}}),
    do: author_id == id

  defp author?(_, _), do: false

  defp pin_state_text(%Announcement{pinned_at: nil}), do: "Not pinned"
  defp pin_state_text(%Announcement{}), do: "Pinned"

  defp ack_initials(%{user: %{initials: initials}}), do: initials
  defp ack_initials(_), do: "??"

  defp ack_name(%{user: %{name: name}}), do: name
  defp ack_name(_), do: ""

  defp read_initials(%{user: %{initials: initials}}), do: initials
  defp read_initials(_), do: "??"

  defp read_name(%{user: %{name: name}}), do: name
  defp read_name(_), do: ""

  defp unacked_reads(%Announcement{reads: reads, acks: acks})
       when is_list(reads) and is_list(acks) do
    acked_user_ids = MapSet.new(acks, & &1.user_id)
    Enum.reject(reads, fn r -> MapSet.member?(acked_user_ids, r.user_id) end)
  end

  defp unacked_reads(_), do: []

  defp unread_count(%Announcement{reads: reads, acks: acks})
       when is_list(reads) and is_list(acks) do
    # TODO: total audience count not exposed by foyer_app's HousePort
    # Unread = audience - (reads + acks) — we can't compute this without audience_count
    # Returning 0 as a placeholder
    _ = reads
    _ = acks
    0
  end

  defp unread_count(_), do: 0
end
