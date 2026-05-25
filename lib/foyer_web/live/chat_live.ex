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
         |> assign(:channels, channels)}

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
      conversations = FoyerWeb.LiveDeps.chat().inbox_for(scope.user)
      channels = FoyerWeb.LiveDeps.channels().list_for_user(scope.user)
      on_shift_ids = FoyerWeb.LiveDeps.shifts().users_on_shift_ids()

      conversation = FoyerWeb.LiveDeps.chat().get_conversation!(id, scope.user)
      messages = FoyerWeb.LiveDeps.chat().list_messages(conversation)

      if connected?(socket) do
        Phoenix.PubSub.subscribe(Foyer.PubSub, "chat:room:#{conversation.id}")
      end

      {:noreply,
       socket
       |> stream(:conversations, conversations, reset: true)
       |> assign(:channels, channels)
       |> assign(:on_shift_ids, on_shift_ids)
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
      <main class="foyer-shell">
        <FoyerComponents.desktop_rail
          active={:chat}
          current_scope={@current_scope}
          channels={@channels}
        />
        <div class="foyer-content">
          <div class="foyer-scroll md:flex md:flex-row md:gap-0 md:p-0" id="chat">
            <%!-- Left panel: inbox (always visible at md:+) --%>
            <div
              id="chat-panel-inbox"
              class={[
                "md:flex-shrink-0 md:w-72 md:border-r md:flex md:flex-col md:gap-0 md:overflow-y-auto",
                @live_action == :show && "hidden md:flex"
              ]}
              style="border-color: var(--foyer-rule);"
            >
              <div class="p-4 flex items-start justify-between">
                <div>
                  <div class="foyer-mono">The Linden · Mayfair, London</div>
                  <h1 class="foyer-serif text-3xl">Messages</h1>
                </div>
                <.link navigate={~p"/chat/new"} class="foyer-btn sm" id="new-message-cta">
                  <.icon name="hero-pencil-square" class="size-4" /> New
                </.link>
              </div>

              <div class="foyer-fieldset px-4">
                <input
                  type="search"
                  class="foyer-input"
                  placeholder="Search messages"
                  id="chat-search"
                  name="search"
                />
              </div>

              <section class="p-4">
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

              <%= if @live_action == :new_message do %>
                <section id="new-message" class="p-4">
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

              <FoyerComponents.bottom_nav active={:chat} current_scope={@current_scope} />
            </div>

            <%!-- Right panel: room (hidden on mobile unless :show; always shown at md:+) --%>
            <div
              id="chat-panel-room"
              class={[
                "flex-1 flex flex-col gap-2 p-4 min-w-0",
                @live_action == :show && "flex",
                @live_action != :show && "hidden md:flex"
              ]}
            >
              <%= if @live_action == :show and @conversation do %>
                <header class="flex items-center gap-2">
                  <.link
                    navigate={~p"/chat"}
                    class="foyer-btn ghost sm md:hidden"
                    id="back-to-inbox"
                  >
                    <.icon name="hero-arrow-left" class="size-4" /> Back
                  </.link>
                  <h1 class="foyer-serif text-2xl">
                    {conversation_title(@conversation, @current_scope.user.id)}
                  </h1>
                </header>

                <%= if off_shift_conversation?(@conversation, @on_shift_ids, @current_scope.user.id) do %>
                  <div
                    id="off-shift-banner"
                    class="rounded-lg p-3"
                    style="background: var(--foyer-claret-soft); color: var(--foyer-claret);"
                  >
                    <span class="foyer-mono">
                      Off shift · notifications paused for this colleague
                    </span>
                  </div>
                <% end %>

                <div id="messages" phx-update="stream" class="flex flex-col gap-2 flex-1">
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
              <% else %>
                <div class="flex items-center justify-center h-full text-center p-8">
                  <div>
                    <div class="foyer-serif text-xl">Select a conversation</div>
                    <div class="foyer-mono mt-2">Choose from the list on the left</div>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </main>
    </Layouts.app>
    """
  end

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
