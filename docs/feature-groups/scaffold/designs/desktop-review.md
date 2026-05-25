# Desktop design review — mockups vs `../foyer` implementation

Audit comparing every `designs/**/desktop-*.html` mockup against the actually
implemented LiveView UI in the sibling project at `/Users/joaobalsini/dev/foyer`.
The mockups in `../foyer/designs/` are byte-identical to ours, so the
implementation in `../foyer/lib/foyer_web/live/*` is the only meaningful "real
design" reference.

12 mockups reviewed across 4 feature groups: chat (1), house (6), profile (1),
recognition (4).

## TL;DR — the headlines

1. **`designs/profile/desktop-charlotte-voss.html` is misfiled.** The page is a
   Chat UI, not a Profile UI. There is no desktop Profile mockup at all.
2. **`designs/house/desktop-weekly-digest.html` is a byte-for-byte duplicate of
   `desktop-my-announcements.html`** (only `<title>` differs), and neither the
   "weekly digest" nor "my announcements" routes exist in the implementation.
3. **The mockups invent features the backend cannot support today**: multi-channel
   announcement audiences, draft saving, auto-translate (EN·FR·ES·PT·TL·YO),
   scheduled publishing/sending, file attachments, push notifications, ack
   timeline sparkline, median-to-ack metric, declined/conflict state, monthly
   recognition quota, nudge/export actions, recipient typeahead picker, a
   "Team" house value (only six exist), point-emoji reactions on recognitions.
4. **The mockups omit the F.F.4 grace-window UI entirely** from
   `desktop-recognition-sent-undo.html` — there's no countdown, no Edit, no
   Remove. Filename promises "undo" but no undo affordance is shown.
5. **Chat desktop assumes a three-pane (rail + inbox + thread) layout** while
   the implementation's `:show` route is single-pane. The compose-state widgets
   (Schedule checkbox, Schedule button, attach/emoji, ⌘+⏎ hint, textarea) are
   fabricated.

---

## Critical — mockup will mislead implementation

These divergences will cause an implementer following the mockup to build the
wrong screen, the wrong control, or features the data model doesn't support.

### `profile/desktop-charlotte-voss.html`
- **Wrong feature entirely.** File renders a Chat conversation with Maya Okafor
  — left rail with channels + DM list, center thread, composer. The real
  ProfileLive (`profile_live.ex:82-150`) is a four-section page: header
  (avatar + name + "Member since … · Languages: …"), 3-tile stats grid
  (Received this month / Given this month / Foyer points), a Recognitions
  Received list, and a Trade-your-points rewards catalog. **None** of that
  appears in the mockup.
- Move the file to `designs/chat/` (or delete) and produce a real desktop
  Profile mockup. `designs/profile/mobile-recognitions-received.html` already
  contains the right content for reference.

### `chat/desktop-message-off-shift.html`
- **Three-pane layout doesn't exist.** Mockup shows rail + inbox list + thread
  side-by-side; `chat_live.ex:589-647` renders only the thread on
  `/chat/:id`. The inbox is a separate route (`:index`, `chat_live.ex:266-307`).
- **Scheduled-send is fabricated.** The checked "Schedule" checkbox, disabled
  "Schedule" submit button, and "Note for Rafael when they're back…" textarea
  placeholder imply queued delivery. `handle_event("send", …)` calls
  `Chat.send_message/3` unconditionally — no schedule concept anywhere.
- **Composer affordances are fabricated.** Mockup uses `<textarea>` + Attach
  button + Emoji button + `⌘+⏎` hint; implementation (`chat_live.ex:637-645`)
  is a one-line `<input type="text">` + "Send" button. No uploads, no emoji
  picker, no shortcut.
- **Global "Search staff, rooms, announcements" + `⌘K` doesn't exist.** The
  desktop topbar (`layouts.ex:294-347`) is just page title + "+ New" dropdown.

### `house/desktop-compose.html`
- **Audience is a single `channel_id`, not multi-select checkboxes.**
  `announcement.ex:5,40` allows exactly one channel; impl renders a single
  `<select name="audience">` (`announcements_live.ex:295-307`). The mockup's
  6-checkbox audience picker + "22/84 colleagues will receive this" counter
  would over-build a feature the schema can't store.
