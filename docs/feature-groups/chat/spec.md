# Chat — spec

Chat is Foyer's staff messaging surface. It carries two conversation kinds — direct messages between
two people and channel conversations scoped to a Foyer channel (e.g. `Housekeeping · Floor 4`) — under
a single inbox, a single room view, and a single picker for starting a new conversation. The context
boundary (`Foyer.Chat`) enforces canonical uniqueness (one direct row per pair, one row per channel),
membership checks on every read and write, and a read-receipt model where unread state is derived from
the absence of a `chat_message_reads` row. The LiveView surface (`FoyerWeb.ChatLive`) renders the
inbox, the room, and the picker, subscribes to `chat:room:<id>` while a room is open and to
`chat:inbox:<user_id>` for global unread state, and uses `live_isolated`-friendly ports
(`FoyerWeb.LiveDeps.chat/0` etc.) so its tests can swap in scenario modules.

## Scope

**In scope**

- Direct conversations between two distinct users with a canonical `min_uid-max_uid` direct key so a
  pair never accumulates duplicate rows.
- Channel conversations: one conversation per `Foyer.Channels.Channel`, opened only by members of that
  channel.
- Inbox: list conversations the user can see, enriched with the latest message preview, virtual
  `unread?` flag, and virtual `unread_count`, ordered by `last_message_at` desc, excluding
  conversations with no messages yet.
- Room view: ordered message list, compose form, PubSub-driven append of incoming messages without a
  full page reload.
- Read receipts: per-`(message_id, user_id)` uniqueness, `mark_read/2` idempotent over repeat calls,
  membership-gated.
- Global unread count per user, used by the bottom-nav and desktop-rail unread dots.
- Picker (`/chat/new`): people tab with off-shift tagging, channels tab listing the user's
  memberships with real member counts, click-to-open routing to `/chat/:conversation_id`.
- PubSub broadcasts: `:chat_message` on `chat:room:<conversation_id>` for new messages and
  `:chat_inbox_updated` on `chat:inbox:<recipient_id>` for inbox refresh.
- Direct room header showing the other participant's shift state; channel conversations omit this
  header because the audience is many users.

**Out of scope**

- Attachments, reactions, threads, typing indicators, message editing or deletion.
- Group direct messages (>2 participants); group communication happens in channel conversations.
- Channel admin (create, rename, archive, membership management) — owned by the Channels group.
- Push notifications and notification preference settings.
- Search across messages.
- Cross-property routing — chat is single-property in v1.

---

## Clauses

### F.Chat.1 — Direct conversation is canonical per pair

**Given** a user opens a direct conversation with another user.

**When** no canonical two-person conversation exists yet for the pair.

**Then** a single direct conversation is created with both users as participants and returned as
`{:ok, conversation}`.

**And when** the same pair opens a direct conversation again (in either order).

**Then** the existing conversation is returned without creating a duplicate.

### F.Chat.2 — Self-direct rejected and database enforces uniqueness

**Given** a request to open a direct conversation.

**When** the same user appears on both sides of the pair.

**Then** the call returns `{:error, :invalid_direct}` and no conversation is created.

**And given** any direct conversation in the system, **when** uniqueness is enforced at the database
level, **then** there is at most one row per canonical participant key (`min_uid-max_uid`) and the row
holds exactly two participants.

### F.Chat.3 — Channel conversation is unique per channel

**Given** a channel member opens a channel conversation.

**When** no conversation row exists for that channel yet.

**Then** the single channel conversation is created and returned.

**And when** any other channel member opens the same channel afterward.

**Then** the same conversation row is returned (one conversation per channel).

### F.Chat.4 — Channel membership gates open and get

**Given** a user who is not a member of a channel.

**When** they attempt to open the channel conversation.

**Then** the call returns `{:error, :unauthorized}` and no membership-bypass is possible through
`get_conversation!/2` either.

### F.Chat.5 — Empty conversations are excluded from inbox

**Given** a direct conversation that has just been opened.

**When** no message has been sent in it yet (`last_message_at` is nil).

**Then** the conversation is excluded from `inbox_for/1` results for either participant until the
first message is sent.

### F.Chat.6 — Send message persists, broadcasts, and gates on membership

**Given** a user who is a participant or channel member of a conversation.

**When** they send a message with a valid body.

**Then** the message is persisted, `last_message_at` is updated, a read receipt is recorded for the
sender, and `:chat_message` is broadcast on `chat:room:<id>` and `:chat_inbox_updated` on
`chat:inbox:<recipient_id>`.

**And given** a user who is neither participant nor channel member, **when** they attempt to send a
message in that conversation, **then** the call returns `{:error, :unauthorized}` and nothing is
persisted or broadcast.

### F.Chat.7 — mark_read is idempotent and membership-gated

**Given** a user with visibility into a conversation.

**When** `mark_read/2` is called.

**Then** a read row is recorded for every current message in the conversation (idempotently — the
unique index on `(message_id, user_id)` makes repeat calls return `{:ok, 0}`).

**And given** a user without visibility, **when** `mark_read/2` is called, **then** the call returns
`{:error, :unauthorized}`.

### F.Chat.8 — Unread count excludes own messages and respects visibility

**Given** a user with one or more conversations they can see.

**When** `unread_count/1` is called for that user.

**Then** the count includes only messages authored by someone else that have no read row for the
user, scoped to conversations the user is a participant or channel member of.

### F.Chat.9 — Inbox enrichment shape

**Given** a user with conversations that contain messages.

**When** `inbox_for/1` is called.

**Then** each returned conversation carries the latest message preloaded under `messages: [latest]`,
a virtual `unread?` boolean, and a virtual `unread_count`, sorted by `last_message_at` descending.

### F.Chat.10 — Room PubSub append and picker open events

**Given** a user is viewing a chat room (LiveView mounted, subscribed to `chat:room:<id>`).

**When** another participant sends a new message in that conversation.

**Then** the message is appended to the room stream without a full page reload, and the sender's
`:chat_inbox_updated` broadcast refreshes the receiver's inbox panel.

**And given** the picker is open, **when** the channel tab renders, **then** each channel row shows
the real member count from `Channels.list_all_with_member_counts/0`, not a hard-coded zero.

**And when** the user clicks a person or channel button, **then** the LiveView opens or creates the
underlying conversation and redirects to `/chat/:conversation_id`.

### F.Chat.11 — Off-shift tags in picker and room header

**Given** a list of colleagues rendered in the chat picker.

**When** the colleague is not currently on shift.

**Then** an `Off shift` tag is rendered alongside their name.

**And given** a direct conversation is open in the room panel, **when** the room header renders,
**then** the other participant's shift state is shown in `#chat-room-shift-state` (channel
conversations do not render this header because the audience is many users).
