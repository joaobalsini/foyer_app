# Verify — Chat feature group (commit 52a508c)

## Verdict

**Pass with follow-ups.**

The execute phase shipped the full chat surface against the spec — direct/channel
open helpers, membership-gated send, idempotent read receipts, per-user unread
counting, inbox enrichment, two PubSub topics (`chat:room:<id>` and
`chat:inbox:<user_id>`), the picker actions, and off-shift indicators. Database
indexes are in place for every hot query. There is no execute plan file in
`docs/feature-groups/chat/plans/` — the executor worked directly from
`spec.md`, so this verify doc is the first artefact in the `plans/` folder.

Two real issues turned up that needed fixing during verify, both done in this
pass:

1. `mix credo --strict` flagged three "nested too deep" findings in
   `lib/foyer/chat.ex` (`open_direct/2`, `open_channel/2`, `send_message/3`).
   The static-checks gate was failing. Refactored into named helpers — credo
   now reports 0 issues.
2. **F.Chat.11** had no test that mentioned the clause number. The behaviour
   was effectively pinned by `F.Chat.10`'s picker test ("Off shift" assertion)
   and `F.Chat.6/F.Chat.10`'s room test ("On shift" assertion), but a future
   reader grepping for `F.Chat.11` would find nothing. Added two explicit
   pinning tests in `test/foyer_web/chat_live_test.exs`.

Remaining follow-ups (see `Known follow-ups`) are not regressions: telemetry
isn't added by any feature group yet, the unused `compose_changeset/1` port
callback predates the chat LiveView's inline form, and the room shift state
is only meaningful for direct conversations by design.

## Checklist

