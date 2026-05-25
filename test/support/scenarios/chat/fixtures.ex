defmodule Foyer.ChatScenarios.Fixtures do
  @moduledoc """
  In-memory struct builders for chat scenario modules. No DB. Stable IDs so
  isolated tests can refer to them by name.

  Scenarios construct `%Conversation{}`/`%Message{}`/`%User{}`/`%Channel{}`
  with virtual fields (`unread?`, `unread_count`, preloaded `participants`,
  `messages`, `channel`) populated — exactly the shape the ChatLive renderer
  consumes.
  """

  alias Foyer.Accounts.User
  alias Foyer.Channels.Channel
  alias Foyer.Chat.Conversation
  alias Foyer.Chat.Message
  alias Foyer.Chat.Participant

  @spec maya() :: User.t()
  def maya do
    %User{
      id: 1,
      name: "Maya Okafor",
      initials: "MO",
      role: :staff,
      department: "Housekeeping",
      title: "Senior Housekeeper · Floor 4",
      languages: ["EN", "FR", "YO"],
      points_balance: 245
    }
  end

  @spec charlotte() :: User.t()
  def charlotte do
    %User{
      id: 2,
      name: "Charlotte Voss",
      initials: "CV",
      role: :manager,
      department: "Housekeeping",
      title: "Dir. of Housekeeping",
      languages: ["EN", "FR"],
      points_balance: 0
    }
  end

  @spec hugo() :: User.t()
  def hugo do
    %User{
      id: 3,
      name: "Hugo Brandt",
      initials: "HB",
      role: :staff,
      department: "Engineering",
      title: "Engineering",
      languages: ["EN", "DE"],
      points_balance: 100
    }
  end

  @spec jamal() :: User.t()
  def jamal do
    %User{
      id: 4,
      name: "Jamal Mensah",
      initials: "JM",
      role: :staff,
      department: "Housekeeping",
      title: "Housekeeper · Fl. 2",
      languages: ["EN", "TL"],
      points_balance: 0
    }
  end

  @spec floor_4() :: Channel.t()
  def floor_4 do
    %Channel{
      id: 10,
      name: "Housekeeping · Floor 4",
      slug: "housekeeping-floor-4",
      kind: :department
    }
  end

  @spec leadership() :: Channel.t()
  def leadership do
    %Channel{
      id: 11,
      name: "Leadership",
      slug: "leadership",
      kind: :department
    }
  end

  @spec direct_maya_charlotte(keyword()) :: Conversation.t()
  def direct_maya_charlotte(opts \\ []) do
    unread? = Keyword.get(opts, :unread?, true)
    unread_count = Keyword.get(opts, :unread_count, 1)
    latest_body = Keyword.get(opts, :latest_body, "Confirmed in 412.")
    last_message_at = Keyword.get(opts, :last_message_at, ~U[2026-05-25 08:14:00Z])

    latest =
      %Message{
        id: 100,
        conversation_id: 50,
        author_id: charlotte().id,
        author: charlotte(),
        body: latest_body,
        inserted_at: last_message_at
      }

    %Conversation{
      id: 50,
      kind: :direct,
      direct_key: Conversation.direct_key([maya().id, charlotte().id]),
      last_message_at: last_message_at,
      participants: [
        %Participant{id: 200, conversation_id: 50, user_id: maya().id, user: maya()},
        %Participant{
          id: 201,
          conversation_id: 50,
          user_id: charlotte().id,
          user: charlotte()
        }
      ],
      messages: [latest],
      unread?: unread?,
      unread_count: unread_count
    }
  end

  @spec channel_floor_4(keyword()) :: Conversation.t()
  def channel_floor_4(opts \\ []) do
    unread? = Keyword.get(opts, :unread?, false)
    unread_count = Keyword.get(opts, :unread_count, 0)
    last_message_at = Keyword.get(opts, :last_message_at, ~U[2026-05-25 08:02:00Z])

    %Conversation{
      id: 60,
      kind: :channel,
      channel_id: floor_4().id,
      channel: floor_4(),
      last_message_at: last_message_at,
      participants: [],
      messages: [
        %Message{
          id: 110,
          conversation_id: 60,
          author_id: charlotte().id,
          author: charlotte(),
          body: "Floor 4 standby checklist updated.",
          inserted_at: last_message_at
        }
      ],
      unread?: unread?,
      unread_count: unread_count
    }
  end

  @spec direct_message(integer(), integer(), integer(), String.t()) :: Message.t()
  def direct_message(id, conversation_id, author_id, body) do
    author =
      case author_id do
        1 -> maya()
        2 -> charlotte()
        3 -> hugo()
        4 -> jamal()
      end

    %Message{
      id: id,
      conversation_id: conversation_id,
      author_id: author_id,
      author: author,
      body: body,
      inserted_at: ~U[2026-05-25 08:14:00Z]
    }
  end
end
