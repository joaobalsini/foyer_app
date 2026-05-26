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

  attr :active, :atom, required: true, values: [:today, :house, :chat, :me, :people, :profile]
  attr :current_scope, FoyerWeb.Scope, required: true
  attr :chat_unread_count, :integer, default: 0

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
          <span class="relative">
            Chat
            <span
              :if={@chat_unread_count > 0}
              class="absolute -right-2 -top-1 size-2 rounded-full bg-[var(--foyer-claret)]"
              id="bottom-nav-chat-unread-dot"
              aria-label={"#{@chat_unread_count} unread chat messages"}
            >
            </span>
          </span>
        </.link>
        <.link
          id="bottom-nav-me"
          navigate={~p"/me"}
          class={["foyer-bottom-nav__item", @active in [:me, :profile] && "is-active"]}
          aria-current={if @active in [:me, :profile], do: "page", else: nil}
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
          <span class="relative">
            Chat
            <span
              :if={@chat_unread_count > 0}
              class="absolute -right-2 -top-1 size-2 rounded-full bg-[var(--foyer-claret)]"
              id="bottom-nav-chat-unread-dot"
              aria-label={"#{@chat_unread_count} unread chat messages"}
            >
            </span>
          </span>
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

  attr :active, :atom, required: true, values: [:today, :house, :chat, :me, :people, :profile]
  attr :current_scope, FoyerWeb.Scope, required: true
  attr :channels, :list, default: []
  attr :property_name, :string, default: "The Linden · Mayfair"
  attr :chat_unread_count, :integer, default: 0

  @doc """
  Fixed left side-rail for desktop widths (`md:+`). Hidden at mobile via CSS
  (`.foyer-rail { display: none }` below `768px`). Stable IDs for smoke tests:
  `#desktop-rail`, `#rail-nav-today`, `#rail-nav-house`, `#rail-nav-chat`,
  `#rail-nav-people`.

  When off-shift, House/Chat/People render as disabled `<button>` elements
  matching the same discipline as `bottom_nav/1`.

  The profile chip at the bottom links to /me and is always clickable.
  """
  def desktop_rail(assigns) do
    ~H"""
    <nav id="desktop-rail" class="foyer-rail" aria-label="Main navigation">
      <%!-- Wordmark --%>
      <div class="foyer-rail__header">
        <div class="foyer-serif text-xl">Foyer</div>
        <div class="foyer-mono">{@property_name}</div>
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
          <.icon name="hero-building-library" class="size-4" /> The House
        </.link>
        <.link
          id="rail-nav-chat"
          navigate={~p"/chat"}
          class={["foyer-rail__item", @active == :chat && "is-active"]}
          aria-current={if @active == :chat, do: "page", else: nil}
        >
          <span class="relative inline-flex">
            <.icon name="hero-chat-bubble-left-right" class="size-4" />
            <span
              :if={@chat_unread_count > 0}
              id="rail-chat-unread"
              class="absolute -top-0.5 -right-0.5 size-2 rounded-full bg-[var(--foyer-claret)]"
              aria-label={"#{@chat_unread_count} unread chat messages"}
            >
            </span>
          </span>
          Chat
        </.link>
        <.link
          id="rail-nav-people"
          navigate={~p"/people"}
          class={["foyer-rail__item", @active == :people && "is-active"]}
          aria-current={if @active == :people, do: "page", else: nil}
        >
          <.icon name="hero-users" class="size-4" /> People
        </.link>
      <% else %>
        <button
          id="rail-nav-house"
          type="button"
          disabled
          aria-disabled="true"
          class="foyer-rail__item opacity-40 cursor-not-allowed"
        >
          <.icon name="hero-building-library" class="size-4" /> The House
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
          <.icon name="hero-user-circle" class="size-4" /> Profile
        </button>
      <% end %>

      <%!-- Channels sub-group (shown when list is not empty) --%>
      <%= if @channels != [] do %>
        <div class="foyer-rail__section">
          <div class="foyer-mono">Channels</div>
          <hr class="foyer-rail__section-rule" />
        </div>
        <.link
          :for={ch <- @channels}
          navigate={~p"/chat/new?channel_id=#{ch.id}"}
          class="foyer-rail__item pl-6"
          id={"rail-channel-#{ch.id}"}
        >
          {ch.name}
        </.link>
      <% end %>

      <%!-- Footer: profile chip + sign out --%>
      <div class="foyer-rail__footer">
        <.link
          navigate={~p"/me"}
          id={if @current_scope.on_shift?, do: "rail-nav-me", else: "rail-profile-link"}
          class={[
            "foyer-rail__profile",
            @active in [:me, :profile] && "foyer-rail__item is-active",
            @active not in [:me, :profile] && "foyer-rail__item"
          ]}
          aria-current={if @active in [:me, :profile], do: "page", else: nil}
        >
          <.avatar initials={@current_scope.user.initials} size={:sm} />
          <div class="min-w-0">
            <div class="text-sm font-semibold truncate">{@current_scope.user.name}</div>
            <div class="foyer-mono">{@current_scope.user.title}</div>
          </div>
        </.link>
        <.link
          href={~p"/session"}
          method="delete"
          id="rail-sign-out"
          class="foyer-rail__sign-out"
        >
          <.icon name="hero-arrow-left-on-rectangle" class="size-4" /> Sign out
        </.link>
      </div>
    </nav>
    """
  end

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

  attr :label, :string, default: nil
  attr :class, :string, default: nil
  slot :inner_block

  def section_label(assigns) do
    ~H"""
    <div class={["foyer-mono", @class]}>{@label}{render_slot(@inner_block)}</div>
    """
  end

  def pulse(assigns) do
    ~H"""
    <span class="foyer-pulse" aria-hidden="true"></span>
    """
  end

  attr :kind, :atom,
    required: true,
    values: [:on_shift, :off_shift, :pinned, :ack_required, :manager_only]

  attr :label, :string, default: nil
  attr :class, :string, default: ""

  def status_pill(assigns) do
    {pill_class, default_text} = status_pill_for(assigns.kind)
    assigns = assign(assigns, pill_class: pill_class, text: assigns.label || default_text)

    ~H"""
    <span class={["foyer-tag", @pill_class, @class]} data-pill={@kind}>
      <span
        :if={@kind == :on_shift}
        class="foyer-pulse"
        aria-hidden="true"
      >
      </span>
      {@text}
    </span>
    """
  end

  defp status_pill_for(:on_shift), do: {"moss", "On shift"}
  defp status_pill_for(:off_shift), do: {"outline", "Off shift · notifications paused"}
  defp status_pill_for(:pinned), do: {"claret", "Pinned"}
  defp status_pill_for(:ack_required), do: {"outline", "Ack required"}
  defp status_pill_for(:manager_only), do: {"forest", "Manager view only"}

  attr :class, :string, default: ""
  slot :inner_block, required: true

  def editorial_heading(assigns) do
    ~H"""
    <h1 class={["foyer-serif text-3xl sm:text-4xl leading-tight", @class]}>
      {render_slot(@inner_block)}
    </h1>
    """
  end

  @value_labels %{
    "care" => "Care",
    "craft" => "Craft",
    "warmth" => "Warmth",
    "discretion" => "Discretion",
    "initiative" => "Initiative",
    "excellence" => "Excellence",
    "team" => "Team"
  }

  attr :value, :string, required: true
  attr :selected, :boolean, default: false

  def house_value_chip(assigns) do
    assigns = assign(assigns, :label, Map.get(@value_labels, assigns.value, assigns.value))

    ~H"""
    <span
      data-value={@value}
      class={[
        "inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-medium border",
        @selected && "bg-[var(--foyer-forest)] text-[var(--foyer-cream)] border-[var(--foyer-forest)]",
        !@selected && "bg-transparent border-[var(--foyer-rule)]"
      ]}
    >
      {@label}
    </span>
    """
  end

  attr :current_scope, FoyerWeb.Scope, required: true
  attr :page_title, :string, default: nil

  @doc """
  Sticky topbar rendered above the main content pane on desktop (`md:+`).
  Shows the current page title on the left and a "+ New" dropdown on the right.
  The dropdown exposes: New chat · New announcement (managers only) · Give recognition.

  Stable IDs: `#desktop-topbar`, `#new-menu`, `#new-menu-trigger`, `#new-menu-panel`.
  """
  def desktop_topbar(assigns) do
    ~H"""
    <header
      id="desktop-topbar"
      class="hidden md:flex items-center justify-between gap-4 px-6 py-3 border-b foyer-rail__header sticky top-0 z-20"
    >
      <div class="foyer-serif text-lg truncate">
        {@page_title || ""}
      </div>

      <details
        :if={@current_scope.on_shift?}
        id="new-menu"
        class="relative [&_summary::-webkit-details-marker]:hidden marker:hidden group"
      >
        <summary
          id="new-menu-trigger"
          class="foyer-btn sm cursor-pointer list-none inline-flex items-center gap-1 select-none"
        >
          <.icon name="hero-plus" class="size-4" /> New
        </summary>
        <div
          id="new-menu-panel"
          class="absolute right-0 mt-2 w-64 rounded-lg border p-2 z-30 shadow-xl"
          style="background: var(--foyer-cream-deep); border-color: var(--foyer-rule);"
        >
          <.new_menu_item
            to={~p"/chat/new"}
            icon="hero-chat-bubble-left-right"
            action="chat"
            title="New chat"
            description="Direct or group thread."
          />
          <.new_menu_item
            :if={manager?(@current_scope)}
            to={~p"/announcements/new"}
            icon="hero-megaphone"
            action="announcement"
            title="New announcement"
            description="Reach the team in The House."
          />
          <.new_menu_item
            to={~p"/recognitions/new"}
            icon="hero-sparkles"
            action="recognition"
            title="Give recognition"
            description="Shout out a colleague."
          />
        </div>
      </details>
    </header>
    """
  end

  attr :to, :string, required: true
  attr :icon, :string, required: true
  attr :action, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true

  defp new_menu_item(assigns) do
    ~H"""
    <.link
      navigate={@to}
      data-new-action={@action}
      class="flex items-start gap-3 p-3 rounded-md hover:bg-[var(--foyer-cream)] transition"
    >
      <.icon name={@icon} class="size-5 mt-0.5 shrink-0" />
      <div class="min-w-0">
        <div class="text-sm foyer-serif">{@title}</div>
        <div class="text-xs foyer-mono">{@description}</div>
      </div>
    </.link>
    """
  end

  attr :announcement, Foyer.House.Announcement, required: true
  attr :current_user_id, :integer, default: nil

  def announcement_card(assigns) do
    assigns =
      assigns
      |> assign(:ack_state, announcement_ack_state(assigns.announcement, assigns.current_user_id))
      |> assign(:ack_count, association_count(assigns.announcement.acks))
      |> assign(
        :ack_denominator,
        association_count(assigns.announcement.reads) +
          association_count(assigns.announcement.acks)
      )

    ~H"""
    <article
      class={[
        "announcement-card",
        @ack_state == :needs_ack && "needs-ack",
        @ack_state == :acked && "acked"
      ]}
      id={"announcement-card-#{@announcement.id}"}
      data-ack-state={@ack_state}
    >
      <div class="announcement-card__meta">
        <%= if @announcement.pinned_at do %>
          <span class="foyer-tag claret">Pinned</span>
        <% end %>
        <%= cond do %>
          <% @ack_state == :needs_ack -> %>
            <span class="announcement-card__ack-pill urgent">
              <.icon name="hero-exclamation-circle" class="size-4" /> Needs your ack
            </span>
          <% @ack_state == :acked -> %>
            <span class="announcement-card__ack-pill done">
              <.icon name="hero-check-circle" class="size-4" /> Acknowledged
            </span>
          <% @announcement.requires_ack -> %>
            <span class="announcement-card__ack-pill">Ack required</span>
          <% true -> %>
        <% end %>
        <span class="foyer-mono ml-auto">{@announcement.channel && @announcement.channel.name}</span>
      </div>
      <h3 class="announcement-card__title">{@announcement.title}</h3>
      <p class="announcement-card__body">{truncate(@announcement.body)}</p>
      <div class="announcement-card__footer">
        <.avatar :if={@announcement.author} initials={@announcement.author.initials} size={:sm} />
        <span class="announcement-card__author">
          {@announcement.author && @announcement.author.name}
        </span>
        <span
          :if={@announcement.requires_ack && @ack_denominator > 0}
          class="foyer-mono text-xs ml-auto"
        >
          {@ack_count}/{@ack_denominator} acknowledged
        </span>
        <.link
          navigate={~p"/announcements/#{@announcement.id}"}
          class="foyer-btn sm shrink-0 ml-auto"
          id={"announcement-card-link-#{@announcement.id}"}
        >
          View
        </.link>
      </div>
    </article>
    """
  end

  defp announcement_ack_state(%{requires_ack: false}, _), do: :none

  defp announcement_ack_state(%{author_id: user_id}, user_id) when not is_nil(user_id),
    do: :not_required

  defp announcement_ack_state(%{acks: acks}, user_id)
       when is_list(acks) and not is_nil(user_id) do
    if Enum.any?(acks, fn ack -> ack.user_id == user_id end), do: :acked, else: :needs_ack
  end

  defp announcement_ack_state(%{requires_ack: true}, user_id) when not is_nil(user_id),
    do: :needs_ack

  defp announcement_ack_state(%{requires_ack: true}, _), do: :requires_ack
  defp announcement_ack_state(_, _), do: :none

  defp association_count(items) when is_list(items), do: length(items)
  defp association_count(_), do: 0

  defp truncate(nil), do: ""

  defp truncate(text) when is_binary(text) do
    if String.length(text) > 200, do: String.slice(text, 0, 200) <> "...", else: text
  end

  attr :recognition, Foyer.Recognitions.Recognition, required: true
  attr :current_user_id, :integer, default: nil

  def recognition_card(assigns) do
    ~H"""
    <article
      class="rounded-lg border p-5 md:p-6 min-h-52 flex flex-col justify-between gap-8"
      style="background: color-mix(in srgb, var(--foyer-brass-soft) 42%, var(--foyer-cream) 58%); border-color: color-mix(in srgb, var(--foyer-rule) 72%, var(--foyer-brass) 28%);"
      id={"rec-card-#{@recognition.id}"}
      data-rec-id={@recognition.id}
    >
      <div class="flex flex-col gap-5">
        <div class="flex items-center justify-between gap-3">
          <div class="foyer-mono flex items-center gap-2">
            <.icon name="hero-sparkles" class="size-4 text-[var(--foyer-brass)]" />
            <span>For {recipient_name(@recognition)}</span>
          </div>
          <div class="flex items-center gap-2">
            <%= if @recognition.bonus_points && @recognition.bonus_points > 0 do %>
              <span class="foyer-tag claret" data-bonus>+{@recognition.bonus_points} pts</span>
            <% end %>
            <span :if={@recognition.public == false} class="foyer-tag outline">Private</span>
          </div>
        </div>

        <p class="foyer-serif text-2xl md:text-3xl leading-tight italic">
          "{@recognition.body}"
        </p>
      </div>

      <div class="flex items-end justify-between gap-4">
        <div class="flex items-center gap-2">
          <.avatar :if={@recognition.sender} initials={@recognition.sender.initials} />
          <div>
            <div class="font-semibold">{@recognition.sender && @recognition.sender.name}</div>
            <div class="text-sm text-stone-600">{relative_day(@recognition.inserted_at)}</div>
          </div>
        </div>
        <div class="flex items-center justify-end gap-2 flex-wrap" data-values>
          <.house_value_chip :for={v <- @recognition.values || []} value={v} selected />
          <.link
            :if={own_recognition?(@recognition, @current_user_id)}
            navigate={~p"/recognitions/#{@recognition.id}"}
            class="foyer-btn sm"
            id={"recognition-view-#{@recognition.id}"}
          >
            View
          </.link>
        </div>
      </div>
    </article>
    """
  end

  defp own_recognition?(_recognition, nil), do: false
  defp own_recognition?(%{sender_id: user_id}, user_id), do: true
  defp own_recognition?(%{recipient_id: user_id}, user_id), do: true
  defp own_recognition?(_recognition, _user_id), do: false

  defp recipient_name(%{recipient: %{name: name}}) when is_binary(name), do: String.upcase(name)
  defp recipient_name(_recognition), do: "COLLEAGUE"

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
      <span
        :if={@conversation.unread?}
        class="size-2 rounded-full bg-[var(--foyer-claret)]"
        id={"conversation-unread-#{@conversation.id}"}
        aria-label={"#{@conversation.unread_count} unread"}
      >
      </span>
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

  attr :message, Foyer.Chat.Message, required: true
  attr :current_user_id, :integer, required: true

  def message_bubble(assigns) do
    mine = assigns.message.author_id == assigns.current_user_id
    assigns = assign(assigns, :mine, mine)

    ~H"""
    <div class={["flex gap-2", @mine && "justify-end"]} data-message-mine={@mine}>
      <div class={[
        "rounded-2xl px-4 py-2 max-w-[78%] text-sm leading-relaxed",
        @mine && "bg-[var(--foyer-forest)] text-[var(--foyer-cream)]",
        !@mine && "bg-[var(--foyer-cream-deep)]"
      ]}>
        <%= if @message.author && !@mine do %>
          <div class="foyer-mono mb-0.5">{@message.author.name}</div>
        <% end %>
        <p>{@message.body}</p>
        <div class="text-[10px] opacity-70 mt-1 text-right">
          {format_time(@message.inserted_at)}{if @mine and Map.get(@message, :read, false),
            do: " · Read",
            else: ""}
        </div>
      </div>
    </div>
    """
  end

  attr :card, Foyer.Profile.Card, required: true
  attr :viewer, :atom, default: :other, values: [:self, :other]
  attr :rewards, :list, default: []
  attr :self_service, :boolean, default: nil

  def profile_card(assigns) do
    # F.Profile.25 — property code from application config. All v1 users share
    # one property; per-user property codes are a v2 concern.
    assigns =
      assigns
      |> assign(:property_code, Application.get_env(:foyer, :property_code, "LDN·MAY"))
      |> assign(:self_service, self_service?(assigns))

    ~H"""
    <div class="flex flex-col gap-4" id="profile-card">
      <%!-- Identity header (F.Profile.1, F.Profile.2, F.Profile.3) --%>
      <header class="flex items-start gap-3 pt-2">
        <.avatar initials={@card.user.initials} size={:lg} />
        <div class="flex flex-col gap-1">
          <h1 class="foyer-serif text-3xl">{@card.user.name}</h1>
          <div class="foyer-mono">{@card.user.title}</div>
          <div class="foyer-mono">
            {@property_code} · Member since {member_since(@card.user)}
          </div>
          <%= if @card.user.languages && @card.user.languages != [] do %>
            <div class="foyer-mono">
              {Enum.join(@card.user.languages, " · ")}
            </div>
          <% end %>
          <%!-- F.Profile.2 — on-shift tag with animated pulse --%>
          <%!-- F.Profile.3 — absent when off-shift --%>
          <span :if={@card.on_shift?} class="foyer-tag moss self-start">
            <span class="foyer-pulse"></span>On shift
          </span>
        </div>
      </header>

      <%!-- Stats row (F.Profile.9, F.Profile.10) --%>
      <section class="grid grid-cols-2 gap-2" id="profile-stats">
        <div class="rounded-lg border p-3" style="border-color: var(--foyer-rule);">
          <div class="foyer-mono">Recognitions this month</div>
          <div
            class="foyer-serif text-2xl"
            id="stats-recognitions-this-month"
          >
            {@card.received_this_month}
          </div>
        </div>
        <div class="rounded-lg border p-3" style="border-color: var(--foyer-rule);">
          <%!-- F.Profile.10 — ack-on-time placeholder; analytics not yet implemented --%>
          <div class="foyer-mono">Ack on time</div>
          <div class="foyer-serif text-2xl" id="stats-ack-on-time">—</div>
        </div>
      </section>

      <%!-- Received recognitions (F.Profile.4, F.Profile.5, F.Profile.6, F.Profile.20) --%>
      <section id="recognitions-received">
        <div class="flex items-center gap-2 mb-2">
          <div class="foyer-mono">Recognition received</div>
          <%= if @card.received != [] do %>
            <span class="foyer-tag outline">{length(@card.received)}</span>
          <% end %>
        </div>
        <%= if @card.received == [] do %>
          <%!-- F.Profile.20 — empty state --%>
          <p class="foyer-mono text-center py-4" id="recognitions-received-empty">
            No recognitions yet
          </p>
        <% else %>
          <div class="flex flex-col gap-2">
            <.profile_recognition_card
              :for={r <- @card.received}
              recognition={r}
              show_recipient={false}
            />
          </div>
        <% end %>
      </section>

      <%!-- Given recognitions — own profile only (F.Profile.7, F.Profile.8) --%>
      <%= if @viewer == :self do %>
        <section id="recognitions-given">
          <div class="flex items-center gap-2 mb-2">
            <div class="foyer-mono">Given</div>
            <%= if @card.given != [] do %>
              <span class="foyer-tag outline">{length(@card.given)}</span>
            <% end %>
          </div>
          <%= if @card.given == [] do %>
            <p class="foyer-mono text-center py-4" id="recognitions-given-empty">
              No recognitions given yet
            </p>
          <% else %>
            <div class="flex flex-col gap-2">
              <.profile_recognition_card
                :for={r <- @card.given}
                recognition={r}
                show_recipient={true}
              />
            </div>
          <% end %>
        </section>
      <% end %>

      <%!-- Foyer points balance (F.Profile.11) --%>
      <section id="points">
        <div class="flex items-center gap-2 mb-2">
          <span class="foyer-tag outline">
            <.icon name="hero-star" class="size-3" />Foyer points · balance
          </span>
        </div>
        <div class="foyer-serif text-3xl">{@card.points}</div>
        <p class="foyer-mono mt-1">
          Earned through recognition. Trade for time, meals, the spa, or pass it on as a donation.
        </p>

        <%!-- Points earned breakdown — own profile only (F.Profile.12, F.Profile.24) --%>
        <%= if @viewer == :self and @card.points_earned != [] do %>
          <div class="mt-3" id="points-earned">
            <div class="foyer-mono mb-2">How you earned bonus points</div>
            <div class="flex flex-col gap-2">
              <div
                :for={r <- @card.points_earned}
                class="flex items-center gap-2 rounded-lg border p-2"
                style="border-color: var(--foyer-rule);"
              >
                <.avatar initials={(r.sender && r.sender.initials) || "?"} size={:sm} />
                <span class="flex-1 text-sm">{truncate(r.body)}</span>
                <span class="foyer-tag forest">+{r.bonus_points} pts</span>
              </div>
            </div>
          </div>
        <% end %>
      </section>

      <%!-- Rewards catalog — own profile only (F.Profile.13, F.Profile.14, F.Profile.15) --%>
      <%= if @self_service and @rewards != [] do %>
        <section id="rewards">
          <div class="foyer-mono mb-2">Trade your points</div>
          <div class="grid grid-cols-2 md:grid-cols-3 gap-2">
            <div
              :for={item <- @rewards}
              class={[
                "rounded-lg border p-3 flex flex-col gap-1",
                item.cost > @card.points && "opacity-50"
              ]}
              style="border-color: var(--foyer-rule);"
            >
              <.icon name={item.icon} class="size-5" />
              <div class="foyer-mono">{item.cost} pts</div>
              <div class="foyer-serif">{item.title}</div>
              <div class="text-xs" style="color: var(--foyer-ink-soft);">{item.description}</div>
              <%!-- F.Profile.14 — no redeem button; "Coming soon" label only --%>
              <div class="foyer-mono mt-1">Coming soon</div>
            </div>
          </div>
          <p class="foyer-mono mt-2" style="color: var(--foyer-ink-soft);">
            Redemptions are confirmed by your department head within 24 hours.
          </p>
        </section>
      <% end %>

      <%!-- Settings links — own profile only, inert (F.Profile.14, v2 nit) --%>
      <%= if @self_service do %>
        <section id="profile-settings">
          <div class="foyer-mono mb-2">Settings</div>
          <div class="flex flex-col gap-1">
            <button type="button" aria-disabled="true" class="foyer-btn ghost">
              Notifications &amp; alerts <span class="foyer-mono ml-auto">Coming soon</span>
            </button>
            <button type="button" aria-disabled="true" class="foyer-btn ghost">
              Languages &amp; translation <span class="foyer-mono ml-auto">Coming soon</span>
            </button>
            <button type="button" aria-disabled="true" class="foyer-btn ghost">
              Shift availability <span class="foyer-mono ml-auto">Coming soon</span>
            </button>
          </div>
        </section>
      <% end %>
    </div>
    """
  end

  defp self_service?(%{self_service: nil, viewer: viewer}), do: viewer == :self
  defp self_service?(%{self_service: self_service}), do: self_service

  attr :recognition, Foyer.Recognitions.Recognition, required: true
  attr :show_recipient, :boolean, default: false

  defp profile_recognition_card(assigns) do
    ~H"""
    <article
      class="rounded-lg border p-3 flex flex-col gap-2"
      style="border-color: var(--foyer-rule);"
      id={"recognition-#{@recognition.id}"}
    >
      <%= if @show_recipient and @recognition.recipient do %>
        <div class="foyer-mono">
          For {@recognition.recipient.name}
        </div>
      <% end %>
      <p class="foyer-serif text-lg">{@recognition.body}</p>
      <%!-- House value tags (F.Profile.21) --%>
      <%= if @recognition.values && @recognition.values != [] do %>
        <div class="flex flex-wrap gap-1">
          <span :for={v <- @recognition.values} class="foyer-tag outline">
            {String.upcase(v)}
          </span>
        </div>
      <% end %>
      <div class="flex items-center gap-2">
        <.avatar :if={@recognition.sender} initials={@recognition.sender.initials} size={:sm} />
        <span class="text-sm">{@recognition.sender && @recognition.sender.name}</span>
        <%!-- Bonus points badge (F.Profile.22) --%>
        <%= if @recognition.bonus_points && @recognition.bonus_points > 0 do %>
          <span class="foyer-tag forest ml-auto">+{@recognition.bonus_points} pts</span>
        <% end %>
        <span class={[
          "foyer-mono",
          @recognition.bonus_points && @recognition.bonus_points > 0 && "ml-0",
          (@recognition.bonus_points == nil or @recognition.bonus_points == 0) && "ml-auto"
        ]}>
          {relative_date(@recognition.inserted_at)}
        </span>
      </div>
    </article>
    """
  end

  attr :user, Foyer.Accounts.User, required: true
  attr :subtitle, :string, default: nil
  attr :action, :string, default: nil
  attr :action_href, :string, default: nil
  attr :action_event, :string, default: nil
  attr :action_value, :any, default: nil

  def colleague_row(assigns) do
    ~H"""
    <div
      class="flex items-center justify-between gap-3 p-3 rounded-lg hover:bg-[var(--foyer-cream-deep)]"
      data-colleague-id={@user.id}
      data-shift={if(Map.get(@user, :on_shift, false), do: "on_shift", else: "off_shift")}
    >
      <div class="flex items-center gap-3 min-w-0">
        <.avatar initials={@user.initials} />
        <div class="min-w-0">
          <div class="flex items-center gap-2">
            <span class="foyer-serif truncate">{@user.name}</span>
            <.status_pill
              :if={Map.get(@user, :on_shift, false)}
              kind={:on_shift}
              label="On shift"
              class="text-[10px]"
            />
          </div>
          <div class="foyer-mono truncate">{@subtitle || @user.title}</div>
        </div>
      </div>
      <button
        :if={@action && @action_event}
        type="button"
        phx-click={@action_event}
        phx-value-user_id={@action_value}
        class="foyer-btn sm shrink-0"
        data-colleague-action
      >
        {@action}
      </button>
      <.link
        :if={@action && is_nil(@action_event)}
        navigate={@action_href}
        class="foyer-btn ghost sm"
        data-colleague-action
      >
        {@action}
      </.link>
    </div>
    """
  end

  @spec member_since(Foyer.Accounts.User.t()) :: integer() | String.t()
  defp member_since(%{inserted_at: %DateTime{year: year}}), do: year
  defp member_since(_), do: "—"

  @spec format_time(DateTime.t() | nil) :: String.t()
  def format_time(nil), do: ""

  def format_time(%DateTime{} = dt) do
    "#{pad(dt.hour)}:#{pad(dt.minute)}"
  end

  defp pad(n) when n < 10, do: "0#{n}"
  defp pad(n), do: "#{n}"

  defp relative_day(nil), do: ""

  defp relative_day(%DateTime{} = dt) do
    today = Date.utc_today()
    date = DateTime.to_date(dt)

    case Date.diff(today, date) do
      0 -> "Today"
      1 -> "Yesterday"
      _ -> Calendar.strftime(date, "%a %-d %b")
    end
  end

  @spec relative_date(DateTime.t() | nil) :: String.t()
  defp relative_date(nil), do: ""

  defp relative_date(%DateTime{} = dt) do
    today = Date.utc_today()
    date = DateTime.to_date(dt)
    diff = Date.diff(today, date)

    cond do
      diff == 0 -> "Today"
      diff == 1 -> "Yesterday"
      diff < 7 -> Calendar.strftime(date, "%a %-d %b")
      true -> Calendar.strftime(date, "%-d %b %Y")
    end
  end

  @spec manager?(Scope.t()) :: boolean()
  defdelegate manager?(scope), to: Scope
end
