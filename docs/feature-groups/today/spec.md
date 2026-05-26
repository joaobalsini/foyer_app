# Today — spec

Today is the staff member's daily briefing surface. It is phone-first and gets quieter as the shift
progresses. When on shift, it shows — in priority order — the most recent relevant handoff from the
previous shift, announcements that still require the user's acknowledgement, and recent recognition
received while the user was off shift. When off shift, Today becomes the user's entire allowed
surface: a paused-state banner, a Start shift action, and a compact summary of work held quietly in
waiting. Transitions between off-shift and on-shift states update the view on the same page load that
follows the action; there is no live push in v1.

*(v2 additions: F.Today.20 and F.Today.21 added to address spec gaps identified in the Codex review.)*

## Scope

**In scope**

- Off-shift paused state: banner, Start shift action, waiting-count summary (announcements needing
  ack, unread messages, private recognitions received since last shift ended).
- On-shift staff state: handoff card, needs-acknowledgement list, recent recognition cards, End shift
  link.
- On-shift manager state: same structure as staff plus a New announcement CTA; manager's own live
  posts replace the needs-ack list when the manager has nothing pending.
- Start shift action: transitions Today from off-shift to on-shift state.
- End shift flow: required note and target channel when submitting a handoff, plus an explicit skip
  clock-out action for ending without a handoff.
- Inline acknowledgement: tapping a needs-ack item navigates to the announcement detail; once the
  user acknowledges there, the item disappears from Today on next surface load.
- Off-shift route gate: every authenticated route other than `/today` redirects off-shift users back
  to `/today`.
- "Gets quieter" property: acked items disappear from the urgent area; the handoff card fades to
  background once the user has read it (page re-load).
- Mobile-first viewport at phone width.

**Out of scope**

- PubSub / real-time push in v1. Today refreshes on page load, shift start, shift end, and surface
  re-entry only.
- Composing announcements or recognitions from Today. Write paths for those live in their own
  feature groups.
- Notification delivery rules, push notifications, or queued-delivery audit.
- Multiple simultaneous open shifts per user (the DB enforces one open shift per user).
- Shift scheduling or rostering; Foyer treats shift state as something the worker explicitly controls.

---

## Clauses

### F.Today.1 — Off-shift paused state banner

**Given** an authenticated user whose current shift is nil (no open shift row)  
**When** the user navigates to `/today`  
**Then** the page renders with:
- a tag reading "Off shift · notifications paused",
- the copy "You're off the clock. Rest is part of the work.",
- the copy "You won't receive notifications until you start your next shift.",
- a "Start shift" button,
- a waiting-count line ("While you were off · N waiting") where N reflects the total of unacknowledged
  announcements, unread messages, and private recognitions received since the user's last shift ended.

### F.Today.2 — Off-shift route gate

**Given** an authenticated user who is off shift  
**When** the user navigates to any route inside `:authenticated_on_shift` (e.g. `/house`, `/chat`,
`/me`, `/people`, announcement or recognition detail pages)  
**Then** the router redirects to `/today` with the flash "Start your shift to enter the rest of
Foyer." and the target page does not render.

### F.Today.3 — Start shift transition

**Given** an authenticated user who is off shift, viewing `/today`  
**When** the user taps "Start shift"  
**Then** a new Shift row is inserted with `started_at = now` and `ended_at = nil`, the user's scope
becomes on-shift, and Today re-renders showing the on-shift view (handoff card if one exists, plus
the needs-ack list and recent recognition).

### F.Today.4 — On-shift staff state: priority content order

**Given** an authenticated staff user who is on shift  
**When** the user views `/today`  
**Then** the page renders — in this exact visual order:
1. On-shift status pill with the user's title and an End shift link.
2. Handoff card (if a relevant handoff exists from the previous shift on a shared channel, within
   the last 24 hours).
3. "Needs your acknowledgement" section listing any announcements targeted to the user's channels
   that require acknowledgement and have not yet been acknowledged by this user.
4. Recent recognition cards for recognitions received by this user (up to three).

### F.Today.5 — Needs-acknowledgement item links to announcement detail

**Given** an on-shift user with one or more unacknowledged announcements in Today  
**When** the user taps a needs-ack item  
**Then** the user is navigated to the announcement detail page (`/announcements/:id`), where they
can read the announcement and acknowledge it.

### F.Today.6 — Acknowledged item disappears from Today

**Given** an on-shift user who has one or more items in the needs-ack section  
**When** the user acknowledges an announcement (on its detail page) and then returns to `/today`  
**Then** the acknowledged announcement no longer appears in the needs-ack section; all remaining
unacknowledged items are still shown.

### F.Today.7 — Today gets quieter as acknowledgements are completed

**Given** an on-shift user who has acknowledged all their required announcements  
**When** the user views `/today`  
**Then** the "Needs your acknowledgement" section is absent from the page; the briefing shows only
the handoff card (if present) and recent recognition.

### F.Today.8 — Handoff card content

**Given** a relevant handoff exists: another user's shift that (a) ended within the last 24 hours,
(b) targeted a channel the current user is a member of, and (c) includes a handoff note  
**When** the user views `/today` on shift  
**Then** the handoff card shows: the previous shift-holder's name and initials, the ended-at time,
and the handoff note text.

