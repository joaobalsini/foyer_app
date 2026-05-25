# Review — Plan 01 Today briefing

## Verdict

Block

Today's core v1 behaviour depends on cross-context functions the plan proposes to stub, so executing it would knowingly fail the waiting-count and manager-live-post clauses.

## Strengths

- The plan correctly treats Today as a read-model/orchestrator and keeps shift writes on `Foyer.Shifts`.
- It fixes a real scaffold gap by splitting `waiting_count` into category counts for announcements, messages, and private recognitions.
- It keeps `/today` in the authenticated-but-off-shift-allowed live session and relies on the existing `:ensure_on_shift` gate for the rest of the app.
- It identifies the current DTO and template references to `waiting_count`, which are real scaffold facts.

## Critical Issues

### §4.3 / §9 Stubbed Cousin Helpers Cannot Satisfy Today v1

Bug: `F.Today.1` and `F.Today.16` require accurate off-shift waiting counts. `F.Today.14` requires manager live posts. The plan says `House.authored_by/1`, `House.unacked_since/2`, `Chat.unread_since/2`, `Recognitions.private_received_since/2`, and `Shifts.last_ended_shift_for/1` are owned by other groups, then step 2 adds stub implementations returning zero/empty "for now."

Fix: do not execute Today against stubs for spec-critical behaviour. Either:

```text
1. Move real implementations of the five read helpers into this plan as explicit cross-context deltas, with tests in the owning context files; or
2. Split this plan so only DTO/template work lands now, and block F.Today.1, F.Today.14, and F.Today.16 until House/Chat/Recognitions/Shifts deliver the real helpers.
```

Recommended real ownership: Today may orchestrate cousin reads per scaffold §6.8, but the queries themselves belong in the owning contexts and must be real before Today is verified.

### §5 Shift-Complete Session Key Is Not Feasible From A LiveView Event

Bug: The plan proposes setting a session key like `:just_clocked_out` in `end_shift_submit` and consuming it in `handle_params/3`. A LiveView event handler cannot mutate the Plug session directly. Executing this literally will either be impossible or require introducing a controller workaround not described in the plan.

Fix: use a route or query-param based transient state. Recommended:

```elixir
{:noreply,
 socket
 |> put_flash(:info, "Shift ended. Rest well.")
 |> push_navigate(to: ~p"/today?state=shift_complete")}
```

Then in `handle_params/3`, assign `just_clocked_out: params["state"] == "shift_complete"`. If the state needs a clean URL after first render, use a distinct `live "/today/shift-complete", TodayLive, :complete` route instead.

### §4.3 `Chat.unread_since/2` Lacks A Correct Read Model Definition

Risk: The plan asks Chat for unread message counts, but the current `Foyer.Chat` has no read-marking API and no implemented `MessageRead` flow. Counting "messages sent after since and not yet read" is underspecified: it must exclude the user's own messages, include membership-authorized channel conversations, include direct conversations where the user is a participant, and avoid double-counting conversations/messages.

Fix: define the exact query contract before Today consumes it:

```text
Chat.unread_since(user, since) returns count of chat_messages where:
- message.author_id != user.id
- message.inserted_at > since, or all-time when since is nil
- user is a direct participant OR a member of the channel conversation
- no chat_message_reads row exists for (message_id, user_id)
```

Add required indexes or confirm the existing `chat_messages(conversation_id, inserted_at)`, `chat_message_reads(user_id)`, `conversation_participants(user_id, conversation_id)`, and membership indexes cover the query.

### §5 / Template Links Still Need Route Reconciliation

Contradiction: The plan says the scaffold has `/house/:id`, then says the current route is `/announcements/:id`. The real router currently defines `/announcements/:id`, and TodayLive already links to `~p"/announcements/#{a.id}"`.

Fix: remove the stale `/house/:id` language from the plan and pin `F.Today.5` to the actual route:

```elixir
<.link navigate={~p"/announcements/#{a.id}"} id={"needs-ack-#{a.id}"}>
```

If product wants `/house/:id`, that is a router-wide change and not a Today-only cleanup.

## Spec drift / missing clauses

- The Today spec does not state whether waiting counts should include the user's own chat messages. Add that they should not.
- The spec does not define unread message semantics in v1, even though it requires unread message counts. Add a clause covering `chat_message_reads` and channel/direct authorization.
- The spec says the handoff card fades to background once read, but no read-state schema or clause exists for handoffs. Either remove that sentence from the scope or add a concrete "handoff read" mechanism.
- `F.Today.14` says managers with authored announcements see "Your live posts", but it does not define whether removed/unpublished/old posts are included. The plan should constrain this to published live announcements ordered newest-first.

## Cross-plan concerns

- Today depends on House, Chat, Recognitions, and Shifts read helpers that none of the three reviewed feature plans owns. This is the largest cross-plan risk. The plan must either implement those real helpers as accepted cross-context deltas or wait for their owning groups.
- Channels owns `list_for_user/1`, which Today needs for the end-shift channel picker. That API exists today, but if Channels changes the port signature or moves directory data to streams, Today tests must stub the updated `ChannelsPort`.
- Profile's private-recognition rule affects `Recognitions.private_received_since/2`: Today must count only private recognitions received by the user since last shift, not all received recognitions and not public recognitions already visible in House.

## Nits

- `recent_recognition` is singular in the existing DTO. If the field remains a list, rename to `recent_recognitions` while making the breaking DTO change.
- The plan says the `@behaviour` annotation catches struct-shape drift. Behaviours catch callback shape, not every required field in returned test structs; typed_struct enforcement helps at construction time.
- Mobile overflow cannot be proven by asserting no `overflow-x: scroll` string in HTML. Use Playwright or at least a rendered viewport smoke test if the project has browser-test support.
- Add stable IDs to the new channel picker and "Skip · clock out" control because the spec expects testable end-shift interactions.

## Open questions raised by the original plan

- Cousin-calling trade-off: resolved. Today may orchestrate cousin reads, but the owning contexts must expose real, tested read functions. Today should not own their query internals.
- No PubSub boundary: resolved. Keep no PubSub in v1 and test `F.Today.15` as a non-update/reload behaviour only if the test can do so without brittle timing.
- `waiting_count` single integer vs breakdown: resolved. Use category fields plus `Briefing.waiting_total/1`.
- Shift-complete variant: do not use a session key from LiveView. Recommended route/query-param solution above.
- Delta helpers currently stubs: escalate as blocker. Stubbed counts contradict the Today spec.
- Announcement route discrepancy: resolve to current `/announcements/:id` unless a separate router plan changes it.
