defmodule FoyerWeb.FoyerComponents do
  @moduledoc """
  Shared visual atoms specific to Foyer — bottom navigation, avatar, tag, pulse,
  feed cards, message bubble. All built from the `.foyer-*` CSS vocabulary
  defined in `assets/css/app.css`. See plan §8 for the contract.
  """
  use Phoenix.Component

  import FoyerWeb.CoreComponents, only: [icon: 1]

  alias FoyerWeb.Scope

  use Phoenix.VerifiedRoutes,
    endpoint: FoyerWeb.Endpoint,
    router: FoyerWeb.Router,
    statics: FoyerWeb.static_paths()

  # ---------------------------------------------------------------------------
  # Bottom navigation
  # ---------------------------------------------------------------------------

  attr :active, :atom, required: true, values: [:today, :house, :chat, :me]
  attr :current_scope, FoyerWeb.Scope, required: true

  @doc """
  Fixed bottom navigation. Stable IDs (`#bottom-nav-today`, `#bottom-nav-house`,
  `#bottom-nav-chat`, `#bottom-nav-me`) so smoke tests can assert reliably.

  When the user is off-shift, House/Chat/Me render as disabled buttons (defence
  in depth — the route-level `:ensure_on_shift` hook is the actual guard).
  """
  def bottom_nav(assigns) do
    ~H"""
    <nav class="foyer-bottom-nav" aria-label="Main navigation">
      <.link
        id="bottom-nav-today"
        navigate={~p"/today"}
        class={["foyer-bottom-nav__item", @active == :today && "is-active"]}
        aria-current={if @active == :today, do: "page", else: nil}
      >
        <.icon name="hero-home" class="size-5" />
        <span>Today</span>
      </.link>

      <%= if @current_scope.on_shift? do %>
        <.link
          id="bottom-nav-house"
          navigate={~p"/house"}
          class={["foyer-bottom-nav__item", @active == :house && "is-active"]}
          aria-current={if @active == :house, do: "page", else: nil}
        >
          <.icon name="hero-building-library" class="size-5" />
          <span>House</span>
        </.link>
        <.link
          id="bottom-nav-chat"
          navigate={~p"/chat"}
          class={["foyer-bottom-nav__item", @active == :chat && "is-active"]}
          aria-current={if @active == :chat, do: "page", else: nil}
        >
          <.icon name="hero-chat-bubble-left-right" class="size-5" />
          <span>Chat</span>
        </.link>
        <.link
          id="bottom-nav-me"
          navigate={~p"/me"}
          class={["foyer-bottom-nav__item", @active == :me && "is-active"]}
          aria-current={if @active == :me, do: "page", else: nil}
        >
          <.icon name="hero-user-circle" class="size-5" />
          <span>Me</span>
        </.link>
      <% else %>
        <button
          id="bottom-nav-house"
          type="button"
          disabled
          aria-disabled="true"
          class="foyer-bottom-nav__item"
        >
          <.icon name="hero-building-library" class="size-5" />
          <span>House</span>
        </button>
        <button
          id="bottom-nav-chat"
          type="button"
          disabled
          aria-disabled="true"
          class="foyer-bottom-nav__item"
        >
          <.icon name="hero-chat-bubble-left-right" class="size-5" />
          <span>Chat</span>
        </button>
        <button
          id="bottom-nav-me"
          type="button"
          disabled
          aria-disabled="true"
          class="foyer-bottom-nav__item"
        >
          <.icon name="hero-user-circle" class="size-5" />
          <span>Me</span>
        </button>
      <% end %>
    </nav>
    """
  end

  # ---------------------------------------------------------------------------
  # Desktop side-rail
  # ---------------------------------------------------------------------------

  attr :active, :atom, required: true, values: [:today, :house, :chat, :me]
  attr :current_scope, FoyerWeb.Scope, required: true
  attr :channels, :list, default: []

  @doc """
  Fixed left side-rail for desktop widths (`md:+`). Hidden at mobile via CSS
  (`.foyer-rail { display: none }` below `768px`). Stable IDs for smoke tests:
  `#desktop-rail`, `#rail-nav-today`, `#rail-nav-house`, `#rail-nav-chat`,
  `#rail-nav-me`.

  When off-shift, House/Chat/Me render as disabled `<button>` elements matching
  the same discipline as `bottom_nav/1`.
  """
  def desktop_rail(assigns) do
    ~H"""
    <nav id="desktop-rail" class="foyer-rail" aria-label="Main navigation">
      <%!-- Wordmark --%>
      <div class="foyer-rail__header">
        <div class="foyer-serif text-xl">Foyer</div>
        <div class="foyer-mono">{@current_scope.user.department}</div>
      </div>

      <%!-- Primary nav --%>
      <.link
        id="rail-nav-today"
        navigate={~p"/today"}
        class={["foyer-rail__item", @active == :today && "is-active"]}
        aria-current={if @active == :today, do: "page", else: nil}
      >
        <.icon name="hero-home" class="size-4" /> Today
      </.link>

      <%= if @current_scope.on_shift? do %>
        <.link
          id="rail-nav-house"
          navigate={~p"/house"}
          class={["foyer-rail__item", @active == :house && "is-active"]}
          aria-current={if @active == :house, do: "page", else: nil}
        >
          <.icon name="hero-building-library" class="size-4" /> House
        </.link>
        <.link
          id="rail-nav-chat"
          navigate={~p"/chat"}
          class={["foyer-rail__item", @active == :chat && "is-active"]}
          aria-current={if @active == :chat, do: "page", else: nil}
        >
          <.icon name="hero-chat-bubble-left-right" class="size-4" /> Chat
        </.link>
        <.link
          id="rail-nav-me"
          navigate={~p"/me"}
          class={["foyer-rail__item", @active == :me && "is-active"]}
          aria-current={if @active == :me, do: "page", else: nil}
        >
          <.icon name="hero-user-circle" class="size-4" /> Me
        </.link>
      <% else %>
        <button
          id="rail-nav-house"
          type="button"
          disabled
          aria-disabled="true"
          class="foyer-rail__item opacity-40 cursor-not-allowed"
        >
          <.icon name="hero-building-library" class="size-4" /> House
        </button>
        <button
          id="rail-nav-chat"
          type="button"
          disabled
          aria-disabled="true"
          class="foyer-rail__item opacity-40 cursor-not-allowed"
        >
          <.icon name="hero-chat-bubble-left-right" class="size-4" /> Chat
        </button>
        <button
          id="rail-nav-me"
          type="button"
          disabled
          aria-disabled="true"
          class="foyer-rail__item opacity-40 cursor-not-allowed"
        >
          <.icon name="hero-user-circle" class="size-4" /> Me
        </button>
      <% end %>

      <%!-- Channels sub-group (shown when list is not empty) --%>
      <%= if @channels != [] do %>
        <div class="foyer-rail__section">
          <div class="foyer-mono">Channels</div>
        </div>
        <.link
          :for={ch <- @channels}
          navigate={~p"/chat"}
          class="foyer-rail__item pl-6"
          id={"rail-channel-#{ch.id}"}
        >
          # {ch.name}
        </.link>
      <% end %>

      <%!-- Footer: current user + sign-out --%>
      <div class="foyer-rail__footer">
        <div class="flex items-center gap-2 mb-2">
          <.avatar initials={@current_scope.user.initials} size={:sm} />
          <div>
            <div class="foyer-serif text-sm">{@current_scope.user.name}</div>
            <div class="foyer-mono">{@current_scope.user.title}</div>
          </div>
        </div>
        <.link method="delete" href={~p"/session"} class="foyer-rail__item" id="rail-sign-out">
          <.icon name="hero-arrow-right-on-rectangle" class="size-4" /> Sign out
        </.link>
      </div>
    </nav>
    """
  end

  # ---------------------------------------------------------------------------
  # Avatar
  # ---------------------------------------------------------------------------

  attr :initials, :string, required: true
  attr :size, :atom, default: :md, values: [:sm, :md, :lg]
  attr :class, :string, default: nil

  def avatar(assigns) do
    ~H"""
    <span class={[
      "foyer-avatar",
      @size == :sm && "sm",
      @size == :lg && "lg",
      @class
    ]}>
      {@initials}
    </span>
    """
  end

  # ---------------------------------------------------------------------------
  # Tag
  # ---------------------------------------------------------------------------

  attr :variant, :atom, required: true, values: [:claret, :moss, :forest, :outline]
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def tag(assigns) do
    ~H"""
    <span class={["foyer-tag", to_string(@variant), @class]}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  # ---------------------------------------------------------------------------
  # Section label (mono eyebrow)
  # ---------------------------------------------------------------------------

  attr :class, :string, default: nil
  slot :inner_block, required: true

  def section_label(assigns) do
    ~H"""
    <div class={["foyer-mono", @class]}>{render_slot(@inner_block)}</div>
    """
  end

  # ---------------------------------------------------------------------------
  # Pulse
  # ---------------------------------------------------------------------------

  def pulse(assigns) do
    ~H"""
    <span class="foyer-pulse" aria-hidden="true"></span>
    """
  end

  # ---------------------------------------------------------------------------
  # Announcement card
  # ---------------------------------------------------------------------------

  attr :announcement, Foyer.House.Announcement, required: true

  def announcement_card(assigns) do
    ~H"""
    <article
      class="rounded-lg border p-3 flex flex-col gap-2"
      style="border-color: var(--foyer-rule);"
    >
      <div class="flex items-center gap-2">
        <%= if @announcement.pinned_at do %>
          <span class="foyer-tag claret">Pinned</span>
        <% end %>
        <%= if @announcement.requires_ack do %>
          <span class="foyer-tag outline">Action</span>
        <% end %>
        <span class="foyer-mono ml-auto">{@announcement.channel && @announcement.channel.name}</span>
      </div>
      <h3 class="foyer-serif text-xl">{@announcement.title}</h3>
      <p class="text-sm">{truncate(@announcement.body)}</p>
      <div class="flex items-center gap-2 mt-1">
        <.avatar :if={@announcement.author} initials={@announcement.author.initials} size={:sm} />
        <span class="text-sm">{@announcement.author && @announcement.author.name}</span>
        <.link
          navigate={~p"/announcements/#{@announcement.id}"}
          class="foyer-btn sm ml-auto"
          id={"announcement-card-link-#{@announcement.id}"}
        >
          View details
        </.link>
      </div>
    </article>
    """
  end

  defp truncate(nil), do: ""

  defp truncate(text) when is_binary(text) do
    if String.length(text) > 200, do: String.slice(text, 0, 200) <> "...", else: text
  end

  # ---------------------------------------------------------------------------
  # Recognition card
  # ---------------------------------------------------------------------------

  attr :recognition, Foyer.Recognitions.Recognition, required: true

  def recognition_card(assigns) do
    ~H"""
    <article
      class="rounded-lg border p-3 flex flex-col gap-2"
      style="border-color: var(--foyer-rule);"
    >
      <div class="foyer-mono">
        Recognition for {@recognition.recipient && @recognition.recipient.name}
      </div>
      <p class="foyer-serif text-lg">{@recognition.body}</p>
      <div class="flex items-center gap-2 text-sm">
        <.avatar :if={@recognition.sender} initials={@recognition.sender.initials} size={:sm} />
        <span>{@recognition.sender && @recognition.sender.name}</span>
        <%= if @recognition.bonus_points && @recognition.bonus_points > 0 do %>
          <span class="foyer-tag forest ml-auto">+{@recognition.bonus_points} pts</span>
        <% end %>
      </div>
    </article>
    """
  end

  # ---------------------------------------------------------------------------
  # Conversation row
  # ---------------------------------------------------------------------------

  attr :conversation, Foyer.Chat.Conversation, required: true
  attr :current_user_id, :integer, required: true

  def conversation_row(assigns) do
    ~H"""
    <.link
      navigate={~p"/chat/#{@conversation.id}"}
      class="flex items-center gap-3 p-3 rounded-lg border"
      style="border-color: var(--foyer-rule);"
      id={"conversation-row-#{@conversation.id}"}
    >
      <%= cond do %>
        <% @conversation.kind == :channel and @conversation.channel -> %>
          <span class="foyer-avatar">#</span>
          <span class="flex-1">
            <span class="foyer-serif">{@conversation.channel.name}</span>
            <span class="foyer-mono block">{conversation_preview(@conversation)}</span>
          </span>
        <% true -> %>
          <span class="foyer-avatar">{other_initials(@conversation, @current_user_id)}</span>
          <span class="flex-1">
            <span class="foyer-serif">{other_name(@conversation, @current_user_id)}</span>
            <span class="foyer-mono block">{conversation_preview(@conversation)}</span>
          </span>
      <% end %>
    </.link>
    """
  end

  defp other_name(%{participants: participants}, current_user_id) when is_list(participants) do
    participants
    |> Enum.find(fn p -> p.user_id != current_user_id end)
    |> case do
      nil -> "Conversation"
      %{user: %{name: name}} -> name
      _ -> "Conversation"
    end
  end

  defp other_name(_, _), do: "Conversation"

  defp other_initials(%{participants: participants}, current_user_id)
       when is_list(participants) do
    participants
    |> Enum.find(fn p -> p.user_id != current_user_id end)
    |> case do
      nil -> "??"
      %{user: %{initials: initials}} -> initials
      _ -> "??"
    end
  end

  defp other_initials(_, _), do: "??"

  defp conversation_preview(%{messages: [%{body: body} | _]}), do: truncate(body)
  defp conversation_preview(_), do: ""

  # ---------------------------------------------------------------------------
  # Message bubble
  # ---------------------------------------------------------------------------

  attr :message, Foyer.Chat.Message, required: true
  attr :current_user_id, :integer, required: true

  def message_bubble(assigns) do
    ~H"""
    <div class={[
      "flex",
      @message.author_id == @current_user_id && "justify-end"
    ]}>
      <div class={[
        "rounded-lg px-3 py-2 max-w-[80%] text-sm",
        @message.author_id == @current_user_id && "bg-[var(--foyer-forest)] text-[var(--foyer-cream)]",
        @message.author_id != @current_user_id && "bg-[var(--foyer-cream-deep)]"
      ]}>
        <%= if @message.author && @message.author_id != @current_user_id do %>
          <div class="foyer-mono mb-1">{@message.author.name}</div>
        <% end %>
        {@message.body}
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Profile card — shared between `ProfileLive :me` and `PeopleLive :show`.
  # ---------------------------------------------------------------------------

  attr :card, Foyer.Profile.Card, required: true
  attr :rewards, :list, default: []

  def profile_card(assigns) do
    ~H"""
    <div class="foyer-content-cols">
      <%!-- Left column: header + stats --%>
      <div class="flex flex-col gap-4">
        <header class="flex items-center gap-3">
          <.avatar initials={@card.user.initials} size={:lg} />
          <div>
            <h1 class="foyer-serif text-3xl">{@card.user.name}</h1>
            <div class="foyer-mono">{@card.user.title}</div>
            <div class="text-sm">
              Languages · {Enum.join(@card.user.languages || [], ", ")}
            </div>
            <span :if={@card.on_shift?} class="foyer-tag moss">
              <span class="foyer-pulse"></span>On shift
            </span>
          </div>
        </header>

        <section class="grid grid-cols-2 gap-2" id="profile-stats">
          <div class="rounded-lg border p-3" style="border-color: var(--foyer-rule);">
            <div class="foyer-mono">Recognitions this month</div>
            <div class="foyer-serif text-2xl">{length(@card.received)}</div>
          </div>
          <div class="rounded-lg border p-3" style="border-color: var(--foyer-rule);">
            <div class="foyer-mono">Ack on time</div>
            <div class="foyer-serif text-2xl">—</div>
          </div>
        </section>
      </div>

      <%!-- Right column: recognitions + points + rewards (at lg:, stacks below at md: and mobile) --%>
      <div class="flex flex-col gap-4">
        <section id="recognitions-received">
          <div class="foyer-mono">Received</div>
          <div class="flex flex-col gap-2 mt-2">
            <.recognition_card :for={r <- @card.received} recognition={r} />
          </div>
        </section>

        <section id="recognitions-given">
          <div class="foyer-mono">Given</div>
          <div class="flex flex-col gap-2 mt-2">
            <.recognition_card :for={r <- @card.given} recognition={r} />
          </div>
        </section>

        <section id="points">
          <div class="foyer-mono">Foyer points</div>
          <div class="foyer-serif text-3xl">{@card.points}</div>
        </section>

        <section :if={@rewards != []} id="rewards">
          <div class="foyer-mono">Rewards</div>
          <div class="grid grid-cols-2 gap-2 mt-2">
            <div
              :for={r <- @rewards}
              class="rounded-lg border p-3"
              style="border-color: var(--foyer-rule);"
            >
              <div class="foyer-serif">{r.title}</div>
              <div class="foyer-mono">{r.cost} pts</div>
            </div>
          </div>
        </section>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Manager guard helper — re-exported here so LiveView templates can use
  # `manager?/1` without aliasing Scope. (Convenience only.)
  # ---------------------------------------------------------------------------

  @spec manager?(Scope.t()) :: boolean()
  defdelegate manager?(scope), to: Scope
end
