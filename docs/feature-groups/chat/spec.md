# Chat Feature Spec

## Clauses

### F.Chat.1

- **Given** a user opens a direct conversation with another user
- **When** no canonical two-person conversation exists yet for the pair
- **Then** a single direct conversation is created with both users as
  participants and returned as `{:ok, conversation}`
- **And when** the same pair opens a direct conversation again (in either
  order)
- **Then** the existing conversation is returned without creating a duplicate

### F.Chat.2

- **Given** a request to open a direct conversation
- **When** the same user appears on both sides of the pair
- **Then** the call returns `{:error, :invalid_direct}` and no conversation is
  created
- **And given** any direct conversation in the system
- **When** uniqueness is enforced at the database level
- **Then** there is at most one row per canonical participant key (`min_uid-max_uid`)
  and the row holds exactly two participants

### F.Chat.3

- **Given** a channel member opens a channel conversation
- **When** no conversation row exists for that channel yet
- **Then** the single channel conversation is created and returned
- **And when** any other channel member opens the same channel afterward
- **Then** the same conversation row is returned (one conversation per channel)

### F.Chat.4

- **Given** a user who is not a member of a channel
- **When** they attempt to open the channel conversation
- **Then** the call returns `{:error, :unauthorized}` and no membership-bypass
  is possible through `get_conversation!/2` either

### F.Chat.5

- **Given** a direct conversation that has just been opened
- **When** no message has been sent in it yet (`last_message_at` is nil)
- **Then** the conversation is excluded from `inbox_for/1` results for either
  participant until the first message is sent

### F.Chat.6

- **Given** a user who is a participant or channel member of a conversation
- **When** they send a message with a valid body
- **Then** the message is persisted, `last_message_at` is updated, a read
  receipt is recorded for the sender, and `:chat_message` is broadcast on
  `chat:room:<id>` and `:chat_inbox_updated` on `chat:inbox:<recipient_id>`
- **And given** a user who is neither participant nor channel member
- **When** they attempt to send a message in that conversation
- **Then** the call returns `{:error, :unauthorized}` and nothing is
  persisted or broadcast

### F.Chat.7

- **Given** a user with visibility into a conversation
- **When** `mark_read/2` is called
- **Then** a read row is recorded for every current message in the
  conversation (idempotently — the unique index on `(message_id, user_id)`
  makes repeat calls return `{:ok, 0}`)
- **And given** a user without visibility
- **When** `mark_read/2` is called
- **Then** the call returns `{:error, :unauthorized}`

### F.Chat.8

- **Given** a user with one or more conversations they can see
- **When** `unread_count/1` is called for that user
- **Then** the count includes only messages authored by someone else that
  have no read row for the user, scoped to conversations the user is a
  participant or channel member of

### F.Chat.9

- **Given** a user with conversations that contain messages
- **When** `inbox_for/1` is called
- **Then** each returned conversation carries the latest message preloaded
  under `messages: [latest]`, a virtual `unread?` boolean, and a virtual
  `unread_count`, sorted by `last_message_at` descending

### F.Chat.10

- **Given** a user is viewing a chat room (LiveView mounted, subscribed to
  `chat:room:<id>`)
- **When** another participant sends a new message in that conversation
- **Then** the message is appended to the room stream without a full page
  reload, and the sender's `:chat_inbox_updated` broadcast refreshes the
  receiver's inbox panel
- **And given** the picker is open
- **When** the user clicks a person or channel button
- **Then** the LiveView opens or creates the underlying conversation and
  redirects to `/chat/:conversation_id`

### F.Chat.11

- **Given** a list of colleagues rendered in the chat picker
- **When** the colleague is not currently on shift
- **Then** an `Off shift` tag is rendered alongside their name
- **And given** a direct conversation is open in the room panel
- **When** the room header renders
- **Then** the other participant's shift state is shown in
  `#chat-room-shift-state` (channel conversations do not render this header
  because the audience is many users)

## Test Coverage

- `test/foyer/chat_test.exs` — context-boundary coverage for F.Chat.1 through
  F.Chat.9, including canonical direct conversations, channel authorization,
  inbox enrichment, sending, read receipts, unread counts, and read idempotence.
- `test/foyer_web/chat_live_test.exs` — focused isolated LiveView coverage
  using `live_isolated/3` against scenario modules: F.Chat.5 (empty
  conversations absent from rendered inbox), F.Chat.6 (compose form fires
  `send_message`), F.Chat.7 (`mark_read` triggered on conversation open),
  F.Chat.8 (unread count rendering flips with scenario state), F.Chat.9
  (latest preview and unread dot rendering), F.Chat.10 (incoming room message
  stream append plus open-direct / open-channel picker redirects), and
  F.Chat.11 (picker off-shift tag and room header shift state).
- `test/foyer_web/smoke_test.exs` — route wiring only for `/chat`,
  `/chat/new`, `/chat/:conversation_id`, and the channel deep-link entrypoint
  used by the desktop rail.
- Scenario modules live at `test/support/scenarios/chat/`,
  `test/support/scenarios/channels/`, `test/support/scenarios/accounts/`,
  and `test/support/scenarios/shifts/` and implement the corresponding port
  behaviours.
