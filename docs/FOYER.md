# Foyer

The Foyer is the room where the staff gather before service. It's where the day begins and ends. It's a staff
communications platform for luxury hotel groups.

Hotels run on conversation: the night manager handing off to the day shift, the housekeeper flagging a VIP arrival,
the chef briefing Food & Beverage before service, the quiet shout-out for someone who went above and beyond. Today
most of that lives in a patchwork of WhatsApp threads, paper logs, group emails, and corkboard notes. Things get
missed. Nobody knows if the allergy protocol was actually read before turndown.

Foyer puts the back-of-house under one roof.

## POC covers three surfaces across one product

Today — a brief morning briefing on every staff member's phone. It starts with the handoff from the previous shift,
then shows anything that needs acknowledgement and recent recognition relevant to the user. Short by design — once
you've read the handoff and acked what you owe, Today gets shorter and quieter through the day.

The House — the property feed. Announcements from managers (pinned to the top, audience-targeted, with required
acknowledgements when it matters); recognition cards for colleagues going above and beyond. Filterable by type and
time, so a new starter can scroll back to March and feel the texture of the place.

Chat — direct messages and department channels that replace the fragmented threads. Live messages, read receipts,
unread indicators, and off-shift colleagues marked clearly so urgent notes can wait until they clock in.

## High level view

Managers compose announcements with audience targeting, pin them for visibility, and track basic read and
acknowledgement receipts on the announcement detail page. Recognition with optional bonus points gives managers a way
to make good work visible and begin tying appreciation to a staff rewards program.

Respect for the worker is a core idea. Staff explicitly clock in. Off-shift, notifications quiet — messages and
announcements wait until the next shift starts. Foyer doesn't pretend to know anyone's schedule and doesn't trespass
on rest time. Shifts end with a gentle prompt to leave a handoff note for whoever comes next.

As a respect to employees and managers, people who are not working should not be expected to participate in the house.
Off-shift boundaries are part of the product, not just notification preferences.

The application is role-aware but not role-segregated. Different roles share the same app and same visual language.
Line staff and managers see the same surfaces, but managers just have additional capabilities: compose announcements,
see receipts, attach bonus points to recognitions. The product respects everyone with the same care.

Foyer is built for properties where guests pay for craft. The design style and colors reflect that: warm cream and
forest green and a quiet brass accent. It looks like the house, not the help desk.

## Main functionality

### Announcements

Announcements are manager-authored posts with optional acknowledgement requirements. They can be pinned for visibility
and later unpinned by any manager.

Managers can target only channels they belong to. Acknowledgement recipients are based on the selected channel, but
the announcement author is excluded. A manager who posts an announcement should not be required to acknowledge their
own message.

Announcement detail pages include the operational receipt view: acknowledged, read without acknowledgement, unread,
and off-shift status. This is the answer to the original hotel problem: not just “we sent the allergy protocol,” but
“we know who has actually confirmed it.”

Opening an announcement records a read for the current viewer. For acknowledgement-required posts, the recipient sees
a clear acknowledgement action; once acknowledged, the post no longer asks that user to confirm it.

### Recognitions

Recognitions are lightweight and visible. A staff member can send a shout-out to a colleague, optionally with points
when their role allows it. Recognitions appear in The House and land with the recipient directly.

Recognition is not only a feed item; it becomes part of someone’s standing in the house.

Recognitions can carry house values such as craft, care, warmth, discretion, initiative, and excellence. Those values
make recognition feel specific to the property rather than generic praise.

### Conversation Access

Conversation access is membership-scoped. Users only see direct messages and channels they belong to. Managers do not
get a hidden override into every channel; if a manager should participate in a channel, they should be a member of
that channel.

Foyer supports direct messages and department channels. Off-shift users are visibly marked so the sender understands
that a reply may wait.

### Shift Boundaries

Foyer depends on explicit shift state. Staff start and end shifts in the app. Ending a shift can include a handoff
note; starting a shift brings the relevant handoff forward.

The product does not assume a perfect scheduling system. It treats shift state as something the worker controls.
Off-shift means quieter notifications and clearer expectations for colleagues trying to reach them.

When a user is off shift, they should only see Today. They can review what is waiting, start their shift, and then
enter the rest of the product. This boundary is permanent to the app: Foyer does not ask employees or managers to read
the feed, answer messages, or manage announcements while they are not working.

### Channels

Channels are the operational rooms of the property. They usually map to departments or recurring service contexts:
Housekeeping, Front Office, Food & Beverage, Maintenance, Spa, Leadership.

Channels define who receives the work. A channel can be associated with announcements, chat conversations, and
handoffs. Membership matters: if someone should see or participate in a channel, they should be a member of that
channel.

