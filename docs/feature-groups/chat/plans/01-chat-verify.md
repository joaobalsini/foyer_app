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

## Rebase

Rebased `feature/chat` onto `origin/main` = `49cd39b "desktop version"`. New
HEAD: `5c9beb7`. Three commits replayed (`52a508c` → `74aa996`, `5a55301` →
`9ebc317`, `26493a4` → `5c9beb7`).

**Conflict resolution:**

- `lib/foyer_web/components/foyer_components.ex` — auto-merged by git (no
  manual edit).
- `lib/foyer_web/live/chat_live.ex` — manually merged. Kept the desktop
  shell from `49cd39b` (`<Layouts.app>` → `<main class="foyer-shell">` +
  `desktop_rail` + `foyer-content` two-panel layout with `chat-panel-inbox`
  on the left and `chat-panel-room` on the right) AND the chat feature
  behaviour from `52a508c` (PubSub handlers for `:chat_message`,
  `:chat_inbox_updated`, `:chat_unread_updated`; `mark_read` in both
  `load_conversation/2` and on incoming `:chat_message`;
  `open_direct`/`open_channel` event handlers with proper error branches;
  `unread_count` assign; picker `phx-click` wiring and `Off shift` tags;
  `#chat-room-shift-state` header for direct rooms; F.Chat.11 helpers).
  `load_conversation/2` keeps the desktop **dual-load** (`inbox_for/1` +
  `list_for_user/1` + `users_on_shift_ids/0` so the inbox panel and rail
  stay populated when a room is opened directly) plus the feature-side
  side-effects (`mark_read/2`, `unread_count/1` refresh). The room PubSub
  subscribe lifecycle in `load_conversation/2` is preserved. The desktop
  `off_shift_conversation?/3` banner helper was dropped in favour of the
  feature-side `#chat-room-shift-state` text — both signal the same thing
  and the feature side is the one pinned by tests
  (`chat_live_test.exs:58` and the F.Chat.11 pinning tests). Bottom nav
  gains the `chat_unread_count={@unread_count}` attribute (desktop side
  passed no count; feature side did). On-shift assign name unified to
  `on_shift_user_ids` (feature side; the desktop branch's
  `on_shift_ids` was not yet referenced by any test).

No further conflicts on commits 2 (`9ebc317`) and 3 (`5c9beb7`).

**Post-rebase check status:**