- **"Save draft" button is not implemented.** Only "Publish now" exists.
- **Auto-translate (EN·FR·ES·PT·TL·YO) is fabricated.** No locale column, no
  translation pipeline anywhere.
- **Schedule (`now / shift start / at 14:00`) is fabricated.** Impl publishes
  immediately with `published_at: utc_now()`.
- **Attachments are fabricated.** No upload column, no LiveView upload binding,
  no UI for file management.

### `house/desktop-my-announcements.html`
- **"By me / This week / This month / All time / All 15" filters don't exist.**
  Impl has three chips only — All / Announcements / Recognition
  (`house_live.ex:131-139`). No author-scoped view, no time-window filter, no
  archive concept. No `/my` or `/announcements/mine` route.
- **Recognition cards show "✦ 18 ♡ 6" / "✦ 24 ♡ 9 ☕ 4" point/emoji tallies.**
  The real `recognition_card` (`foyer_ui.ex:257-294`) renders House value chips
  + optional "+N pts" bonus pill. No per-emoji reactions exist in the schema.

### `house/desktop-read-receipts.html`
- **`/receipts` route does not render this page.** `receipts_live.ex:11-17`
  redirects to `/announcements/:id`; receipts are inlined under announcement
  detail. The mockup's URL bar (`foyer.thelinden.hotel/receipts`) is wrong.
- **"Nudge" and "Export" actions are fabricated.** Only "Unpin" exists
  (`announcement_live.ex:201-209`).
- **Acknowledgement-timeline sparkline is fabricated.** No time-bucketed ack
  data, no chart.
- **Median-to-ack and team-average metrics are fabricated.**
- **"Declined / flagged conflict" metric is fabricated.** Receipt states are
  only `:acked | :read | :unread | :off_shift` (`announcement_live.ex:442-450`).
- **"Target 100% by 12:00"** — no per-announcement deadline field exists.

### `house/desktop-announcement-published-undo.html`
- **No dedicated post-publish success page exists.** Impl `push_navigate`s to
  `/announcements/:id` with a flash and shows a small italic "60s to edit or
  remove." line above Edit/Remove buttons (`announcement_live.ex:231-261`).
  The mockup's full-card success layout (with hero "52" countdown badge,
  "Audience: 1 channel", "Pinned: Yes — top of feed", "Translated: EN·FR·ES…",
  Receipt summary) is mockup-only.
- **"+ Another", "Receipt", "View read receipts", "See it in the feed" CTAs
  are fabricated.** Only Edit and Remove exist during grace.
- **"It's now at the top of The House feed and on every recipient's phone as
  a push"** — push notifications are not implemented; only LiveView PubSub
  fan-out exists.

### `house/desktop-weekly-digest.html`
- **Entire feature is fabricated.** File is a byte-for-byte duplicate of
  `desktop-my-announcements.html` (only `<title>` differs). No `/digest` route,
  no `Foyer.House.weekly_digest/*` function, no scheduled email/notification
  job. Either produce a real digest mockup or delete this file.

### `recognition/desktop-give.html`
- **"Team" house value doesn't exist.** Mockup shows seven chips
  (Care, Craft, Discretion, Initiative, Warmth, Excellence, **Team**).
  `house.ex:62` defines exactly six (no Team); `foyer_ui.ex:14-21` confirms.
  Adding Team would break the enum.
- **"Save draft" button is fabricated.**
- **"—" (none) bonus tier is wrong.** Mockup renders `— / +25 / +50 / +100` as
  four equal toggles. Impl renders only the three tiers plus a separate text
  `clear` link (`recognition_live.ex:474-498`).
- **Recipient picker is a `<select>`, not an avatar card with "Change…"
  button.** `recognition_live.ex:378-392` is a plain dropdown — the mockup
  implies a typeahead search picker that doesn't exist.
- **"House values shown" label** mis-implies a passive readout. It's a
  multi-select picker (`recognition_live.ex:395`, subtext "Pick one or more.").

### `recognition/desktop-staff-give-no-points.html`
- Inherits all desktop-give criticals (Team chip, Save draft, recipient card,
  values picker).
- **Preview avatar is wrong persona.** Mockup shows Charlotte (`CV`) in the
  preview author block while the left nav is Maya Okafor. Impl uses
  `@current_user` for the preview avatar (`recognition_live.ex:531`), so the
  staff user (Maya) should appear there.

