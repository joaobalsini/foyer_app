# Chat Feature Spec

## Clauses

- F.Chat.1 Opening a direct conversation creates or returns one two-person conversation.
- F.Chat.2 Direct conversations are unique by canonical participant key and cannot contain more than two people.
- F.Chat.3 Opening a channel conversation creates or returns the single conversation for that channel.
- F.Chat.4 Channel conversations are available only to channel members.
- F.Chat.5 Empty conversations are excluded from inbox results until the first message is sent.
- F.Chat.6 Sending a message verifies conversation membership, inserts the message, updates `last_message_at`, marks the sender read, and publishes live updates.
- F.Chat.7 `mark_read/2` idempotently records reads for all current messages visible to the user.
- F.Chat.8 `unread_count/1` counts messages visible to the user that were authored by someone else and have no read row for the user.
- F.Chat.9 `inbox_for/1` returns conversations enriched with latest message and unread state.
- F.Chat.10 Live rooms receive new messages through PubSub without a full page reload.
- F.Chat.11 The picker and room header indicate off-shift colleagues.

## Scaffold Gaps

- Implemented in `feature/chat`: direct/channel open helpers, read receipts, unread counts, message sending, inbox enrichment, PubSub room/inbox updates, picker actions, read marking, unread dot rendering, and off-shift indicators.
- Remaining product follow-ups: inbox timestamp display and richer desktop chat layouts.

## Test Coverage

- `test/foyer/chat_test.exs` covers F.Chat.1 through F.Chat.9 at the context boundary.
- `test/foyer_web/chat_live_test.exs` covers picker actions, room streaming, unread dot rendering, and off-shift indicators for F.Chat.6, F.Chat.9, F.Chat.10, and F.Chat.11.