Managers are not outside the model. They can be members of channels like everyone else.

## Areas

### Today

Today is the staff member’s starting point. It should answer one question: “What do I need to know before I begin?”

The first item is the handoff from the previous shift. If the previous shift left notes, they appear before anything
else, because operational continuity matters more than feed freshness. After that, Today shows required
acknowledgements, unread priority announcements, and recent recognition relevant to the user.

When the user is off shift, Today becomes the only available working surface. It shows that notifications are paused,
offers a Start shift action, and summarizes what is quietly waiting.

Today gets quieter as work is completed. Acknowledged announcements disappear from the urgent area. Read handoffs no
longer dominate the view. The surface should feel like a briefing, not another inbox.

### The House

The House is the shared memory of the property.

It contains manager announcements, pinned operational notices, recognitions, and general house-wide updates. Pinned
announcements sit at the top when they need ongoing attention. Recognition has a prominent entry point so staff can
quickly celebrate a colleague without treating it like an administrative task.

The feed is grouped by day and ordered newest-first within the ordinary feed. Pinned announcements sit above the day
groups while they remain pinned. Filter chips let the user switch between all posts, announcements, and recognition.

Announcements are audience-targeted by channel. Read receipts and acknowledgement status live on the announcement
detail page, so managers can see who has read, acknowledged, missed, or not yet received the message because they are
off shift.

### Chat

Chat is the working conversation layer.

It contains direct messages and channel conversations. Direct messages are for person-to-person coordination. Channel
conversations are for department-level work: a room turnover note for Housekeeping, a front desk escalation, a
maintenance update, a service prep reminder.

The inbox is ordered by most recent activity. Each row shows the colleague or channel name, the latest message preview,
and the latest message time. Conversations with no messages stay out of the inbox until the first message exists, so
the surface stays focused on active work.

Starting a conversation is explicit. From Chat, the user can start a new message, pick a colleague, and Foyer either
opens the existing direct conversation or creates one if none exists. The same picker includes channels: choosing a
channel opens that channel's existing conversation. Users only see channels they belong to in this picker.

Unread work is visible without turning the whole app into an inbox. When a user receives a message they have not read,
Foyer shows a small red dot on Chat in the navigation. The same unread state appears on the relevant conversation row
inside the inbox.

The chat surface should make availability obvious. Off-shift colleagues are marked clearly, so sending a message does
not create a false expectation of an immediate reply. The goal is to replace fragmented side channels without
recreating the pressure of always being reachable.

### Profile

Profile is the staff member’s personal recognition and rewards page.

It shows their role in the property, languages, recent recognition activity, and Foyer points balance. Staff can see
recognition they have received, recognition they have given, and the rewards their points may eventually unlock.

The rewards catalog is visible in v1 but not redeemable. It gives points a concrete shape without requiring approval,
budgeting, or redemption operations in the POC.

## Version boundary

Foyer v1 is the first complete product slice. It should prove the operating model: staff start their day in Today,
managers publish targeted announcements, teams coordinate in chat, colleagues recognise good work, and everyone has a
profile where recognition becomes visible.

v1 intentionally keeps the system shallow in a few places. The goal is not to ship every future workflow, but to make
the core product feel real enough that hotel operators can understand it, use it, and react to it.

### v1

#### POC Access

The POC uses a simple user picker instead of production authentication.

The picker includes one manager and two Housekeeping staff members. This gives the demo enough contrast to show role
differences, channel membership, acknowledgement flows, recognition, and shift boundaries without introducing a full
login system.

#### Today

Today is the staff member’s briefing surface.

In v1, Today shows the most recent relevant handoff, announcements that still need the user’s acknowledgement,
recognition received recently, and the user’s shift state. Staff can start a shift, end a shift, and optionally leave
a handoff note for the next shift.

When off shift, Today shows a paused state, a Start shift action, and a compact count of work held for the user:
announcements, messages, and private recognitions since their last shift ended.

Today does not need live updates in v1. It refreshes when the user loads the page, starts a shift, ends a shift, or
returns to the surface.

#### The House

The House is the property feed.

In v1, it contains announcements and recognitions. Announcements can be pinned, require acknowledgement, and be
targeted to a channel. Recognitions appear in the feed when public. The feed can be filtered by type.

Pinned announcements appear above the day-grouped feed. The ordinary feed is grouped by day and ordered newest-first.
Audience filtering happens on read: users do not see announcements targeted to channels they are not members of.

The House does not need live updates in v1. New announcements and recognitions appear after navigation, refresh, or
returning to the feed.

#### Announcements

Announcements are manager-authored posts with optional acknowledgement requirements. They can be pinned for visibility
and later unpinned by any manager.