### `recognition/desktop-recognition-sent-undo.html`
- **The 60s grace UI is missing entirely.** Filename promises
  "edit / remove / undo" but the mockup has no countdown, no Edit, no Remove —
  only a "See it in the feed" ghost button. Impl
  (`recognition_live.ex:289-339`) is built around `60s to edit or remove.` +
  Edit link + Remove button + expired state. An implementer would drop the
  core F.F.4 affordance.
- **Receipt block is fabricated.** Mockup shows a labeled grid
  (Recipient / Values / Visibility / Bonus). Impl shows a single sentence:
  `Recognition for {recipient}{· N Foyer points} — delivered.`.
- **"Reactions and shout-outs will roll into the weekly digest."** Invents a
  weekly digest feature that doesn't exist.
- **"50 Foyer points" hardcoded** with no manager gate visual. Impl only
  renders bonus when `@is_manager and @bonus_points` (`:300`).

### `recognition/desktop-people-directory.html`
- **Department filter is a `<select>`, not a button-popover.** Impl uses native
  `<select name="department">` (`people_live.ex:92-104`).
- **"On shift" filter is a `<input type=checkbox>`, not a pill button.**
  Label is "On shift only" (`people_live.ex:105-108`).
- **Every colleague is shown "On shift".** Mockup hardcodes the pulse pill on
  all 14 cards. Impl conditionally renders the on-shift pill only when
  `@user.on_shift` (`foyer_ui.ex:316-320`); off-shift users show name + title
  only. The mockup never demonstrates the off-shift visual.

---

## Notable — real divergence, lower risk

### `chat/desktop-message-off-shift.html`
- "View profile" button in the conversation header doesn't exist
  (`chat_live.ex:593-603`).
- Off-shift banner: mockup uses `<b>Rafael</b>` (first name) without icon;
  impl renders full `{@title}` with leading `hero-moon` icon
  (`chat_live.ex:625-635`).
- "READ" indicator: mockup shows it as a separate uppercase pill; impl
  renders ` · Read` inline appended to the timestamp (`foyer_ui.ex:392-395`).
- Inbox rows show colleague title ("Sr. Housekeeper", "Night Manager") under
  the name. Impl `conversation_row` (`chat_live.ex:311-358`) doesn't render
  titles.
- Unread badge: mockup uses textual "2 new" / "1 new" pills; impl uses a small
  red dot (`chat_live.ex:328-333`) — count is never exposed.
- Chat nav rail badge: mockup shows numeric `4`; impl uses dot only
  (`ChatUnreadDot` LiveComponent).
- Rail header: mockup shows "Foyer / STAFF · LDN·MAY" with an "F" badge; impl
  shows "Foyer" + `{property.name} · {property.city}` (`layouts.ex:132-135`).

### `house/desktop-compose.html`
- Pin "Unpin when" sub-options (`I unpin / Everyone acked / At a specific
  time`) don't exist. `pinned` is a single boolean; helper copy is "Stays
  pinned until you unpin manually." (`announcements_live.ex:324`).
- "★ Pinned" / "✓ Requires ack" tag styling: real `status_pill` renders just
  "Pinned" / "Ack required" — no star, no checkmark (`foyer_ui.ex:47-48`).
- Mockup preview card has an inline "Acknowledge" button. Real feed card
  (`foyer_ui.ex:140-228`) shows ack-progress text only — the Acknowledge
  button lives on the detail page.

### `house/desktop-staff-compose-gated.html`
- Missing the `manager_only` status pill on top of the card
  (`gated_live.ex:29` prepends it). Mockup shows bare "Manager view only." text.
- URL bar says `/compose` — the gated route is `/gated`.

### `house/desktop-my-announcements.html`
- Pinned placement is wrong. Impl renders a separate
  `<section id="pinned-section">` above the dated feed groups
  (`house_live.ex:149-152`). Mockup nests Pinned inside the "This week" group.
- Missing the "Notice a colleague going above and beyond? — Recognize"
  parchment CTA card that sits between the filter chips and the feed
  (`house_live.ex:141-147`).
- Day-group labels: impl uses "Today", "Yesterday", "Mon 18 May"
  (`house_live.ex:235-245`); mockup uses "This week" / "Earlier this month".
- Per-card ack progress: mockup "2 / 14 acked →"; impl
  "{confirmed}/{audience} acknowledged" (no arrow, full word).

