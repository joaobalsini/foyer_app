# Announcements Feature Spec

## Clauses

### F.Announcements.1

- **Given** a manager who is a member of channel X
- **When** they publish an announcement to channel X
- **Then** the announcement is created with the manager as author, scoped to channel X, and persists with the requested `requires_ack` setting

### F.Announcements.2

- **Given** a staff user (non-manager)
- **When** they attempt to create an announcement — whether by visiting `/announcements/new` or by submitting a forged compose payload
- **Then** the compose route redirects them away with a flash, and the context-level write rejects the attempt with `{:error, :unauthorized}` so no announcement is persisted

### F.Announcements.3

- **Given** the author of an announcement published less than 15 minutes ago
- **When** they edit the title, body, audience, or `requires_ack` setting
- **Then** the update succeeds and the new values are persisted

### F.Announcements.4

- **Given** an announcement whose 15-minute grace window has expired (or a non-author attempting the action)
  - **When** the author attempts to edit the announcement
  - **Then** the update is rejected with `{:error, :outside_grace_window}` (or `{:error, :unauthorized}` for non-authors) and the announcement is unchanged
  - **When** the author attempts to remove the announcement
  - **Then** the removal is rejected with the same error and the announcement is unchanged

### F.Announcements.5

- **Given** a manager who is a member of channel X
- **When** they pin (or unpin) an announcement that lives in channel X
- **Then** the announcement's `pinned_at` is set (or cleared), and the rendered detail page swaps the pin/unpin affordance to reflect the new state

### F.Announcements.6

- **Given** an announcement that has been removed (its author called remove within the grace window)
- **When** any channel member loads their feed or visits the announcement detail page
- **Then** the announcement no longer appears in user-facing feeds and the detail page is unreachable, but the receipts remain queryable through `receipts_for/2` for audit purposes (soft-removal via `removed_at`)

### F.Announcements.7

- **Given** an announcement that requires acknowledgement, authored by user A
- **When** the required-ack list is rendered for the announcement's channel
- **Then** user A (the author) is excluded from the required-ack set, and an explicit `acknowledge/2` call by the author returns `{:error, :not_required}`

### F.Announcements.8

- **Given** a user who has already acknowledged (or marked read) an announcement
- **When** acknowledge or mark-read is called again for the same `(announcement_id, user_id)` pair
- **Then** the second call returns `{:ok, _}` without creating a duplicate row (idempotent upsert via the unique index)

### F.Announcements.9

- **Given** a manager viewing the receipts panel for an announcement they manage
- **When** the receipts are loaded
- **Then** every channel member (other than the author) is bucketed into exactly one of: `acknowledged`, `read_without_acknowledgement`, `unread`, or `off_shift` — with `off_shift` taking precedence over the other three

### F.Announcements.10

- **Given** a user who is not a member of the announcement's channel (whether through forged DOM events, URL tampering, or any other route bypass)
- **When** they attempt to read, acknowledge, pin, unpin, edit, or remove the announcement via the LiveView or the context API
- **Then** the context layer rejects the attempt with `{:error, :not_channel_member}` (or `Ecto.NoResultsError` for reads), independent of route gating