### F.Today.9 — No handoff card when no relevant handoff exists

**Given** no shift exists in the last 24 hours that matches the handoff query (no note, or different
channel membership, or too old)  
**When** the user views `/today` on shift  
**Then** the handoff card section is absent from the page.

### F.Today.10 — End shift — opens handoff prompt

**Given** an authenticated user who is on shift  
**When** the user taps "End shift"  
**Then** the page navigates to `/today/end-shift` and renders a handoff prompt with a textarea for a
note and a "Clock out" submit button; a "Skip · clock out" option is also available.

### F.Today.11 — End shift — handoff note and channel are required

**Given** the user is on the `/today/end-shift` view  
**When** the user fills in a handoff note, keeps one of their channels selected, and submits  
**Then** the current shift row is updated with `ended_at = now`, `handoff_note`, and
`handoff_channel_id`; the user's scope becomes off-shift; Today re-renders in the off-shift state.
The form starts with the user's first channel selected, does not offer a blank channel option, and
the backend rejects handoff-form submissions with either an empty note or missing channel.

### F.Today.12 — End shift — skip (no note)

**Given** the user is on the `/today/end-shift` view  
**When** the user taps "Skip · clock out"  
**Then** the current shift row is updated with `ended_at = now` and no handoff note; the user's
scope becomes off-shift; Today re-renders in the off-shift state.

### F.Today.13 — On-shift manager state: New announcement CTA

**Given** an authenticated user whose role is `:manager` and who is on shift  
**When** the user views `/today`  
**Then** the page renders a "New announcement" CTA button that navigates to the announcement compose
surface; the rest of the Today structure (on-shift pill, handoff card, needs-ack list, recent
recognition) follows the same rules as for staff.

### F.Today.14 — On-shift manager state: live posts section

**Given** an on-shift manager viewing `/today`  
**When** the manager has one or more published, non-removed announcements they authored  
**Then** a "Your live posts" section is rendered below the needs-ack section, listing those
announcements ordered newest-first by `published_at`; only announcements with a non-null
`published_at` are included. Each live post uses the shared `announcement_card` component so the
announcement treatment matches the House feed.

### F.Today.15 — No PubSub: Today does not auto-refresh

**Given** an on-shift user is viewing `/today`  
**When** another user acknowledges an announcement or a new announcement is posted  
**Then** Today does not update in real time; the change is visible only after the user navigates away
and returns to `/today` (or reloads the page).

### F.Today.16 — Off-shift waiting counts reflect work since last shift

**Given** an off-shift user whose last shift ended at time T  
**When** the user views `/today`  
**Then** the waiting count shown reflects the number of unacknowledged announcement-ack obligations
plus unread messages plus private recognitions addressed to the user, all created or modified after
time T; items created before T are excluded from the count. The unread message count excludes
messages the user authored themselves.

### F.Today.17 — Mobile-first rendering

**Given** any authenticated user viewing `/today` in a phone-width viewport (≤ 390 px wide)  
**When** the page renders  
**Then** all Today content (off-shift banner, on-shift briefing, handoff card, needs-ack list,
recognition cards, end-shift form) fits within the viewport without horizontal overflow; the
bottom navigation is sticky at the bottom; tap targets meet minimum 44 px height.

### F.Today.18 — Recent recognition cards

**Given** an on-shift user has received one or more recognitions  
**When** the user views `/today`  
**Then** up to three most recent recognitions are shown, including received recognitions and the
current user's authored private recognitions, each rendered with the shared House recognition card
style. `View` appears only for recognitions authored by the current user and navigates to
`/recognitions/:id`.

### F.Today.19 — No recognition section when none received

**Given** an on-shift user has received no recognitions  
**When** the user views `/today`  
**Then** the recognition section is absent from the page.

### F.Today.20 — Unread message count semantics

**Given** an off-shift user whose last shift ended at time T  
**When** Today computes the unread message count for the waiting summary  
**Then** the count includes only messages where:
- `message.author_id != user.id` (the user's own messages are excluded),
- `message.inserted_at > T` (or all-time if T is nil, i.e. the user has never ended a shift),
- the user is a direct participant in the conversation **or** a member of the channel conversation,
- no `chat_message_reads` row exists for `(message_id, user_id)`.

### F.Today.21 — Handoff card "gets quieter" on re-load

**Given** an on-shift user views `/today` and a handoff card is rendered  
**When** the user navigates away and returns to `/today` on a subsequent page load  
**Then** the handoff card is de-emphasised visually (rendered with muted styling rather than the
full-attention card treatment); it does not disappear, but it no longer dominates the view. No
persistent read-state record is stored for handoffs in v1; the visual de-emphasis is UI-only,
driven by a flag the LiveView sets after the first render of the current session.

### F.Today.22 — Desktop topbar hides the +New menu off-shift

**Given** an authenticated user who is off shift, viewing any surface that renders the desktop
topbar (`#desktop-topbar`)  
**When** the topbar component is rendered  
**Then** the `#new-menu` dropdown (including its `New chat`, `New announcement`, and
`Give recognition` items) is absent from the DOM. The +New menu would only deep-link into
on-shift-gated routes, so it is suppressed for off-shift users; the only call-to-action they see
is `Start shift` in the Today off-shift card.
