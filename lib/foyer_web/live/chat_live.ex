defmodule FoyerWeb.ChatLive do
  @moduledoc """
  Chat surface — `/chat` (inbox), `/chat/new` (picker), and `/chat/:conversation_id`
  (room). The room view is `:show`; sends are stubbed pending the Chat feature
  group.

  PubSub subscriptions:
    * `chat:inbox:<user_id>` on every connect (drives inbox unread state)
    * `chat:room:<conversation_id>` while viewing the room
  """
  use FoyerWeb, :live_view

  alias FoyerWeb.FoyerComponents

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      scope = socket.assigns.current_scope
      Phoenix.PubSub.subscribe(Foyer.PubSub, "chat:inbox:#{scope.user.id}")
    end

    {:ok,
     socket
     |> stream_configure(:conversations, dom_id: &"conv-#{&1.id}")
     |> stream(:conversations, [])
     |> stream_configure(:messages, dom_id: &"msg-#{&1.id}")
     |> stream(:messages, [])
     |> assign(:people, [])
     |> assign(:channels, [])
     |> assign(:channel_counts, %{})
     |> assign(:new_message_tab, :people)
     |> assign(:on_shift_ids, MapSet.new())
     |> assign(:conversation, nil)
     |> assign(:compose_form, to_form(%{"body" => ""}, as: :message))
     |> assign(:page_title, "Messages")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    scope = socket.assigns.current_scope

    case socket.assigns.live_action do
      :inbox ->
        conversations = FoyerWeb.LiveDeps.chat().inbox_for(scope.user)
        channels = FoyerWeb.LiveDeps.channels().list_for_user(scope.user)

        {:noreply,
         socket
         |> stream(:conversations, conversations, reset: true)
         |> assign(:channels, channels)
         |> assign(:page_title, "Messages")}

      :new_message ->
        tab = if params["tab"] == "channels", do: :channels, else: :people

        people =
          FoyerWeb.LiveDeps.accounts().list_people([])
          |> Enum.reject(fn person -> person.id == scope.user.id end)

        channels = FoyerWeb.LiveDeps.channels().list_for_user(scope.user)

        channel_counts =
          FoyerWeb.LiveDeps.channels().list_all_with_member_counts()
          |> Map.new(fn {channel, count} -> {channel.id, count} end)

        on_shift_ids = FoyerWeb.LiveDeps.shifts().users_on_shift_ids()

        {:noreply,
         socket
         |> assign(:people, people)
         |> assign(:channels, channels)
         |> assign(:channel_counts, channel_counts)
         |> assign(:on_shift_ids, on_shift_ids)
         |> assign(:new_message_tab, tab)
         |> assign(:page_title, "New message")}

      :show ->
        load_conversation(socket, params["conversation_id"])
    end
  end

  defp load_conversation(socket, id) do
    scope = socket.assigns.current_scope

    try do
      channels = FoyerWeb.LiveDeps.channels().list_for_user(scope.user)
      conversations = FoyerWeb.LiveDeps.chat().inbox_for(scope.user)
      on_shift_ids = FoyerWeb.LiveDeps.shifts().users_on_shift_ids()

      conversation = FoyerWeb.LiveDeps.chat().get_conversation!(id, scope.user)
      messages = FoyerWeb.LiveDeps.chat().list_messages(conversation)

      if connected?(socket) do
        Phoenix.PubSub.subscribe(Foyer.PubSub, "chat:room:#{conversation.id}")
      end

      {:noreply,
       socket
       |> assign(:channels, channels)
       |> assign(:on_shift_ids, on_shift_ids)
       |> assign(:conversation, conversation)
       |> assign(:page_title, conversation_title(conversation, scope.user.id))
       |> stream(:conversations, conversations, reset: true)
       |> stream(:messages, messages, reset: true)}
    rescue
      Ecto.NoResultsError ->
        {:noreply,
         socket
         |> put_flash(:error, "That conversation is not available to you.")
         |> push_navigate(to: ~p"/chat")}
    end
  end

  @impl true
  def handle_event("send_message", %{"message" => attrs}, socket) do
    scope = socket.assigns.current_scope
    conversation = socket.assigns.conversation

    case FoyerWeb.LiveDeps.chat().send_message(conversation, scope.user, attrs) do
      {:ok, _message} ->
        {:noreply, socket}

      {:error, :not_implemented} ->
        {:noreply, put_flash(socket, :info, "Send is not implemented in scaffold.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Couldn't send message.")}
    end
  end

  def handle_event("new_direct_message", %{"user_id" => user_id_str}, socket) do
    current_user = socket.assigns.current_scope.user

    with {user_id, ""} <- Integer.parse(user_id_str),
         other_user <- FoyerWeb.LiveDeps.accounts().get_user!(user_id),
         {:ok, conv} <-
           FoyerWeb.LiveDeps.chat().get_or_create_direct_conversation(current_user, other_user) do
      {:noreply, push_navigate(socket, to: ~p"/chat/#{conv.id}")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not start conversation.")}
    end
  end

  @impl true
  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def render(%{live_action: :inbox} = assigns), do: render_inbox(assigns)
  def render(%{live_action: :new_message} = assigns), do: render_new_message(assigns)
  def render(%{live_action: :show} = assigns), do: render_thread(assigns)

  # ─── :inbox render ──────────────────────────────────────────────────

  defp render_inbox(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main class="foyer-shell">
        <FoyerComponents.desktop_rail
          active={:chat}
          current_scope={@current_scope}
          channels={@channels}
        />
        <div class="foyer-content">
          <FoyerComponents.desktop_topbar current_scope={@current_scope} page_title={@page_title} />

          <div class="foyer-scroll" id="chat-inbox">
            <div class="foyer-page-narrow space-y-5 md:pt-8">
              <div class="flex items-end justify-between gap-4">
                <FoyerComponents.editorial_heading>Messages</FoyerComponents.editorial_heading>
                <.link navigate={~p"/chat/new"} class="foyer-btn forest sm" id="new-message-cta">
                  <.icon name="hero-plus" class="size-4" /> New
                </.link>
              </div>

              <div id="chat-panel-inbox" class="card-parchment overflow-hidden">
                <section id="inbox" phx-update="stream" class="flex flex-col">
                  <div
                    id="chat-empty-state"
                    class="hidden only:flex min-h-28 flex-col items-center justify-center gap-3 p-8 text-center"
                  >
                    <div class="foyer-serif text-xl">No messages here yet.</div>
                    <p class="text-sm text-stone-600">
                      Start a conversation with the
                      <.link navigate={~p"/chat/new"} class="underline">New</.link>
                      button.
                    </p>
                  </div>
                  <div :for={{dom_id, c} <- @streams.conversations} id={dom_id}>
                    <.inbox_row conversation={c} current_user_id={@current_scope.user.id} />
                  </div>
                </section>
              </div>

              <section id="chat-panel-room" class="hidden md:block sr-only" aria-hidden="true">
              </section>
            </div>
          </div>

          <FoyerComponents.bottom_nav active={:chat} current_scope={@current_scope} />
        </div>
      </main>
    </Layouts.app>
    """
  end

  # ─── :new_message render ────────────────────────────────────────────

  defp render_new_message(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main class="foyer-shell">
        <FoyerComponents.desktop_rail
          active={:chat}
          current_scope={@current_scope}
          channels={@channels}
        />
        <div class="foyer-content">
          <FoyerComponents.desktop_topbar current_scope={@current_scope} page_title={@page_title} />

          <div class="foyer-scroll" id="new-message">
            <div class="foyer-page-wide space-y-5 md:pt-8">
              <.link
                navigate={~p"/chat"}
                class="inline-flex items-center gap-2 text-sm text-stone-500"
                id="back-to-inbox"
              >
                <.icon name="hero-arrow-left" class="size-4" /> Back to messages
              </.link>

              <FoyerComponents.editorial_heading>
                New message
              </FoyerComponents.editorial_heading>

              <nav
                id="new-message-tabs"
                class="flex gap-6 border-b border-[var(--foyer-rule)]"
                role="tablist"
              >
                <.link
                  patch={~p"/chat/new?tab=people"}
                  class={[
                    "px-1 pb-3 text-sm font-semibold cursor-pointer",
                    @new_message_tab == :people &&
                      "border-b-2 border-[var(--foyer-forest)] text-[var(--foyer-forest)]",
                    @new_message_tab != :people && "text-stone-500"
                  ]}
                >
                  People
                </.link>
                <.link
                  patch={~p"/chat/new?tab=channels"}
                  class={[
                    "px-1 pb-3 text-sm font-semibold cursor-pointer",
                    @new_message_tab == :channels &&
                      "border-b-2 border-[var(--foyer-forest)] text-[var(--foyer-forest)]",
                    @new_message_tab != :channels && "text-stone-500"
                  ]}
                >
                  Channels
                </.link>
              </nav>

              <input
                :if={@new_message_tab == :people}
                type="search"
                class="foyer-input h-12 text-base"
                placeholder="Search colleagues..."
                id="new-message-search"
                name="search"
              />

              <ul :if={@new_message_tab == :people} id="new-message-people" class="flex flex-col">
                <li :for={p <- @people}>
                  <button
                    type="button"
                    phx-click="new_direct_message"
                    phx-value-user_id={p.id}
                    class="flex w-full cursor-pointer items-center justify-between gap-4 rounded-lg px-3 py-3 text-left transition hover:bg-[var(--foyer-cream-deep)]"
                    id={"new-msg-person-#{p.id}"}
                  >
                    <span class="flex min-w-0 items-center gap-4">
                      <FoyerComponents.avatar initials={p.initials} />
                      <span class="min-w-0">
                        <span class="block text-base font-semibold truncate">{p.name}</span>
                        <span class="block text-sm text-stone-500 truncate">{p.title}</span>
                      </span>
                    </span>
                    <span class={[
                      "rounded-full px-3 py-1 text-xs font-semibold",
                      MapSet.member?(@on_shift_ids, p.id) && "bg-emerald-100 text-emerald-700",
                      !MapSet.member?(@on_shift_ids, p.id) && "bg-white/70 text-stone-500"
                    ]}>
                      {if MapSet.member?(@on_shift_ids, p.id), do: "On shift", else: "Off shift"}
                    </span>
                  </button>
                </li>
              </ul>

              <section :if={@new_message_tab == :channels} id="new-message-channels">
                <ul class="flex flex-col gap-3 pt-3">
                  <li :for={c <- @channels}>
                    <button
                      type="button"
                      class="flex w-full cursor-pointer items-center gap-4 rounded-lg px-3 py-2 text-left transition hover:bg-[var(--foyer-cream-deep)]"
                      id={"new-msg-channel-#{c.id}"}
                    >
                      <span class="foyer-avatar sm">
                        <.icon name="hero-users" class="size-4" />
                      </span>
                      <span>
                        <span class="block font-semibold">{channel_label(c.name)}</span>
                        <span class="block text-sm text-stone-500">
                          {channel_member_count(c, @channel_counts)} members
                        </span>
                      </span>
                    </button>
                  </li>
                </ul>
              </section>
            </div>
          </div>

          <FoyerComponents.bottom_nav active={:chat} current_scope={@current_scope} />
        </div>
      </main>
    </Layouts.app>
    """
  end

  # ─── :show render ───────────────────────────────────────────────────

  defp render_thread(assigns) do
    assigns =
      assign(
        assigns,
        :other_off_shift,
        off_shift_conversation?(
          assigns.conversation,
          assigns.on_shift_ids,
          assigns.current_scope.user.id
        )
      )

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main class="foyer-shell">
        <FoyerComponents.desktop_rail
          active={:chat}
          current_scope={@current_scope}
          channels={@channels}
        />
        <div class="foyer-content">
          <FoyerComponents.desktop_topbar current_scope={@current_scope} page_title={@page_title} />

          <div
            class="foyer-scroll md:min-h-[calc(100vh-4.5rem)]"
            id={"conversation-#{@conversation && @conversation.id}"}
          >
            <div class="mx-auto flex min-h-[calc(100vh-9rem)] w-full max-w-5xl flex-col">
              <aside id="chat-panel-inbox" class="sr-only" aria-hidden="true">
                <section id="inbox" phx-update="stream" class="flex flex-col">
                  <div :for={{dom_id, c} <- @streams.conversations} id={dom_id}>
                    <.inbox_row conversation={c} current_user_id={@current_scope.user.id} />
                  </div>
                </section>
              </aside>
              <section id="chat-panel-room" class="flex min-h-[calc(100vh-9rem)] flex-col">
                <%= if @conversation do %>
                  <header
                    class="flex items-center gap-4 border-b pb-5"
                    style="border-color: var(--foyer-rule);"
                  >
                    <.link
                      navigate={~p"/chat"}
                      class="inline-flex size-9 items-center justify-center rounded-full text-stone-500 transition hover:bg-[var(--foyer-cream-deep)] hover:text-[var(--foyer-ink)]"
                      id="back-to-inbox"
                      aria-label="Back to messages"
                    >
                      <.icon name="hero-arrow-left" class="size-6" />
                    </.link>
                    <div class="min-w-0">
                      <div class="foyer-serif truncate text-2xl">
                        {conversation_title(@conversation, @current_scope.user.id)}
                      </div>
                      <%= if other_subtitle(@conversation, @on_shift_ids, @current_scope.user.id) do %>
                        <div class="truncate text-sm text-stone-500">
                          {other_subtitle(@conversation, @on_shift_ids, @current_scope.user.id)}
                        </div>
                      <% end %>
                    </div>
                  </header>

                  <div
                    id="messages"
                    phx-update="stream"
                    class="flex flex-1 flex-col justify-end gap-3 px-0 py-6 md:px-16"
                  >
                    <div :for={{dom_id, msg} <- @streams.messages} id={dom_id}>
                      <FoyerComponents.message_bubble
                        message={msg}
                        current_user_id={@current_scope.user.id}
                      />
                    </div>
                  </div>

                  <div class="space-y-5 md:px-16">
                    <%= if @other_off_shift do %>
                      <div
                        id="off-shift-banner"
                        class="flex items-center gap-3 rounded-lg border px-4 py-3 text-sm text-stone-600"
                        style="background: color-mix(in srgb, var(--foyer-cream) 84%, white); border-color: var(--foyer-rule);"
                      >
                        <.icon name="hero-moon" class="size-5 shrink-0" />
                        <span>
                          {conversation_title(@conversation, @current_scope.user.id)} is off shift. We'll deliver this when they next clock in.
                        </span>
                      </div>
                    <% end %>

                    <form phx-submit="send_message" id="chat-compose" class="flex gap-3">
                      <input
                        type="text"
                        name="message[body]"
                        placeholder="Write a message..."
                        class="foyer-input min-h-14 flex-1 border-[var(--foyer-forest)] bg-[color-mix(in_srgb,var(--foyer-cream)_86%,white)] px-5 text-base"
                        id="chat-compose-input"
                      />
                      <button
                        class="foyer-btn forest min-h-14 px-7 text-base font-semibold"
                        type="submit"
                      >
                        Send
                      </button>
                    </form>
                  </div>
                <% else %>
                  <div class="flex items-center justify-center h-full text-center p-8">
                    <div>
                      <div class="foyer-serif text-xl">Select a conversation</div>
                      <div class="foyer-mono mt-2">Choose from the list on the left</div>
                    </div>
                  </div>
                <% end %>
              </section>
            </div>
          </div>

          <FoyerComponents.bottom_nav active={:chat} current_scope={@current_scope} />
        </div>
      </main>
    </Layouts.app>
    """
  end

  # ─── Inbox row component ────────────────────────────────────────────

  attr :conversation, Foyer.Chat.Conversation, required: true
  attr :current_user_id, :integer, required: true

  defp inbox_row(assigns) do
    ~H"""
    <.link
      navigate={~p"/chat/#{@conversation.id}"}
      class="flex items-center gap-3 p-3 rounded-lg hover:bg-[var(--foyer-cream-deep)]"
      id={"inbox-row-#{@conversation.id}"}
    >
      <div class="relative shrink-0">
        <FoyerComponents.avatar
          initials={inbox_row_initials(@conversation, @current_user_id)}
          size={:sm}
        />
      </div>
      <div class="flex-1 min-w-0">
        <div class="flex items-center justify-between gap-2">
          <span class="foyer-serif truncate">
            {inbox_row_name(@conversation, @current_user_id)}
          </span>
          <time :if={@conversation.last_message_at} class="foyer-mono shrink-0">
            {FoyerComponents.format_time(@conversation.last_message_at)}
          </time>
        </div>
        <p class="foyer-mono truncate">{inbox_row_preview(@conversation)}</p>
      </div>
    </.link>
    """
  end

  # ─── Private helpers ────────────────────────────────────────────────

  defp inbox_row_name(%{kind: :channel, channel: %{name: name}}, _), do: name

  defp inbox_row_name(%{kind: :direct, participants: participants}, user_id)
       when is_list(participants) do
    participants
    |> Enum.find(fn p -> p.user_id != user_id end)
    |> case do
      %{user: %{name: name}} -> name
      _ -> "Direct message"
    end
  end

  defp inbox_row_name(_, _), do: "Conversation"

  defp inbox_row_initials(%{kind: :channel}, _), do: "#"

  defp inbox_row_initials(%{kind: :direct, participants: participants}, user_id)
       when is_list(participants) do
    participants
    |> Enum.find(fn p -> p.user_id != user_id end)
    |> case do
      %{user: %{initials: initials}} -> initials
      _ -> "?"
    end
  end

  defp inbox_row_initials(_, _), do: "?"

  defp inbox_row_preview(%{messages: [%{body: body} | _]}) when is_binary(body) do
    if String.length(body) > 80, do: String.slice(body, 0, 80) <> "…", else: body
  end

  defp inbox_row_preview(_), do: ""

  defp channel_label(name) when is_binary(name) do
    name
    |> String.replace("Linden · ", "")
    |> String.replace("All Housekeeping", "Housekeeping")
  end

  defp channel_label(_), do: "Channel"

  defp channel_member_count(%{id: id}, counts), do: Map.get(counts, id, 0)
  defp channel_member_count(_, _), do: 0

  # Returns true when the other participant in a direct conversation is off shift.
  # Channel conversations never show the banner.
  defp off_shift_conversation?(
         %{kind: :direct, participants: participants},
         on_shift_ids,
         current_user_id
       )
       when is_list(participants) do
    other_user_id =
      participants
      |> Enum.find(fn p -> p.user_id != current_user_id end)
      |> case do
        %{user_id: uid} -> uid
        _ -> nil
      end

    not is_nil(other_user_id) and not MapSet.member?(on_shift_ids, other_user_id)
  end

  defp off_shift_conversation?(_, _, _), do: false

  defp other_subtitle(%{kind: :direct, participants: participants}, on_shift_ids, current_user_id)
       when is_list(participants) do
    case Enum.find(participants, fn p -> p.user_id != current_user_id end) do
      %{user_id: uid} ->
        if MapSet.member?(on_shift_ids, uid),
          do: "Online · on shift",
          else: "Off shift · notifications paused"

      _ ->
        nil
    end
  end

  defp other_subtitle(_, _, _), do: nil

  defp conversation_title(nil, _), do: ""

  defp conversation_title(%{kind: :channel, channel: %{name: name}}, _), do: "# " <> name

  defp conversation_title(%{kind: :direct, participants: participants}, user_id)
       when is_list(participants) do
    participants
    |> Enum.find(fn p -> p.user_id != user_id end)
    |> case do
      %{user: %{name: name}} -> name
      _ -> "Direct message"
    end
  end

  defp conversation_title(_, _), do: ""

  # Unread dot visibility needs a future shared rail attr plus read-state data.
  # The inbox row omits the dot until Foyer.Chat exposes per-conversation unread state.
end
