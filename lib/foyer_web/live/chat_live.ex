defmodule FoyerWeb.ChatLive do
  @moduledoc """
  Chat surface — `/chat` (inbox), `/chat/new` (picker), and `/chat/:conversation_id`
  (room).

  Desktop two-panel layout: the inbox panel and the room panel render
  side-by-side at `md:+`. On mobile the active live_action picks one panel.

  PubSub subscriptions:
    * `chat:inbox:<user_id>` from the auth hook (drives global unread state)
    * `chat:room:<conversation_id>` while viewing the room
  """
  use FoyerWeb, :live_view

  alias Foyer.Accounts.User
  alias FoyerWeb.FoyerComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> stream_configure(:conversations, dom_id: &"conv-#{&1.id}")
     |> stream(:conversations, [])
     |> stream_configure(:messages, dom_id: &"msg-#{&1.id}")
     |> stream(:messages, [])
     |> assign(:people, [])
     |> assign(:channels, [])
     |> assign(:channel_member_counts, %{})
     |> assign(:on_shift_user_ids, MapSet.new())
     |> assign(:conversation, nil)
     |> assign(:picker_tab, :people)
     |> assign(:compose_form, to_form(%{"body" => ""}, as: :message))
     |> assign(:unread_count, 0)
     |> assign(:page_title, "Messages")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    scope = socket.assigns.current_scope

    case socket.assigns.live_action do
      :inbox ->
        conversations = FoyerWeb.LiveDeps.chat().inbox_for(scope.user)
        {channels, channel_member_counts} = channels_for_picker(scope.user)

        {:noreply,
         socket
         |> assign(:channels, channels)
         |> assign(:channel_member_counts, channel_member_counts)
         |> assign(:conversation, nil)
         |> assign(:page_title, "Messages")
         |> assign(:unread_count, FoyerWeb.LiveDeps.chat().unread_count(scope.user))
         |> stream(:conversations, conversations, reset: true)}

      :new_message ->
        apply_new_message_params(socket, params)

      :show ->
        load_conversation(socket, params["conversation_id"])
    end
  end

  defp load_conversation(socket, id) do
    scope = socket.assigns.current_scope

    try do
      conversations = FoyerWeb.LiveDeps.chat().inbox_for(scope.user)
      {channels, channel_member_counts} = channels_for_picker(scope.user)
      on_shift_user_ids = FoyerWeb.LiveDeps.shifts().users_on_shift_ids()

      conversation = FoyerWeb.LiveDeps.chat().get_conversation!(id, scope.user)
      messages = FoyerWeb.LiveDeps.chat().list_messages(conversation)

      if connected?(socket) do
        Phoenix.PubSub.subscribe(Foyer.PubSub, "chat:room:#{conversation.id}")
      end

      {:ok, _read_count} = FoyerWeb.LiveDeps.chat().mark_read(conversation, scope.user)

      {:noreply,
       socket
       |> stream(:conversations, conversations, reset: true)
       |> assign(:channels, channels)
       |> assign(:channel_member_counts, channel_member_counts)
       |> assign(:on_shift_user_ids, on_shift_user_ids)
       |> assign(:conversation, conversation)
       |> assign(:unread_count, FoyerWeb.LiveDeps.chat().unread_count(scope.user))
       |> assign(:page_title, conversation_title(conversation, scope.user.id))
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
        {:noreply,
         socket
         |> assign(:compose_form, to_form(%{"body" => ""}, as: :message))
         |> push_event("clear-chat-compose", %{form_id: "chat-compose"})}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You are not a member of that conversation.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Couldn't send message.")}
    end
  end

  def handle_event("open_direct", %{"user_id" => user_id}, socket) do
    scope = socket.assigns.current_scope

    case FoyerWeb.LiveDeps.accounts().get_user(user_id) do
      %User{} = colleague ->
        case FoyerWeb.LiveDeps.chat().open_direct(scope.user, colleague) do
          {:ok, conversation} ->
            {:noreply, push_navigate(socket, to: ~p"/chat/#{conversation.id}")}

          {:error, :invalid_direct} ->
            {:noreply, put_flash(socket, :error, "Choose a colleague to start a direct message.")}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Couldn't open that conversation.")}
        end

      nil ->
        {:noreply, put_flash(socket, :error, "Choose a colleague to start a direct message.")}
    end
  end

  def handle_event("open_channel", %{"channel_id" => channel_id}, socket) do
    scope = socket.assigns.current_scope

    case FoyerWeb.LiveDeps.chat().open_channel(scope.user, channel_id) do
      {:ok, conversation} ->
        {:noreply, push_navigate(socket, to: ~p"/chat/#{conversation.id}")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "That channel is not available to you.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Couldn't open that channel.")}
    end
  end

  def handle_event("set_new_message_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :picker_tab, picker_tab(tab))}
  end

  @impl true
  def handle_info({:chat_message, message}, socket) do
    scope = socket.assigns.current_scope
    conversation = socket.assigns.conversation

    socket =
      if conversation && message.conversation_id == conversation.id do
        {:ok, _} = FoyerWeb.LiveDeps.chat().mark_read(conversation, scope.user)

        socket
        |> stream_insert(:messages, message)
        |> assign(:unread_count, FoyerWeb.LiveDeps.chat().unread_count(scope.user))
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:chat_inbox_updated, _conversation_id}, socket) do
    {:noreply, refresh_inbox(socket)}
  end

  def handle_info({:chat_unread_updated, _user_id}, socket) do
    scope = socket.assigns.current_scope
    {:noreply, assign(socket, :unread_count, FoyerWeb.LiveDeps.chat().unread_count(scope.user))}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main class="foyer-shell">
        <FoyerComponents.desktop_rail
          active={:chat}
          current_scope={@current_scope}
          channels={@channels}
          chat_unread_count={@unread_count}
        />
        <div class="foyer-content">
          <FoyerComponents.desktop_topbar current_scope={@current_scope} page_title={@page_title} />

          <div id="chat" class="chat-surface">
            <%= cond do %>
              <% @live_action == :new_message -> %>
                <section id="new-message" class="chat-picker">
                  <.link navigate={~p"/chat"} class="chat-back-link" id="back-to-messages">
                    <.icon name="hero-arrow-left" class="size-4" /> Back to messages
                  </.link>
                  <h1 class="foyer-serif text-4xl leading-tight">New message</h1>

                  <div class="chat-tabs" role="tablist" aria-label="Message recipient type">
                    <button
                      type="button"
                      class={["chat-tab", @picker_tab == :people && "is-active"]}
                      id="new-msg-tab-people"
                      phx-click="set_new_message_tab"
                      phx-value-tab="people"
                      aria-selected={@picker_tab == :people}
                    >
                      People
                    </button>
                    <button
                      type="button"
                      class={["chat-tab", @picker_tab == :channels && "is-active"]}
                      id="new-msg-tab-channels"
                      phx-click="set_new_message_tab"
                      phx-value-tab="channels"
                      aria-selected={@picker_tab == :channels}
                    >
                      Channels
                    </button>
                  </div>

                  <div :if={@picker_tab == :people} class="foyer-fieldset">
                    <input
                      type="search"
                      class="foyer-input chat-search"
                      placeholder="Search colleagues..."
                      id="new-message-search"
                      name="search"
                    />
                  </div>

                  <ul :if={@picker_tab == :people} class="chat-picker-list" id="new-message-people">
                    <li :for={p <- @people}>
                      <button
                        type="button"
                        class="chat-picker-row"
                        id={"new-msg-person-#{p.id}"}
                        phx-click="open_direct"
                        phx-value-user_id={p.id}
                      >
                        <FoyerComponents.avatar initials={p.initials} size={:sm} />
                        <span class="min-w-0">
                          <span class="chat-picker-title">{p.name}</span>
                          <span class="chat-picker-subtitle">{p.title}</span>
                        </span>
                        <span class={[
                          "chat-shift-pill",
                          MapSet.member?(@on_shift_user_ids, p.id) && "is-on"
                        ]}>
                          {if MapSet.member?(@on_shift_user_ids, p.id),
                            do: "On shift",
                            else: "Off shift"}
                        </span>
                      </button>
                    </li>
                  </ul>

                  <ul
                    :if={@picker_tab == :channels}
                    class="chat-picker-list"
                    id="new-message-channels"
                  >
                    <li :for={c <- @channels}>
                      <button
                        type="button"
                        class="chat-picker-row"
                        id={"new-msg-channel-#{c.id}"}
                        phx-click="open_channel"
                        phx-value-channel_id={c.id}
                      >
                        <span class="foyer-avatar sm">
                          <.icon name="hero-user-group" class="size-4" />
                        </span>
                        <span class="min-w-0">
                          <span class="chat-picker-title">{c.name}</span>
                          <span class="chat-picker-subtitle">
                            {channel_member_count(@channel_member_counts, c)} members
                          </span>
                        </span>
                      </button>
                    </li>
                  </ul>
                </section>
              <% @live_action == :show and @conversation -> %>
                <section id="chat-panel-room" class="chat-room">
                  <header class="chat-room-header">
                    <.link navigate={~p"/chat"} class="chat-icon-link" id="back-to-inbox">
                      <.icon name="hero-arrow-left" class="size-6" />
                    </.link>
                    <div class="min-w-0">
                      <h1 class="foyer-serif text-2xl leading-none truncate">
                        {conversation_title(@conversation, @current_scope.user.id)}
                      </h1>
                      <div
                        :if={@conversation && @conversation.kind == :direct}
                        class="chat-room-presence"
                        id="chat-room-shift-state"
                      >
                        {conversation_shift_state(
                          @conversation,
                          @current_scope.user.id,
                          @on_shift_user_ids
                        )} · notifications paused
                      </div>
                    </div>
                  </header>

                  <div id="messages" phx-update="stream" class="chat-message-list">
                    <div :for={{dom_id, msg} <- @streams.messages} id={dom_id}>
                      <FoyerComponents.message_bubble
                        message={msg}
                        current_user_id={@current_scope.user.id}
                      />
                    </div>
                  </div>

                  <div class="chat-compose-wrap">
                    <div
                      :if={
                        @conversation.kind == :direct and
                          conversation_shift_state(
                            @conversation,
                            @current_scope.user.id,
                            @on_shift_user_ids
                          ) == "Off shift"
                      }
                      class="chat-delivery-note"
                    >
                      <.icon name="hero-moon" class="size-5" />
                      <span>
                        <strong>{conversation_title(@conversation, @current_scope.user.id)}</strong>
                        is off shift. We'll deliver this when they next clock in.
                      </span>
                    </div>

                    <.form
                      for={@compose_form}
                      id="chat-compose"
                      phx-submit="send_message"
                      class="chat-compose"
                    >
                      <.input
                        field={@compose_form[:body]}
                        type="text"
                        placeholder="Write a message"
                      />
                      <button class="foyer-btn forest" type="submit" id="chat-compose-submit">
                        Send
                      </button>
                    </.form>
                  </div>
                </section>
              <% true -> %>
                <section id="chat-panel-inbox" class="chat-inbox">
                  <div class="chat-inbox-heading">
                    <div>
                      <div class="foyer-mono">The Linden · Mayfair, London</div>
                      <h1 class="foyer-serif text-4xl leading-tight">Messages</h1>
                    </div>
                    <.link navigate={~p"/chat/new"} class="foyer-btn forest sm" id="new-message-cta">
                      <.icon name="hero-plus" class="size-4" /> New
                    </.link>
                  </div>

                  <div id="inbox" phx-update="stream" class="chat-inbox-list">
                    <div id="inbox-empty" class="chat-empty hidden only:flex">
                      <div class="foyer-serif text-xl">No messages here yet.</div>
                      <p>
                        Start a conversation with the <.link navigate={~p"/chat/new"}>New</.link>
                        button.
                      </p>
                    </div>
                    <div :for={{dom_id, c} <- @streams.conversations} id={dom_id}>
                      <FoyerComponents.conversation_row
                        conversation={c}
                        current_user_id={@current_scope.user.id}
                      />
                    </div>
                  </div>
                </section>
            <% end %>
          </div>
        </div>

        <FoyerComponents.bottom_nav
          active={:chat}
          current_scope={@current_scope}
          chat_unread_count={@unread_count}
        />
      </main>
    </Layouts.app>
    """
  end

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

  defp conversation_shift_state(%{participants: participants}, user_id, on_shift_user_ids)
       when is_list(participants) do
    participants
    |> Enum.find(fn p -> p.user_id != user_id end)
    |> case do
      %{user_id: other_user_id} ->
        if MapSet.member?(on_shift_user_ids, other_user_id), do: "On shift", else: "Off shift"

      _ ->
        ""
    end
  end

  defp conversation_shift_state(_, _, _), do: ""

  defp apply_new_message_params(socket, %{"channel_id" => channel_id})
       when is_binary(channel_id) and channel_id != "" do
    scope = socket.assigns.current_scope

    case FoyerWeb.LiveDeps.chat().open_channel(scope.user, channel_id) do
      {:ok, conversation} ->
        {:noreply, push_navigate(socket, to: ~p"/chat/#{conversation.id}")}

      {:error, :unauthorized} ->
        {:noreply,
         socket
         |> put_flash(:error, "That channel is not available to you.")
         |> push_navigate(to: ~p"/chat")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Couldn't open that channel.")
         |> push_navigate(to: ~p"/chat")}
    end
  end

  defp apply_new_message_params(socket, params) do
    scope = socket.assigns.current_scope
    people = FoyerWeb.LiveDeps.accounts().list_people([])
    {channels, channel_member_counts} = channels_for_picker(scope.user)
    on_shift_user_ids = FoyerWeb.LiveDeps.shifts().users_on_shift_ids()

    {:noreply,
     socket
     |> assign(:people, people)
     |> assign(:channels, channels)
     |> assign(:channel_member_counts, channel_member_counts)
     |> assign(:on_shift_user_ids, on_shift_user_ids)
     |> assign(:conversation, nil)
     |> assign(:picker_tab, picker_tab(params["tab"]))
     |> assign(:page_title, "New message")
     |> assign(:unread_count, FoyerWeb.LiveDeps.chat().unread_count(scope.user))}
  end

  defp picker_tab("channels"), do: :channels
  defp picker_tab(:channels), do: :channels
  defp picker_tab(_), do: :people

  defp channels_for_picker(user) do
    channels = FoyerWeb.LiveDeps.channels().list_for_user(user)
    channel_ids = MapSet.new(channels, & &1.id)

    counts =
      FoyerWeb.LiveDeps.channels().list_all_with_member_counts()
      |> Enum.reduce(%{}, fn {channel, count}, acc ->
        if MapSet.member?(channel_ids, channel.id) do
          Map.put(acc, channel.id, count)
        else
          acc
        end
      end)

    {channels, counts}
  end

  defp channel_member_count(counts, channel), do: Map.get(counts, channel.id, 0)

  defp refresh_inbox(socket) do
    scope = socket.assigns.current_scope

    socket =
      assign(socket, :unread_count, FoyerWeb.LiveDeps.chat().unread_count(scope.user))

    if socket.assigns.live_action == :inbox do
      stream(socket, :conversations, FoyerWeb.LiveDeps.chat().inbox_for(scope.user), reset: true)
    else
      socket
    end
  end
end