In v1, managers can target only channels they belong to. Audience membership determines visibility: if a user is not
in the target channel, they do not see the announcement and they are not counted in acknowledgement receipts.

Acknowledgement recipients are based on the selected channel, but the announcement author is excluded. A manager who
posts an announcement should not be required to acknowledge their own message.

Announcement detail pages show basic receipt status: acknowledged, read without acknowledgement, unread, and
off-shift. v1 does not include advanced analytics such as median acknowledgement time, per-minute timelines, exports,
or nudges.

#### Grace Windows

Announcements and recognitions have a short author-only grace window for corrections.

In v1, this is intentionally simple. The server decides whether the grace window is open. When it is open, the author
sees Edit and Remove actions. When it has closed, those actions disappear on the next page load or server interaction,
and late attempts are rejected.

Foyer does not show a live countdown in v1. That is deliberate: the POC needs the correction rule, not second-by-second
timer UI.

#### Recognitions

Recognitions are lightweight shout-outs between staff members.

In v1, any staff member can recognise a colleague. Managers may attach optional bonus points. Public recognitions
appear in The House and on the recipient’s profile. Recognition points are recorded in a simple ledger and shown as a
balance.

Recognitions include at least one house value. Manager bonus points are limited to fixed v1 tiers.

v1 includes a rewards catalog on Profile, but redemption is not active. Reward actions are shown as coming soon.

#### Chat

Chat is the live conversation layer.

In v1, Foyer supports direct messages and channel conversations. Direct messages are participant-based. Channel
conversations are membership-based. Users only see channels they belong to, and managers do not get a hidden override
into non-member channels.

The chat inbox lists visible conversations with messages, ordered newest-first by latest message activity. Each row
shows the other participant or channel name, the latest message preview, the latest message timestamp, and unread state.
Empty conversations are hidden until the first message exists.

The New message flow has two tabs: People and Channels. People starts or opens a direct conversation with one colleague.
Channels opens the selected channel's existing conversation. Only channels the user belongs to are selectable.

Chat is the only v1 area with live updates. Messages, read receipts, unread indicators, and active chat thread updates
should use PubSub so the conversation feels immediate.

Unread chat is shown with a small red dot on the Chat navigation item and on unread conversation rows. Messages authored
by the viewer do not count toward their own unread state.

v1 does not include typing indicators, message reactions, inline translation, attachments, muting, or ad-hoc group
chats. Multi-person conversation happens through channels.

#### Channels

Channels are the operational rooms of the property. They usually map to departments or recurring service contexts:
Housekeeping, Front Office, Food & Beverage, Maintenance, Spa, Leadership.

In v1, channels define membership, announcement targeting, chat access, and handoff visibility. If someone should see
or participate in a channel, they should be a member of that channel.

Managers are not outside the model. They can be members of channels like everyone else. In seed data, managers may
belong to all default property channels, but access still comes from membership. In v1, channels are seeded from
departments, with managers included, and Foyer does not include channel administration.

#### Shift Boundaries

Foyer depends on explicit shift state.

In v1, staff can start and end shifts. Ending a shift can include a handoff note targeted to a channel the user
belongs to. Starting a shift brings relevant handoff context into Today.

Off-shift status affects how people appear in the product and how queued work is summarized. v1 may count waiting
items, but it does not implement full notification delivery rules.

#### Profile

Profile is the staff member’s personal recognition and rewards page.

In v1, Profile shows role, property, languages, recognition received, recognition given counts, Foyer points, and the
rewards catalog. It makes recognition feel tangible without implementing full rewards redemption.

### v2

v2 deepens the workflows that v1 proves.

Planned v2 areas include:

- Advanced announcement lifecycle rules: auto-unpin on full acknowledgement, scheduled unpin, scheduled publish.
- Richer post lifecycle UX: visible countdowns, undo toasts, scheduled expiry, and clearer audit history for edits and
  removals.
- Rich receipt analytics: acknowledgement timeline, declined/exception states, and manager nudges.
- Real notification delivery rules: queued delivery on clock-in, critical overrides, notification preferences, and
  delivery audit.
- Today handoff depth: show all eligible handoffs instead of only the most recent one, with clear grouping and
  de-emphasis after review.
- Chat depth: typing indicators, delivery receipts separate from reads, reactions, attachments, muting, pinned
  conversations, and inline translation.
- Translation for announcements and chat across multilingual teams.
- Rewards redemption: redeem points for time, meals, spa benefits, donations and audit flows.
- Channel administration: create channels, edit membership, archive channels, and manage non-department service
  groups.
- Mobile app with push notifications and production authentication.