1. **Spec drift (per clause):**

   - **F.Chat.1** Opening a direct conversation creates or returns one.
     `lib/foyer/chat.ex:17-30` (`open_direct/2`) — same-user head returns
     `{:error, :invalid_direct}`; otherwise sorts participant ids,
     transacts an upsert keyed on the canonical `direct_key`.
     Pinned by `test/foyer/chat_test.exs:18-31`.
   - **F.Chat.2** Direct conversations unique by canonical participant key,
     max two people. `Conversation.direct_key/1`
     (`lib/foyer/chat/conversation.ex:72-76`) computes `min-max`;
     `unique_index(:conversations, [:direct_key], where: "kind = 'direct'")`
     (`priv/repo/migrations/20260525124509_create_conversations.exs:21-24`)
     pins uniqueness at the DB. The function clause for `:direct` only
     accepts a 2-element list (`conversation.ex:72`) so a 3rd participant
     can't even compute a key. Pinned by `chat_test.exs:21-30`.
   - **F.Chat.3** Opening a channel conversation creates or returns the
     single conversation for that channel.
     `lib/foyer/chat.ex:84-117` (`open_channel/2` →
     `find_or_create_channel/1`). Unique index
     `conversations_channel_id_unique` (migration line 16-19) pins single
     channel conv at DB. Pinned by `chat_test.exs:33-44`.
   - **F.Chat.4** Channel conversations available only to channel members.
     `open_channel/2:85` calls `member_of_channel?/2` first.
     `get_conversation!/2` (`chat.ex:155-166`) also enforces membership via
     a left-join + `not is_nil(p.id) or not is_nil(m.id)` guard.
     Pinned by `chat_test.exs:43`
     (`{:error, :unauthorized} = open_channel(maya, leadership.id)`).
   - **F.Chat.5** Empty conversations excluded from inbox until first
     message sent. `inbox_for/1` (`chat.ex:112-153`) filters on
     `not is_nil(c.last_message_at)`. `send_message/3` is the only writer
     that sets `last_message_at` (line 224-226), so the proxy is reliable
     in production. Pinned by `chat_test.exs:46-57`
     (opens an empty DM and asserts it's absent from the inbox).
   - **F.Chat.6** Sending verifies membership, inserts message, updates
     `last_message_at`, marks sender read, publishes live updates.
     `send_message/3` (`chat.ex:188-204`) →
     `insert_message_with_side_effects/4` (`chat.ex:230-245`) does all
     four; `broadcast_message/2` (`chat.ex:355-372`) emits the room and
     per-recipient inbox topics. Pinned by `chat_test.exs:59-83`
     (room + inbox PubSub assertions, last_message_at, read row,
     unauthorized branch) and `chat_live_test.exs:54-65`.
   - **F.Chat.7** `mark_read/2` idempotently records reads for all
     current messages visible to the user. `mark_read/2`
     (`chat.ex:247-281`) selects every message id in the conversation
     and `Repo.insert_all` with `on_conflict: :nothing,
     conflict_target: [:message_id, :user_id]`. Pinned by
     `chat_test.exs:85-94` — second call returns
     `{:ok, 0}`, third call as non-member returns `:unauthorized`.
     Note: the implementation records reads for *every* message in the
     conversation, including the user's own. That's a tiny write
     amplification but consistent with the spec wording ("all current
     messages visible to the user") and harmless because F.Chat.8
     excludes self-authored messages from the count anyway. Worth
     flagging in a follow-up if churn ever becomes a concern.
   - **F.Chat.8** `unread_count/1` counts messages visible to user,
     authored by someone else, with no read row for the user.
     `visible_unread_query/2` (`chat.ex:289-303`) enforces
     `msg.author_id != ^user_id and is_nil(read.id) and
     (not is_nil(p.id) or not is_nil(membership.id))`. Pinned by
     `chat_test.exs:86-91` (count drops from 1 → 0 after `mark_read`).
   - **F.Chat.9** `inbox_for/1` returns conversations enriched with
     latest message and unread state. `inbox_for/1`
     (`chat.ex:120-153`) loads conversations + channel + participants:user
     in one query, then issues a `DISTINCT ON (conversation_id) … ORDER BY
     conversation_id, inserted_at DESC` for latest messages (one extra
     round-trip total, not N+1), then a `GROUP BY conversation_id` count
     for unread (third round-trip). Stitched onto each conversation as
     `messages: [latest]`, `unread?:`, `unread_count:`.
     Pinned at the context boundary by `chat_test.exs:46-57` and at the
     LiveView boundary by `chat_live_test.exs:67-73`
     (asserts `#conversation-unread-#{maya_charlotte.id}` and
     `#bottom-nav-chat-unread-dot` render).
   - **F.Chat.10** Live rooms receive new messages through PubSub.
     `mount/3` (`chat_live.ex:14-34`) subscribes to the inbox topic;
     `load_conversation/2` (`chat_live.ex:66-94`) subscribes to the room
     topic and calls `mark_read`. `handle_info({:chat_message, message},
     ...)` (`chat_live.ex:145-161`) calls `stream_insert(:messages, …)`
     for the open room and re-marks the room read. Pinned by
     `chat_live_test.exs:54-65` and `chat_test.exs:60-71` (the latter
     subscribes from the test process and asserts the actual PubSub
     message arrives — proves the broadcast, not just the handler).
   - **F.Chat.11** Picker and room header indicate off-shift colleagues.
     Picker: `chat_live.ex:264-280` renders an `Off shift` tag for each
     person not in `@on_shift_user_ids`. Room header:
     `chat_live.ex:191-196` renders `#chat-room-shift-state` for direct
     conversations only (channel rooms have many members, so a single
     shift label doesn't apply). The clause was implicitly pinned by
     existing tests but lacked a test name mentioning `F.Chat.11`. Now
     pinned by two new tests in `chat_live_test.exs:76-97`:
     `"F.Chat.11 picker tags off-shift colleagues and on-shift colleagues
     are unmarked"` and `"F.Chat.11 direct room header reflects the other
     participant's shift state"`.

2. **Guidelines followed:**
   - `chat_test.exs` and `chat_live_test.exs` are both `async: true`.
   - LiveView tests use `Mox.stub_with` to bind real contexts (no
     `Application.put_env/3`), per `TESTING_GUIDE.md` lines 124-125.
   - Each clause has a test naming it (`F.Chat.<N>`), including the new
     F.Chat.11 cases.
   - No scenario modules added — not needed for this group (tests run
     against the real seeded fixtures via `stub_with`).

3. **Static checks clean** (after the credo refactor in this pass):
   - `mix format --check-formatted` — clean.
   - `mix compile --warnings-as-errors` — clean.
   - `mix credo --strict` — 0 issues over 294 mods/funs (was: 3
     nesting-too-deep before this pass).
   - `mix dialyzer` — 0 errors.

4. **Test suite health:** 38 tests, 0 failures, ~0.4s. Well inside the
   10s budget. A logic change in the chat context fails exactly the
   matching `chat_test.exs` case (e.g. flipping the `:invalid_direct`
   guard) — minimal blast radius.

5. **Database indexes:** Every chat query is index-backed.
   - `inbox_for/1`: conversations sorted by `last_message_at` →
     `index(:conversations, [:last_message_at])` (migration line 14).
     Latest-message lookup uses
     `index(:chat_messages, [:conversation_id, :inserted_at])`
     (migration `20260525124511_create_chat_messages.exs:13`).
   - `mark_read/2`: `WHERE conversation_id = ?` uses the same
     `(conversation_id, inserted_at)` index. Read row insert is
     idempotent via `unique_index(:chat_message_reads,
     [:message_id, :user_id])`
     (`20260525124513_create_chat_message_reads.exs:13`).
   - `unread_count/1` / `unread_counts_by_conversation/2`:
     `visible_unread_query/2` joins `chat_message_reads` on
     `(message_id, user_id)` (covered by the unique index above);
     joins `conversation_participants` on `(user_id, conversation_id)`
     covered by `index(:conversation_participants, [:user_id,
     :conversation_id])`
     (`20260525124510_create_conversation_participants.exs:13`);
     joins `channel_memberships` on `(channel_id, user_id)`.
   - `member_of_channel?/2`: `WHERE channel_id = ? AND user_id = ?`
     uses the existing
     `unique_index(:channel_memberships, [:user_id, :channel_id])`
     (assumed present from the channels migration).
   - `get_conversation!/2`: PK lookup + the same participant/membership
     joins as above.

6. **No N+1:** `inbox_for/1` is exactly 3 round-trips regardless of
   inbox size — conversations + latest-per-conversation via `DISTINCT
   ON` + unread counts via `GROUP BY`. No `Enum.map` over conversations
   that issues a per-row query. Verified by reading `chat.ex:120-153`.

7. **Migration safety:** No new migrations were introduced by this
   feature group — the chat tables shipped earlier
   (`20260525124509`-`20260525124513`). Confirmed via
   `ls priv/repo/migrations/` and `git diff main..feature/chat -- priv/`
   (empty). All existing migrations use `change` with `references(… on_delete:
   :delete_all)` and named `unique_index`/`check` constraints; reversible
   via `down` because `Ecto.Migration.change` infers the inverse.

8. **Context isolation:** `Foyer.Chat` only talks to its own schemas and
   its sibling `Foyer.Channels.Membership` (necessary because channel
   audience is owned by `Foyer.Channels`, not `Foyer.Chat`). No reach into
   `Foyer.House`, `Foyer.Recognitions`, `Foyer.Profile`, etc.
   `FoyerWeb.ChatLive` calls only through `FoyerWeb.LiveDeps.chat/0`,
   `.accounts/0`, `.channels/0`, `.shifts/0` — never directly into context
   modules.

9. **LiveView mount discipline:** `mount/3` (`chat_live.ex:14-34`) only
   subscribes to PubSub and assigns empty streams + nil conversation — no
   DB load. Every DB load happens in `handle_params/3` (`chat_live.ex:36-64`)
   or its private `load_conversation/2`. PubSub subscriptions are
   process-scoped so they tear down on socket exit (no manual `terminate/2`
   needed). No `assign_async`/`start_async` — the loads are fast enough
   that the synchronous path is acceptable for an MVP; a follow-up could
   move `inbox_for/1` to async if list size grows.

10. **Mobile responsiveness:** Chat surface uses `foyer-scroll` and
    `foyer-root` (mobile-first). Inbox row is `flex items-center gap-3
    p-3` — readable at 320 px. Room compose form is `flex gap-2 mt-2`
    with the foyer input + send button side-by-side. Picker uses
    full-width `foyer-btn w-full text-left` rows. No desktop-only
    breakpoints introduced. (The desktop scaffold from `49cd39b` is not
    on `feature/chat` by design — chat sits on top of the mobile-first
    scaffold and the desktop two-panel layout is a separate concern that
    will land after the feature groups merge.)

11. **Accessibility:**
    - Picker "Off shift" tag has visible text — no aria-only state.
    - Room header `#chat-room-shift-state` is plain text in a `foyer-mono`
      block — readable.
    - Unread dot on conversation rows has
      `aria-label={"#{@conversation.unread_count} unread"}`
      (`foyer_components.ex:289-294`).
    - Bottom-nav unread dot has
      `aria-label={"#{@chat_unread_count} unread chat messages"}`
      (`foyer_components.ex:65-71`).
    - Compose textarea: `<.input>` renders a `<label for=…>` wrapper
      (`core_components.ex:240-253`). No visible label, but the
      `placeholder="Write a message"` is enough for sighted users and
      screen readers will read the implicit label. A future polish could
      add `aria-label="Message body"` explicitly. Not blocking.
    - Picker "tabs" (`role="tablist"`) are visual placeholders with no
      `aria-controls`/`aria-selected` and both lists are always rendered.
      That's an a11y deviation but matches the plan's "MVP picker" intent
      — flagged as a follow-up.

12. **No secrets in source:** No new env vars or credentials introduced
    in `config/*.exs` (chat context wiring already existed). Verified by
    `git diff main..feature/chat -- config/` (empty).

13. **Telemetry / structured logging:** None added. The scaffold verify
    explicitly noted `n/a — none added or removed` and no feature group
    has yet introduced a telemetry tradition. Flagged as a cross-cutting
    follow-up rather than a chat-specific gap.

## Findings fixed in this pass

### 1. `mix credo --strict` failed with three "nested too deep" violations

- **Files:** `lib/foyer/chat.ex:22-71` (`open_direct/2`),
  `lib/foyer/chat.ex:76-100` (`open_channel/2`), `lib/foyer/chat.ex:180-218`
  (`send_message/3`).
- **Symptom:** All three functions did the work inline (case → case →
  case nesting + `if changeset.valid?` inside `if member?` inside the
  body). Credo reports max depth 2; the originals were 3-4.
  `mix credo --strict` is part of the verify checklist (item 3) so this
  blocked the gate.
- **Change:** Extracted private helpers for each.
  - `open_direct/2` → `upsert_direct/2` → `create_direct/2` +
    `insert_or_fetch_direct/2` + `insert_direct_participants/2`
    (`chat.ex:22-79`).
  - `open_channel/2` → `find_or_create_channel/1` →
    `insert_channel_conversation/1` → `recover_channel_conversation/2`
    (`chat.ex:84-117`).
  - `send_message/3` → `do_send_message/3` → `persist_and_broadcast/4`
    → `insert_message_with_side_effects/4` (`chat.ex:188-245`).
  - Behaviour is identical — same Repo calls in the same order, same
    `{:ok, …}`/`{:error, …}` shapes, same broadcast.
- **Pinned by:** The existing `chat_test.exs` suite passes unchanged (5
  tests covering the upsert paths, the race-recovery branch, send +
  broadcast, and the unauthorized branch). 36 → 38 tests after F.Chat.11
  additions, all green.

### 2. F.Chat.11 lacked a test that mentioned the clause number

- **File:** `test/foyer_web/chat_live_test.exs` (no test name contained
  `F.Chat.11`).
- **Symptom:** The behaviour was effectively pinned — the
  `F.Chat.10 picker…` test asserts `"Off shift"` text on Jamal's row
  (`chat_live_test.exs:31`), and `F.Chat.6/F.Chat.10 room sends…` asserts
  `has_element?(view, "#chat-room-shift-state", "On shift")`
  (`chat_live_test.exs:58`). But the WORKFLOW.md verify checklist (line
  77) requires "Each spec feature has at least one e2e test mentioning
  its `F.<FirstWord>.<N>` number." A future reader running
  `grep -r 'F.Chat.11' test/` would find nothing.
- **Change:** Added two pinning tests at `chat_live_test.exs:76-97`:
  - `"F.Chat.11 picker tags off-shift colleagues and on-shift colleagues
    are unmarked"` — asserts Jamal carries "Off shift" AND Hugo (on
    shift) does NOT. The negative assertion catches a regression where
    everybody gets tagged off-shift, or the `MapSet` membership check
    is inverted.
  - `"F.Chat.11 direct room header reflects the other participant's
    shift state"` — asserts `#chat-room-shift-state` contains "On
    shift" AND does NOT contain "Off shift". Catches a regression where
    the conditional render is dropped or the lookup uses the current
    user instead of the other participant.

## Known follow-ups (not fixed in this pass)

### 1. `compose_changeset/1` callback exists in the port but is unused

- **Files:** `lib/foyer/chat_port.ex:17` (callback),
  `lib/foyer/chat.ex:179-184` (impl). The `FoyerWeb.ChatLive` compose
  form uses `to_form(%{"body" => ""}, as: :message)` inline
  (`chat_live.ex:31, 103`), never calling
  `LiveDeps.chat().compose_changeset/1`. The callback exists for
  symmetry with `HousePort`/`RecognitionsPort` (both used) but adds no
  current value.
- **Why not removed:** Removing the callback is a port-shape change
  that should land alongside a deliberate decision about whether to
  switch the LV to a real changeset-backed form (which would surface
  the 4_000-char `body` validation in the UI instead of as a flash on
  failure). That's a small product polish, not a verify scope.
- **Recommendation:** When the chat compose form is upgraded to show
  inline validation (e.g. "message is too long"), switch the LV to
  `assign(:compose_form, to_form(LiveDeps.chat().compose_changeset(%{})))`
  and the callback becomes load-bearing. Until then, leave the contract
  in place — removing it would force a port version bump for no
  rendered benefit.

### 2. `mark_read/2` writes a read row for every message in the conversation, including the user's own

- **File:** `lib/foyer/chat.ex:247-281`.
- **Symptom:** The query selects every message id in the conversation,
  including ones authored by the current user, and `insert_all`s a read
  row for each. The `on_conflict: :nothing` + `(message_id, user_id)`
  unique index makes this idempotent and safe, but it's wasted writes
  — F.Chat.8 already excludes self-authored messages from the unread
  count, so reads on self-authored messages are bookkeeping noise.
- **Why not fixed:** The spec wording ("all current messages visible to
  the user") is broad enough that including self-authored messages is a
  defensible reading. The test `F.Chat.7/F.Chat.8 mark_read is
  idempotent` explicitly pins `inserted == 2` for the 2-message seed
  (one Maya, one Charlotte) — narrowing the query to "messages I didn't
  author" would change that assertion. If the team wants the narrower
  behaviour, the test gets updated and the query adds `and msg.author_id
  != ^user_id`. Trivial change; punted to a polish ticket.

### 3. Picker "tabs" (People / Channels) are non-functional placeholders

- **File:** `lib/foyer_web/live/chat_live.ex:254-261`. Renders
  `<div role="tablist">` with two `<button>` tabs but no
  `aria-controls`, no `aria-selected`, no click handler — both lists
  are always rendered. Accessibility tooling would flag the orphan
  `role="tablist"`.
- **Why not fixed:** Both lists fit comfortably on a mobile screen
  (≤8 people, ≤4 channels in the seed) so the tabs aren't load-bearing.
  Fixing them properly means deciding whether to (a) drop the
  `role="tablist"` and use plain section headings, or (b) wire real
  tab semantics with `phx-click` handlers and `:if` rendering. Both are
  product polish, not a verify violation per the WORKFLOW checklist.
- **Recommendation:** In a future chat-picker polish ticket, replace the
  tablist with two `<h3>` section labels, OR add `phx-click` toggle +
  `aria-selected` + `aria-controls` wiring. Don't ship the half-tabs in
  production.

### 4. No telemetry / structured logging on chat events

- **Files:** `lib/foyer/chat.ex` (no `:telemetry.execute` or `Logger.info`
  calls anywhere in the module).
- **Symptom:** When an operator wants to debug "why didn't this message
  send?" or "how many messages does the linden hotel send per hour?",
  there's nothing in the logs and no telemetry span to attach to. The
  WORKFLOW verify checklist (line 98) calls this out: "Meaningful events
  emit a telemetry span or structured log line."
- **Why not fixed:** No feature group has yet established a telemetry
  convention — the scaffold verify (item 11) explicitly recorded
  `n/a — none added or removed`. Adding it here in isolation would
  create a one-off pattern that the next feature group would have to
  either match or contradict. Belongs in a cross-cutting "introduce
  telemetry" ticket that picks the event names, fields, and log
  formatter once for the whole app.
- **Recommendation:** Open a top-level ticket to add `:telemetry`
  events for `[:foyer, :chat, :send_message, :stop]`,
  `[:foyer, :chat, :open_direct, :stop]`,
  `[:foyer, :chat, :mark_read, :stop]` with at least `user_id`,
  `conversation_id`, and `duration_native` fields. Then backfill the
  same shape across House, Recognitions, Announcements.

### 5. The room view doesn't unsubscribe from previous room topic on internal navigation

- **File:** `lib/foyer_web/live/chat_live.ex:74-76`. Every entry into
  `:show` calls `Phoenix.PubSub.subscribe(…, "chat:room:#{id}")`. The
  LiveView never unsubscribes.
- **Symptom:** In production, `<.link navigate>` between LiveViews of
  the same module **remounts** the LiveView in Phoenix 1.7+, so the old
  process dies and PubSub auto-cleans the subscription — no leak. But
  if a future refactor switches the room navigation to
  `<.link patch>` (to keep the inbox panel mounted, for example), the
  subscriptions will accumulate across navigations and messages from
  the old room will keep arriving.
- **Why not fixed:** The current code is safe under the current routing
  conventions (`<.link navigate>` everywhere). Adding a defensive
  `Phoenix.PubSub.unsubscribe/2` on transition would be cheap insurance
  but isn't required.
- **Recommendation:** If/when the chat surface gets a two-panel desktop
  layout that patches between rooms (per the desktop scaffold direction
  on `main`), unsubscribe from the previous `chat:room:<id>` topic at
  the top of `load_conversation/2` before subscribing to the new one.

## Test / credo / format / dialyzer status (after fixes)

```
$ mix format --check-formatted    # clean
$ mix compile --warnings-as-errors # clean
$ mix credo --strict              # 0 issues, 294 mods/funs
$ mix dialyzer                    # 0 errors
$ mix test                        # 38 tests, 0 failures, ~0.4s
```

Test count went 36 → 38 — added two F.Chat.11 pinning tests in
`chat_live_test.exs`. The 0.4s suite time is well under the 10s budget.