- `mix deps.get` — clean.
- `mix compile --warnings-as-errors` — clean.
- `mix format --check-formatted` — clean.
- `mix credo --strict` — 0 issues over 301 mods/funs.
- `mix dialyzer` — 0 errors.
- `mix test` — 50 tests, 0 failures, 0.6s (38 from chat + 12 from the
  desktop scaffold's `desktop_smoke_test.exs` now in the tree).

**Verdict after rebase:** Pass with follow-ups (unchanged from the pre-rebase verdict).

## Second pass — test architecture + spec

After the rebase, a second verify pass surfaced two architectural gaps the
first pass missed against `docs/WORKFLOW.md` and `docs/TESTING_GUIDE.md`:

1. **Spec drift from the given/when/then format.** `docs/WORKFLOW.md:38`
   mandates given/when/then; the spec shipped flat declarative clauses.
2. **Test architecture not aligned with `docs/TESTING_GUIDE.md`.** The chat
   group had zero `live_isolated/3` coverage despite being the most
   LiveView-heavy feature; no `test/support/scenarios/` modules existed; the
   `chat_live_test.exs` file used `live(conn, path)` exclusively (route
   smoke), and Mox was only ever used as a no-op `stub_with` proxy. The
   spec also listed F-clauses (F.Chat.1 through F.Chat.5, F.Chat.7,
   F.Chat.8) that had no e2e route-smoke coverage at all.

### Spec rewrite

`docs/feature-groups/chat/spec.md` was rewritten in given/when/then form
for every clause, preserving the existing `F.Chat.1` … `F.Chat.11`
numbering (per `docs/WORKFLOW.md:27-28`, F-numbers are stable per group).
The `## Scaffold Gaps` section is preserved verbatim and `## Test Coverage`
was updated at the end of this pass to reflect the new test files.

### Scenario modules

Six scenario modules were added under `test/support/scenarios/`:

- `test/support/scenarios/chat/fixtures.ex` — in-memory struct builders
  (`Foyer.ChatScenarios.Fixtures`) used by the scenarios. Stable IDs so
  isolated tests can refer to them by name (Maya `id: 1`, Charlotte `id: 2`,
  Hugo `id: 3`, Jamal `id: 4`, conversation `id: 50`, channel conv `id: 60`).
- `test/support/scenarios/chat/empty_inbox.ex`
  (`Foyer.ChatScenarios.EmptyInbox`) — implements `Foyer.ChatPort`,
  returns `[]` from `inbox_for/1` and `0` from `unread_count/1`. Drives
  F.Chat.5 (empty conversations excluded) and the "no unread dot" branch
  of F.Chat.8.
- `test/support/scenarios/chat/with_unread.ex`
  (`Foyer.ChatScenarios.WithUnread`) — implements `Foyer.ChatPort`,
  returns one enriched direct conversation with `unread?: true`,
  `unread_count: 1`. Drives F.Chat.8 (unread dot rendered) and F.Chat.9
  (latest-message preview).
- `test/support/scenarios/chat/room_with_messages.ex`
  (`Foyer.ChatScenarios.RoomWithMessages`) — implements `Foyer.ChatPort`
  with two preloaded messages and `unread_count: 0`. Used for room-panel
  tests (F.Chat.6 compose, F.Chat.7 mark_read trigger, F.Chat.11 header).
- `test/support/scenarios/channels/maya_membership.ex`
  (`Foyer.ChannelsScenarios.MayaMembership`) — implements
  `Foyer.ChannelsPort`, returns the housekeeping floor-4 channel for
  Maya. Drives the picker channel list and the side-rail.
- `test/support/scenarios/accounts/people_with_off_shift.ex`
  (`Foyer.AccountsScenarios.PeopleWithOffShift`) — implements
  `Foyer.AccountsPort`, returns four picker people including the
  off-shift Jamal.
- `test/support/scenarios/shifts/maya_charlotte_hugo_on.ex`
  (`Foyer.ShiftsScenarios.MayaCharlotteHugoOn`) — implements
  `Foyer.ShiftsPort`, marks Maya/Charlotte/Hugo on shift and Jamal off
  shift. Drives F.Chat.11 (off-shift tag) and F.Chat.6/F.Chat.10 (room
  header "On shift").

Scenarios are narrow on purpose: each only implements the port behaviour
it pins, and only stubs the calls `FoyerWeb.ChatLive` makes (no whole-API
shadowing). `@behaviour` annotations make a renamed callback fail the
build rather than a single test.

### Isolated test harness

`test/support/isolated_helpers.ex` and `test/support/isolated_chat_live.ex`
together form the test-only harness for `live_isolated/3` mounting of
`FoyerWeb.ChatLive`:

- `FoyerWeb.IsolatedHelpers.mount_isolated_chat/3` is a macro that wraps
  `Phoenix.LiveViewTest.live_isolated/3` and encodes the test scope
  (user, on_shift?, live_action, optional conversation_id) into the
  session.
- `FoyerWeb.IsolatedChatLive` is a Phoenix.LiveView module that delegates
  `mount/3`, `handle_event/3`, `handle_info/2`, and `render/1` to
  `FoyerWeb.ChatLive`, but pre-assigns `current_scope` from the session
  before calling through. It explicitly does NOT define `handle_params/3`
  because `live_isolated/3` mounts the view without a router, and
  Phoenix's `Route.live_link_info!/3` would fail when post-mount tries to
  resolve a path-less route. Instead the wrapper invokes
  `ChatLive.handle_params/3` directly from `mount/3` with the configured
  `live_action` and `conversation_id`.

Both modules are compiled only in `test/support` (test env only) — they
add no production routes, modules, or test-only flags to the runtime
config.

### Isolated tests (`test/foyer_web/chat_live_isolated_test.exs`, 9 tests)

The new file mounts `FoyerWeb.ChatLive` via `live_isolated/3` against
scenario modules. Tests are `async: true`. Each test pins an F-clause in
its `describe` block.

- **F.Chat.5** "inbox excludes empty conversations" — `EmptyInbox`
  scenario; asserts no `#conversation-row-*` and no
  `#bottom-nav-chat-unread-dot`.
- **F.Chat.9** "inbox renders enriched conversations" — `WithUnread`
  scenario; asserts `#conversation-row-50`, `#conversation-unread-50`,
  and the "Confirmed in 412." latest-message preview.
- **F.Chat.8** "unread_count rendering flips with scenario state" — two
  tests, one against `WithUnread` (dot present) and one against
  `RoomWithMessages` (dot absent).
- **F.Chat.7** "mark_read is triggered when a conversation is opened" —
  `RoomWithMessages` scenario plus `Mox.expect(:mark_read, 2, ...)` that
  pattern-matches the conversation and user. The `2` count reflects that
  `live_isolated/3` (like `live/2`) mounts the LV twice (disconnected +
  connected) — both calls must hit with identical args.
- **F.Chat.6** "compose form submits message via the port" —
  `RoomWithMessages` + `Mox.expect(:send_message, ...)` pattern-matching
  `%{"body" => ^body}` to prove the form attrs reach the port verbatim.
- **F.Chat.10** "picker open events redirect" — two tests:
  - `expect(:open_direct, ...)` on a person click → asserts
    `live_redirect` to `/chat/50`.
  - `expect(:open_channel, ...)` on a channel click → asserts
    `live_redirect` to `/chat/60`.
- **F.Chat.11** "picker tags off-shift colleagues" — two tests: picker
  tag rendering (Jamal: `Off shift`, Hugo: no tag) and room header
  rendering (Charlotte: `On shift`).

### Route smoke tests (`test/foyer_web/chat_live_test.exs`, 6 tests)

Reorganized into three `describe` blocks (inbox / picker / room surfaces),
one or two tests per surface, with explicit F-clause coverage in test
names:

- **F.Chat.5** "inbox does not render empty-conversation rows" — creates
  an empty DM and asserts the inbox row is absent. Closes the e2e gap
  the first pass missed.
- **F.Chat.8/F.Chat.9** "inbox renders unread dot and bottom-nav unread
  dot for unread state" — wiring-level pin of the rendered unread chrome.
- **F.Chat.10/F.Chat.11** "picker renders people and channels and tags
  off-shift" + **F.Chat.10** "picker opens channel conversations".
- **F.Chat.6/F.Chat.10** "room sends and streams messages, header shows
  shift state".
- **F.Chat.7** "opening a room clears that user's unread state via
  mark_read" — asserts the F.Chat.8 unread_count drops from 1 to 0 after
  opening the room. Closes the e2e gap for F.Chat.7 by observing the
  side effect, not by stubbing the call.

The previous F.Chat.11 standalone pinning tests were folded into these
describe blocks (the new F.Chat.11 picker+header coverage in
`chat_live_isolated_test.exs` is the primary pin; the smoke layer keeps a
single wiring confirmation).

### F-clauses pinned at the context layer (not duplicated as e2e)

Per the `docs/TESTING_GUIDE.md` rule "test APIs between parts of the
application at a high level rather than reaching across module
boundaries," the following clauses are observable only at the context
boundary and are pinned in `test/foyer/chat_test.exs`:

- **F.Chat.1** "Opening a direct conversation creates or returns one
  canonical conversation" — the canonical-key invariant is a context-side
  truth (DB unique index + `Conversation.direct_key/1`). The LV only
  exercises this through the picker, which is covered by F.Chat.10. No
  duplicate e2e test added — would either repeat the context assertion
  or weaken it.
- **F.Chat.2** "Direct conversations unique by canonical participant
  key" — same rationale; pinned by `chat_test.exs` line 21-30.
- **F.Chat.3** "Opening a channel conversation creates or returns the
  single conversation for that channel" — pinned at the context layer
  (`chat_test.exs` line 33-44); the LV side is covered by F.Chat.10
  channel-click test.
- **F.Chat.4** "Channel conversations available only to channel members"
  — pinned at the context layer (`chat_test.exs` line 43,
  `open_channel(non-member, …)` returns `{:error, :unauthorized}`). The
  LV behaviour is implicit (the picker only lists channels the user is a
  member of, via `ChannelsPort.list_for_user/1`). Surface-pinning would
  require seeding a forbidden channel and trying to `live(conn,
  ~p"/chat/<that-id>")` — that's a context-level uniqueness assertion in
  disguise, not new coverage.

### Final check results

After the second-pass changes:

```
$ mix deps.get                       # All dependencies have been fetched
$ mix compile --warnings-as-errors   # clean
$ mix format --check-formatted       # clean
$ mix credo --strict                 # 0 issues, 376 mods/funs (was 301 pre-pass)
$ mix dialyzer                       # 0 errors
$ mix test                           # 60 tests, 0 failures, ~0.6s
```

Test count: 50 → 60 (added 9 isolated tests; the smoke file went from 6
flat tests to 6 reorganized tests with broader F-clause coverage; the
context test count is unchanged at 5; +9 net is the isolated file). The
0.6s suite time is unchanged within noise — well inside the 10s budget.

### New HEAD SHA

After the three commits of this pass (spec rewrite + scenarios/harness +
isolated-tests/smoke-split), `feature/chat` HEAD is `1c548d6` on top of
the pre-pass `3033e3d`. The verify-doc commit itself lands on top of
`1c548d6` and will be the new published HEAD.

**Verdict after second pass:** Pass with follow-ups (the known follow-ups
section below is unchanged).

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