### `house/desktop-read-receipts.html`
- Per-person row labels: mockup uses uppercase compact "ACK · 07:48",
  "READ · 07:53", "UNREAD", "OFF SHIFT". Impl uses "Acknowledged", "Read",
  "Unread", "Off shift" with a colored dot (`announcement_live.ex:412-431`).
- Mockup person rows include ack timestamps. Impl's `status_label` doesn't
  render ack timestamps.
- "target 100% by 12:00" — impl shows "target 100%" with no time
  (`announcement_live.ex:310`).

### `house/desktop-announcement-published-undo.html`
- Copy "no one will see the change" is misleading. PubSub broadcasts
  `{:announcement_updated, _}` during grace — anyone already viewing the
  detail page sees the edit in real-time.

### `recognition/desktop-give.html`
- "This month 3/5 recognitions you've given" stat panel doesn't exist. No
  monthly quota / usage counter anywhere.
- Right rail collapses Preview + monthly stat + Visibility + Bonus + Send.
  Impl puts only Preview in the right aside; Visibility/Bonus/Send live inside
  the left form column.
- Visibility radios are shown as button-style cards. Impl uses an
  `<input type=radio>` fieldset (`recognition_live.ex:446,459`).
- Subhead copy: mockup splits the helper line; impl puts it in one block
  ("Shout-out a colleague. Write it like you'd tell it at staff dinner.
  Specific moments land.").

### `recognition/desktop-staff-give-no-points.html`
- No-points note placement: impl renders it as a `card-parchment`
  (`id="staff-bonus-note"`) inside the main form column
  (`recognition_live.ex:503-508`); mockup floats it in the right rail.

---

## Minor — polish gaps

- **`house/desktop-staff-compose-gated.html`** — "react in **the** House"
  (lowercase t) vs impl "react in **The** House" (`gated_live.ex:32`).
- **`house/desktop-compose.html`** — mockup omits the body character counter
  `{String.length(@body)} / 800` (`announcements_live.ex:290`). Subhead copy
  differs ("Compose an announcement" vs "Composing an announcement. Reach the
  right people. Pin if it must be seen.").
- **`house/desktop-my-announcements.html`** — audience labels in impl come from
  `House.audience_label(channel_id)` ("All Housekeeping"); mockup composes
  "Charlotte Voss · Housekeeping · All floors" (author + hierarchy).
- **`chat/desktop-message-off-shift.html`** — subtitle uses "○" bullet glyph;
  impl is plain "Off shift · notifications paused" (`chat_live.ex:675`). Inbox
  shows "Yest." timestamps but `format_time` (`foyer_ui.ex:441-445`) only
  returns `HH:MM` — no day-relative formatting exists. "All" filter in inbox
  toolbar has no counterpart in `render_inbox`. "+ New" placement diverges.
- **`recognition/desktop-people-directory.html`** — no empty-state in mockup
  (impl has `<div :if={@colleagues == []}>No matches.</div>`,
  `people_live.ex:120`). Mockup lists the current user; impl excludes via
  `exclude_user_id` (`people_live.ex:16,42`).
- **`recognition/desktop-give.html`** — bonus-points helper copy slightly
  differs ("…redeemable in the staff portal for time-off, meals, or charitable
  donations." vs "…staff rewards — time off, meals, charitable donations.").

---

## Recommended next steps

1. **Delete or rewrite** `profile/desktop-charlotte-voss.html` and
   `house/desktop-weekly-digest.html` — both are broken in the largest possible
   way (wrong feature / duplicate).
2. **Strip fabricated features** from the remaining mockups before they are
   used as implementation source-of-truth: translations, attachments,
   scheduling, drafts, push notifications, multi-channel audience, monthly
   recognition quota, nudge/export, ack timeline / median-to-ack / declined,
   "Team" house value, point-emoji reactions on recognitions, recipient
   typeahead, 60s-grace replacement for `sent-undo`.
3. **Fix the data-model control mismatches** (single channel select, ack states
   set, three bonus tiers + clear link, six house values, on-shift checkbox,
   department `<select>`).
4. **Restore the 60s grace UI** in `recognition/desktop-recognition-sent-undo`
   — this is the core F.F.4 affordance and the file currently shows none of it.
5. **Add the off-shift visual** to `recognition/desktop-people-directory` (at
   least one card without the pulse pill).
