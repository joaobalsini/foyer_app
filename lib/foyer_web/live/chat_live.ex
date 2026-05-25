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
        {:noreply, stream(socket, :conversations, conversations, reset: true)}

      :new_message ->
        people = FoyerWeb.LiveDeps.accounts().list_people([])
        channels = FoyerWeb.LiveDeps.channels().list_for_user(scope.user)

        {:noreply,
         socket
         |> assign(:people, people)
         |> assign(:channels, channels)}

      :show ->
        load_conversation(socket, params["conversation_id"])
    end
  end

  defp load_conversation(socket, id) do
    scope = socket.assigns.current_scope

    try do
      conversation = FoyerWeb.LiveDeps.chat().get_conversation!(id, scope.user)
      messages = FoyerWeb.LiveDeps.chat().list_messages(conversation)

      if connected?(socket) do
        Phoenix.PubSub.subscribe(Foyer.PubSub, "chat:room:#{conversation.id}")
      end

      {:noreply,
       socket
       |> assign(:conversation, conversation)
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
        {:noreply, socket}

      {:error, :not_implemented} ->
        {:noreply, put_flash(socket, :info, "Send is not implemented in scaffold.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Couldn't send message.")}
    end
  end

  @impl true
  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main class="foyer-root">
        <div class="foyer-scroll" id="chat">
          <%= cond do %>
            <% @live_action == :show -> %>
              <header class="flex items-center gap-2">
                <.link navigate={~p"/chat"} class="foyer-btn ghost sm" id="back-to-inbox">
                  <.icon name="hero-arrow-left" class="size-4" /> Back
                </.link>
                <h1 class="foyer-serif text-2xl">
                  {conversation_title(@conversation, @current_scope.user.id)}
                </h1>
              </header>

              <div id="messages" phx-update="stream" class="flex flex-col gap-2">
                <div :for={{dom_id, msg} <- @streams.messages} id={dom_id}>
                  <FoyerComponents.message_bubble
                    message={msg}
                    current_user_id={@current_scope.user.id}
                  />
                </div>
              </div>

              <.form
                for={@compose_form}
                id="chat-compose"
                phx-submit="send_message"
                class="flex gap-2 mt-2"
              >
                <.input field={@compose_form[:body]} type="text" placeholder="Write a message" />
                <button class="foyer-btn forest sm" type="submit">Send</button>
              </.form>
            <% true -> %>
              <header class="flex items-start justify-between">
                <div>
                  <div class="foyer-mono">The Linden · Mayfair, London</div>
                  <h1 class="foyer-serif text-3xl">Messages</h1>
                </div>
                <.link navigate={~p"/chat/new"} class="foyer-btn sm" id="new-message-cta">
                  <.icon name="hero-pencil-square" class="size-4" /> New
                </.link>
              </header>

              <div class="foyer-fieldset">
                <input
                  type="search"
                  class="foyer-input"
                  placeholder="Search messages"
                  id="chat-search"
                  name="search"
                />
              </div>

              <%= if @live_action == :inbox do %>
                <section>
                  <div class="foyer-mono">Pinned and recent</div>
                  <div id="inbox" phx-update="stream" class="flex flex-col gap-2 mt-2">
                    <div :for={{dom_id, c} <- @streams.conversations} id={dom_id}>
                      <FoyerComponents.conversation_row
                        conversation={c}
                        current_user_id={@current_scope.user.id}
                      />
                    </div>
                  </div>
                </section>
              <% end %>

              <%= if @live_action == :new_message do %>
                <section id="new-message">
                  <h2 class="foyer-serif text-2xl">New message</h2>
                  <div class="flex gap-2 mt-2" role="tablist">
                    <button type="button" class="foyer-btn sm" id="new-msg-tab-people">
                      People
                    </button>
                    <button type="button" class="foyer-btn sm" id="new-msg-tab-channels">
                      Channels
                    </button>
                  </div>
                  <div class="foyer-mono mt-3">People</div>
                  <ul class="flex flex-col gap-2 mt-2">
                    <li :for={p <- @people}>
                      <button
                        type="button"
                        class="foyer-btn w-full text-left"
                        id={"new-msg-person-#{p.id}"}
                      >
                        <FoyerComponents.avatar initials={p.initials} size={:sm} />
                        <span class="ml-2">{p.name}</span>
                      </button>
                    </li>
                  </ul>
                  <div class="foyer-mono mt-3">Channels</div>
                  <ul class="flex flex-col gap-2 mt-2">
                    <li :for={c <- @channels}>
                      <button
                        type="button"
                        class="foyer-btn w-full text-left"
                        id={"new-msg-channel-#{c.id}"}
                      >
                        # {c.name}
                      </button>
                    </li>
                  </ul>
                </section>
              <% end %>
          <% end %>

          <FoyerComponents.bottom_nav active={:chat} current_scope={@current_scope} />
        </div>
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
end
