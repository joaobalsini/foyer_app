defmodule FoyerWeb.FoyerComponentsTest do
  @moduledoc """
  Unit tests for `FoyerWeb.FoyerComponents`. Pure component rendering with
  hand-built structs — no router, no on_mount, no DB.

  Covers:
    F.Announcements.7  — author hidden from required-ack badges
    F.Chat.8           — unread dot driven by chat_unread_count
    F.Chat.9           — inbox preview renders latest message and unread state
    F.Chat.10          — bottom nav unread indicator
    F.Recognitions.5   — bonus points badge only when present
    F.Recognitions.10  — private recognition body hidden for third parties
  """
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias Foyer.Accounts.User
  alias Foyer.Channels.Channel
  alias Foyer.Chat.Conversation
  alias Foyer.Chat.Message
  alias Foyer.Chat.Participant
  alias Foyer.House.Announcement
  alias Foyer.House.AnnouncementAck
  alias Foyer.House.AnnouncementRead
  alias Foyer.Recognitions.Recognition
  alias FoyerWeb.FoyerComponents
  alias FoyerWeb.Scope

  describe "bottom_nav/1" do
    test "renders unread chat dot for on-shift users" do
      html =
        render_component(&FoyerComponents.bottom_nav/1,
          active: :chat,
          current_scope: scope(user(1), true),
          chat_unread_count: 3
        )

      assert html =~ ~s(id="bottom-nav-chat")
      assert html =~ ~s(id="bottom-nav-chat-unread-dot")
      assert html =~ ~s(aria-current="page")
    end

    test "disables gated destinations for off-shift users" do
      html =
        render_component(&FoyerComponents.bottom_nav/1,
          active: :today,
          current_scope: scope(user(1), false)
        )

      assert html =~ ~s(id="bottom-nav-house")
      assert html =~ ~s(disabled)
      assert html =~ ~s(aria-disabled="true")
    end
  end

  describe "desktop_rail/1" do
    test "F.Chat.10 — renders active nav, channels, and channel deep links" do
      html =
        render_component(&FoyerComponents.desktop_rail/1,
          active: :chat,
          current_scope: scope(user(1), true),
          channels: [%Channel{id: 10, name: "Housekeeping"}],
          chat_unread_count: 2
        )

      assert html =~ ~s(id="desktop-rail")
      assert html =~ ~s(id="rail-nav-chat")
      assert html =~ ~s(aria-current="page")
      assert html =~ ~s(id="rail-chat-unread")
      assert html =~ ~s(aria-label="2 unread chat messages")
      assert html =~ ~s(id="rail-channel-10")
      assert html =~ "/chat/new?channel_id=10"
    end

    test "omits the desktop unread dot when there are no unread messages" do
      html =
        render_component(&FoyerComponents.desktop_rail/1,
          active: :today,
          current_scope: scope(user(1), true),
          chat_unread_count: 0
        )

      refute html =~ ~s(id="rail-chat-unread")
    end

    test "disables gated destinations for off-shift users" do
      html =
        render_component(&FoyerComponents.desktop_rail/1,
          active: :today,
          current_scope: scope(user(1), false)
        )

      assert html =~ ~s(id="rail-nav-house")
      assert html =~ ~s(id="rail-nav-chat")
      assert html =~ ~s(id="rail-nav-me")
      assert html =~ ~s(aria-disabled="true")
      assert html =~ ~s(id="rail-profile-link")
    end
  end

  describe "small atoms" do
    test "avatar, status pill, and house value chip render their branch classes" do
      avatar = render_component(&FoyerComponents.avatar/1, initials: "MO", size: :sm)
      pill = render_component(&FoyerComponents.status_pill/1, kind: :on_shift)
      value = render_component(&FoyerComponents.house_value_chip/1, value: "care", selected: true)

      assert avatar =~ "foyer-avatar"
      assert avatar =~ "sm"
      assert pill =~ "On shift"
      assert pill =~ "foyer-pulse"
      assert value =~ ~s(data-value="care")
      assert value =~ "Care"
      assert value =~ "bg-[var(--foyer-forest)]"
    end

    test "slot-based atoms render their content" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <FoyerComponents.tag variant={:claret}>Pinned</FoyerComponents.tag>
        <FoyerComponents.section_label label="Channels" />
        <FoyerComponents.section_label>Today</FoyerComponents.section_label>
        <FoyerComponents.editorial_heading>Messages</FoyerComponents.editorial_heading>
        <FoyerComponents.pulse />
        """)

      assert html =~ "Pinned"
      assert html =~ "Channels"
      assert html =~ "Today"
      assert html =~ "Messages"
      assert html =~ "foyer-pulse"
    end
  end

  describe "desktop_topbar/1" do
    test "renders manager-only announcement action for managers" do
      html =
        render_component(&FoyerComponents.desktop_topbar/1,
          current_scope: scope(user(1, role: :manager), true),
          page_title: "The House"
        )

      assert html =~ ~s(id="desktop-topbar")
      assert html =~ "The House"
      assert html =~ ~s(data-new-action="chat")
      assert html =~ ~s(data-new-action="announcement")
      assert html =~ ~s(data-new-action="recognition")
    end

    test "hides manager-only announcement action for staff" do
      html =
        render_component(&FoyerComponents.desktop_topbar/1,
          current_scope: scope(user(1, role: :staff), true),
          page_title: "Messages"
        )

      assert html =~ "Messages"
      assert html =~ ~s(data-new-action="chat")
      assert html =~ ~s(data-new-action="recognition")
      refute html =~ ~s(data-new-action="announcement")
    end

    test "F.Today.22 — hides the entire +New menu when the user is off shift" do
      html =
        render_component(&FoyerComponents.desktop_topbar/1,
          current_scope: scope(user(1, role: :staff), false),
          page_title: "Today"
        )

      # The page title still renders, but the +New menu and all its items are
      # gone — off-shift users have nothing they can compose, so the affordance
      # would only lead to ensure_on_shift route gates.
      assert html =~ "Today"
      refute html =~ ~s(id="new-menu")
      refute html =~ ~s(data-new-action="chat")
      refute html =~ ~s(data-new-action="recognition")
      refute html =~ ~s(data-new-action="announcement")
    end
  end

  describe "announcement_card/1" do
    test "F.Announcements.7 — marks an acknowledgement-required announcement as owed by the current user" do
      html =
        render_component(&FoyerComponents.announcement_card/1,
          announcement: announcement(acks: []),
          current_user_id: 2
        )

      assert html =~ ~s(id="announcement-card-100")
      assert html =~ ~s(data-ack-state="needs_ack")
      assert html =~ "Needs your ack"
    end

    test "does not render an impossible 0/0 acknowledgement count" do
      html =
        render_component(&FoyerComponents.announcement_card/1,
          announcement: announcement(acks: [], reads: []),
          current_user_id: 2
        )

      assert html =~ "Needs your ack"
      refute html =~ "0/0 acknowledged"
      refute html =~ "acknowledged"
      assert html =~ ~s(id="announcement-card-link-100")
      assert html =~ "ml-auto"
    end

    test "F.Announcements.7 — marks an acknowledgement-required announcement as acknowledged by the current user" do
      html =
        render_component(&FoyerComponents.announcement_card/1,
          announcement: announcement(acks: [%AnnouncementAck{user_id: 2}]),
          current_user_id: 2
        )

      assert html =~ ~s(data-ack-state="acked")
      assert html =~ "Acknowledged"
      refute html =~ "Needs your ack"
    end

    test "F.Announcements.7 — does not mark the author as owing acknowledgement" do
      html =
        render_component(&FoyerComponents.announcement_card/1,
          announcement: announcement(author_id: 2, acks: []),
          current_user_id: 2
        )

      assert html =~ ~s(data-ack-state="not_required")
      refute html =~ "Needs your ack"
    end
  end

  describe "recognition_card/1" do
    test "F.Recognitions.5 / F.Recognitions.10 — renders values, private marker, bonus points, and participants" do
      html =
        render_component(&FoyerComponents.recognition_card/1,
          recognition: %Recognition{
            id: 200,
            sender_id: 1,
            sender: user(1, name: "Maya Okafor", initials: "MO"),
            recipient_id: 2,
            recipient: user(2, name: "Aisha Bello", initials: "AB"),
            body: "Stayed late for 412.",
            values: ["care"],
            public: false,
            bonus_points: 25,
            inserted_at: DateTime.utc_now(:second)
          }
        )

      assert html =~ ~s(id="rec-card-200")
      assert html =~ "Care"
      assert html =~ "Private"
      assert html =~ "+25 pts"
      assert html =~ "Maya Okafor"
      assert html =~ "Aisha Bello"
    end

    test "F.Recognitions.10 — renders View only for sender or recipient" do
      recognition = %Recognition{
        id: 201,
        sender_id: 1,
        sender: user(1, name: "Maya Okafor", initials: "MO"),
        recipient_id: 2,
        recipient: user(2, name: "Aisha Bello", initials: "AB"),
        body: "Stayed late for 412.",
        values: ["care"],
        public: true,
        inserted_at: DateTime.utc_now(:second)
      }

      sender_html =
        render_component(&FoyerComponents.recognition_card/1,
          recognition: recognition,
          current_user_id: 1
        )

      third_party_html =
        render_component(&FoyerComponents.recognition_card/1,
          recognition: recognition,
          current_user_id: 3
        )

      assert sender_html =~ ~s(id="recognition-view-201")
      assert sender_html =~ ~s(href="/recognitions/201")
      refute third_party_html =~ ~s(id="recognition-view-201")
    end
  end

  describe "conversation_row/1" do
    test "F.Chat.8 / F.Chat.9 — renders direct conversation preview and unread state" do
      html =
        render_component(&FoyerComponents.conversation_row/1,
          conversation: direct_conversation(unread?: true),
          current_user_id: 1
        )

      assert html =~ ~s(id="conversation-row-50")
      assert html =~ "Charlotte Voss"
      assert html =~ "Confirmed in 412."
      assert html =~ ~s(id="conversation-unread-50")
    end

    test "F.Chat.10 — renders channel conversation name" do
      html =
        render_component(&FoyerComponents.conversation_row/1,
          conversation: %Conversation{
            id: 60,
            kind: :channel,
            channel: %Channel{name: "Housekeeping"},
            messages: [%Message{body: "Floor reset"}],
            unread?: false,
            unread_count: 0
          },
          current_user_id: 1
        )

      assert html =~ "Housekeeping"
      assert html =~ "Floor reset"
      refute html =~ "conversation-unread-60"
    end
  end

  describe "message_bubble/1" do
    test "renders current-user messages as mine with read state" do
      html =
        render_component(&FoyerComponents.message_bubble/1,
          message:
            %Message{
              id: 1,
              author_id: 1,
              body: "Done.",
              inserted_at: ~U[2026-05-25 08:14:00Z]
            }
            |> Map.put(:read, true),
          current_user_id: 1
        )

      assert html =~ "data-message-mine"
      assert html =~ "justify-end"
      assert html =~ "Done."
      assert html =~ "Read"
    end

    test "renders other-user messages with author name" do
      html =
        render_component(&FoyerComponents.message_bubble/1,
          message: %Message{
            id: 2,
            author_id: 2,
            author: user(2, name: "Charlotte Voss", initials: "CV"),
            body: "Please confirm.",
            inserted_at: ~U[2026-05-25 08:14:00Z]
          },
          current_user_id: 1
        )

      refute html =~ "data-message-mine"
      refute html =~ "justify-end"
      assert html =~ "Charlotte Voss"
      assert html =~ "Please confirm."
    end
  end

  describe "profile_card/1" do
    test "renders profile sections, received recognitions, points, and rewards" do
      html =
        render_component(&FoyerComponents.profile_card/1,
          card: %Foyer.Profile.Card{
            user: user(2, name: "Aisha Bello", initials: "AB"),
            received: [
              %Recognition{
                id: 300,
                sender: user(1, name: "Maya Okafor", initials: "MO"),
                recipient: user(2, name: "Aisha Bello", initials: "AB"),
                body: "Covered the late suite reset.",
                values: ["craft"],
                public: true,
                bonus_points: 0,
                inserted_at: ~U[2026-05-25 08:14:00Z]
              }
            ],
            given: [],
            points: 120,
            on_shift?: true,
            received_this_month: 1,
            points_earned: []
          },
          viewer: :self,
          rewards: [
            %Foyer.Profile.RewardItem{
              icon: "hero-gift",
              title: "Staff dinner",
              description: "Any Tuesday",
              cost: 80
            }
          ]
        )

      assert html =~ "Aisha Bello"
      assert html =~ ~s(id="profile-stats")
      assert html =~ ~s(id="recognitions-received")
      assert html =~ "Covered the late suite reset."
      assert html =~ ~s(id="points")
      assert html =~ "120"
      assert html =~ ~s(id="rewards")
      assert html =~ "Staff dinner"
    end
  end

  describe "colleague_row/1" do
    test "renders on-shift state and action event" do
      html =
        render_component(&FoyerComponents.colleague_row/1,
          user: Map.put(user(3, name: "Hugo Brandt", initials: "HB"), :on_shift, true),
          action: "Message",
          action_event: "open_direct",
          action_value: 3
        )

      assert html =~ ~s(data-colleague-id="3")
      assert html =~ ~s(data-shift="on_shift")
      assert html =~ "Hugo Brandt"
      assert html =~ "On shift"
      assert html =~ ~s(phx-click="open_direct")
      assert html =~ ~s(phx-value-user_id="3")
    end
  end

  describe "format_time/1" do
    test "formats nil and datetime values" do
      assert FoyerComponents.format_time(nil) == ""
      assert FoyerComponents.format_time(~U[2026-05-25 08:04:00Z]) == "08:04"
      assert FoyerComponents.format_time(~U[2026-05-25 18:14:00Z]) == "18:14"
    end
  end

  defp announcement(opts) do
    author_id = Keyword.get(opts, :author_id, 1)
    acks = Keyword.get(opts, :acks, [])
    reads = Keyword.get(opts, :reads, [%AnnouncementRead{user_id: 2}])

    %Announcement{
      id: 100,
      author_id: author_id,
      author: %User{id: author_id, name: "Charlotte Voss", initials: "CV"},
      channel: %Channel{id: 10, name: "All Housekeeping"},
      title: "Suite 412 - Allergy protocol in effect",
      body: "Use the marked cleaning kit before entering.",
      requires_ack: true,
      acks: acks,
      reads: reads
    }
  end

  defp direct_conversation(opts) do
    unread? = Keyword.get(opts, :unread?, false)

    %Conversation{
      id: 50,
      kind: :direct,
      participants: [
        %Participant{user_id: 1, user: user(1)},
        %Participant{user_id: 2, user: user(2, name: "Charlotte Voss", initials: "CV")}
      ],
      messages: [%Message{body: "Confirmed in 412."}],
      unread?: unread?,
      unread_count: if(unread?, do: 1, else: 0)
    }
  end

  defp scope(user, on_shift?) do
    shift =
      if on_shift? do
        %Foyer.Shifts.Shift{user_id: user.id}
      end

    Scope.for_user(user, shift)
  end

  defp user(id, opts \\ []) do
    %User{
      id: id,
      name: Keyword.get(opts, :name, "Maya Okafor"),
      initials: Keyword.get(opts, :initials, "MO"),
      role: Keyword.get(opts, :role, :staff),
      department: "Housekeeping",
      title: "Senior Housekeeper",
      languages: ["EN"],
      points_balance: 0
    }
  end
end
