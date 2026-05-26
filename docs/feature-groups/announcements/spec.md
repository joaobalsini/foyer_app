# Announcements — spec

Announcements is the manager-driven posting surface inside House. Managers compose short,
channel-scoped notices ("Suite 412 allergy protocol", "Lift inspection at noon") that staff in
the targeted channel read, optionally acknowledge, and — for the manager — see receipts for. The
feature centres on three guarantees: a tight authoring grace window so mistakes can be fixed but
posts stop drifting after publication settles; a four-bucket receipts view so managers can see at
a glance who has acknowledged, who has only read, who has not seen it, and who is off shift; and
membership authorization enforced at the context boundary so route gating is not the only line of
defence.

The surface lives at `/announcements/new`, `/announcements/:id`, and `/announcements/:id/edit`,
all backed by `FoyerWeb.AnnouncementLive` and the `Foyer.House` context.

## Scope

**In scope**

- Compose flow at `/announcements/new`: manager-only, channel-scoped, optional
  acknowledgement requirement.
- Detail page at `/announcements/:id`: renders the announcement, the read-and-acknowledge CTA
  for non-author members, and (for managers in the channel) the four-bucket receipts panel.
- Edit flow at `/announcements/:id/edit`: author-only, gated by a 5-minute grace window after
  `published_at`.
- Pin / unpin from the detail page, by managers in the channel.
- Soft removal via `removed_at`, gated by the same grace window; removed posts leave user feeds
  but stay queryable through `receipts_for/2` for audit.
- Acknowledgement and mark-read writes via `Foyer.House.acknowledge/2` and
  `Foyer.House.mark_read/2`, both idempotent on `(announcement_id, user_id)`.
- Receipts grouping into `acknowledged`, `read_without_acknowledgement`, `unread`, `off_shift`
  with `off_shift` taking precedence.
- Membership authorization at the context boundary for read, ack, mark-read, pin, unpin, edit,
  and remove paths.

**Out of scope**

- Real-time PubSub updates of receipt buckets or new announcements (users see updates on next
  page load).
- Cross-channel announcement broadcasting; each announcement belongs to a single channel.
- Scheduled or draft announcements; publication is immediate on create.
- Announcement comments, reactions, or threads.
- Notification delivery rules and push notifications.
- Re-opening the grace window or any "manager override" of grace-expired edits.

---

## Clauses

### F.Announcements.1 — Managers publish to their own channels

**Given** a manager who is a member of channel X  \
**When** they publish an announcement to channel X  \
**Then** the announcement is created with the manager as author, scoped to channel X, and
persists with the requested `requires_ack` setting. The user is redirected to the new announcement's
show page with an info toast confirming the announcement was published.

### F.Announcements.2 — Staff cannot compose announcements

**Given** a staff user (non-manager)  \
**When** they attempt to create an announcement — whether by visiting `/announcements/new` or by
submitting a forged compose payload  \
**Then** the compose route redirects them away with a flash, and the context-level write rejects
the attempt with `{:error, :unauthorized}` so no announcement is persisted.

### F.Announcements.3 — Author may edit within the 5-minute grace window

**Given** the author of an announcement published less than 5 minutes ago  \
**When** they edit the title, body, audience, or `requires_ack` setting  \
**Then** the update succeeds, the new values are persisted, and the user is redirected back to the
announcement show page.
On the detail page, author/manager actions render after the announcement body in this order:
Pin/Unpin, Edit, then Remove.

### F.Announcements.4 — Edit and remove are rejected after grace or by non-authors

**Given** an announcement whose 5-minute grace window has expired (or a non-author attempting
the action)  \
**When** the author attempts to edit the announcement  \
**Then** the update is rejected with `{:error, :outside_grace_window}` (or `{:error, :unauthorized}`
for non-authors) and the announcement is unchanged. On the detail page, the author still sees the
Edit and Remove actions, but they are disabled with a tooltip explaining that editing and removal
are only available for 5 minutes after publishing.

**When** the author attempts to remove the announcement  \
**Then** the removal is rejected with the same error and the announcement is unchanged.

### F.Announcements.5 — Managers pin and unpin announcements in their channel

**Given** a manager who is a member of channel X  \
**When** they pin (or unpin) an announcement that lives in channel X  \
**Then** the announcement's `pinned_at` is set (or cleared), and the rendered detail page swaps
the pin/unpin affordance to reflect the new state.

### F.Announcements.6 — Removal is soft and preserves auditable receipts

**Given** an announcement that has been removed (its author called remove within the grace
window)  \
**When** any channel member loads their feed or visits the announcement detail page  \
**Then** the announcement no longer appears in user-facing feeds and the detail page is
unreachable, but the receipts remain queryable through `receipts_for/2` for audit purposes
(soft-removal via `removed_at`).

### F.Announcements.7 — Authors are excluded from the required-ack set

**Given** an announcement that requires acknowledgement, authored by user A  \
**When** the required-ack list is rendered for the announcement's channel  \
**Then** user A (the author) is excluded from the required-ack set, and an explicit
`acknowledge/2` call by the author returns `{:error, :not_required}`.

### F.Announcements.8 — Acknowledge and mark-read are idempotent

**Given** a user who has already acknowledged (or marked read) an announcement  \
**When** acknowledge or mark-read is called again for the same `(announcement_id, user_id)` pair  \
**Then** the second call returns `{:ok, _}` without creating a duplicate row (idempotent upsert
via the unique index).

### F.Announcements.9 — Receipts bucket every channel member exactly once

**Given** a manager viewing the receipts panel for an announcement they manage  \
**When** the receipts are loaded  \
**Then** every channel member (other than the author) is bucketed into exactly one of:
`acknowledged`, `read_without_acknowledgement`, `unread`, or `off_shift` — with `off_shift`
taking precedence over the other three.

### F.Announcements.10 — Membership is enforced at the context boundary

**Given** a user who is not a member of the announcement's channel (whether through forged DOM
events, URL tampering, or any other route bypass)  \
**When** they attempt to read, acknowledge, pin, unpin, edit, or remove the announcement via the
LiveView or the context API  \
**Then** the context layer rejects the attempt with `{:error, :not_channel_member}` (or
`Ecto.NoResultsError` for reads), independent of route gating.
