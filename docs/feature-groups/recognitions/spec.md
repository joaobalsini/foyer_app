# Recognitions — spec

Recognitions is Foyer's peer-recognition surface. Staff and managers thank
colleagues by sending a short note tagged with one or more house values
(`care`, `craft`, `warmth`, `discretion`, `initiative`, `excellence`).
Managers can additionally attach bonus points from a fixed tier
(`0 / 10 / 25 / 50 / 100`), which post atomically to the recipient's
`points_balance` and to an immutable `PointEntry` ledger via `Ecto.Multi`.
Authors get a 15-minute grace window to edit or remove what they sent;
removals reverse the points through a compensating ledger row so the audit
trail stays complete. Recognitions can be public (visible to everyone on the
feed) or private (visible only to sender and recipient); the visibility rule
is enforced at the context boundary so every read path — public feed,
profile listings, single-recognition fetches — honours it consistently.

## Scope

**In scope**

- Peer recognition compose form: pick a colleague (not self), write a body,
  tag one or more house values, choose public / private.
- House value vocabulary fixed to `care`, `craft`, `warmth`, `discretion`,
  `initiative`, `excellence`; any other token is rejected.
- Manager-only bonus points fieldset on the compose form, restricted to the
  `0 / 10 / 25 / 50 / 100` tier; staff submissions are silently normalised
  to `0`.
- Transactional point ledger: `give/2` writes the recognition row, a positive
  `PointEntry`, and the recipient's `points_balance` increment in one
  `Ecto.Multi`.
- Soft removal via `remove_recognition/2`: sets `removed_at` /
  `removed_by_id`, inserts a compensating `PointEntry` with
  `reason = "recognition_removed"`, and decrements `points_balance` — again
  in one `Ecto.Multi`.
- 15-minute author grace window for `update_recognition/3` and
  `remove_recognition/2`. Non-authors are rejected with `:unauthorized`;
  late authors get `:outside_grace_window`.
- Public / private visibility enforced at the context boundary across
  `feed_public/0`, `received_by/2`, `given_by/2`, and `get_recognition!/2`.
- LiveView surfaces `/recognitions/new`, `/recognitions/:id`, and
  `/recognitions/:id/edit` rendering the compose form, detail view, and edit
  form respectively. There is no standalone recognitions index route; public
  recognition browsing happens through The House, and recent received
  recognition entry points also appear on Today.

**Out of scope**

- Hard delete of recognitions or `PointEntry` rows — the ledger is
  append-only and removals are soft.
- Custom bonus-point amounts outside the `0 / 10 / 25 / 50 / 100` tier.
- Staff-granted bonus points; the role gate is enforced server-side, not
  just UI-side.
- Editing the recipient or value list after the grace window closes.
- Notifications, digests, or push delivery of recognition events.
- Redemption of points — the rewards catalog lives in the Profile feature
  group and is read-only in v1.

---

## Clauses

### F.Recognitions.1 — Send a recognition to a colleague

**Given** an on-shift user looking at the recognitions surface

**When** they submit a recognition naming a colleague (not themselves), a
body, and one or more house values

**Then** the recognition is created with `sender_id` set to the current
user, the recipient is the named colleague, and the row becomes visible
according to its `public` flag. The sender is redirected to the recognition's
show page with a confirmation toast.

### F.Recognitions.2 — Self-recognition is rejected

**Given** an on-shift user composing a recognition

**When** they pick themselves as the recipient and submit

**Then** the context rejects the attempt with `{:error, :self_recognition}`
and no recognition is created.

### F.Recognitions.3 — House value vocabulary is fixed

**Given** the recognitions form

**When** a sender chooses house values

**Then** the only accepted values are exactly `care`, `craft`, `warmth`,
`discretion`, `initiative`, and `excellence`; any other token (e.g. `team`)
is rejected by the changeset.

### F.Recognitions.4 — At least one house value is required

**Given** the recognitions form

**When** a sender submits with an empty `values` list (or all values
cleared)

**Then** the changeset adds an error on `:values` ("choose at least one
value") and the recognition is not inserted.

### F.Recognitions.5 — Bonus points are manager-only

**Given** a sender composing a recognition with `bonus_points > 0`

**When** the sender is a manager

**Then** the bonus points are accepted and granted on the ledger; when the
sender is staff, the value is silently normalised to `0` before insert so
staff cannot grant bonus points.

### F.Recognitions.6 — Bonus points must match the fixed tier

**Given** a manager attaching bonus points

**When** the attached value is one of `0`, `10`, `25`, `50`, `100`

**Then** the recognition is accepted; when the value is any other integer
(e.g. `15`), the context returns `{:error, :invalid_point_tier}` and no
recognition or ledger row is written.

### F.Recognitions.7 — Recognition and ledger commit atomically

**Given** a successful `give/2` call with `bonus_points > 0`

**When** the transaction commits

**Then** the recognition insert, the matching positive `PointEntry` ledger
row, and the recipient's `points_balance` increment all happen inside a
single `Ecto.Multi`; if any step fails the whole transaction rolls back and
no partial state remains.

### F.Recognitions.8 — Removal soft-deletes and reverses points

**Given** an existing recognition with `bonus_points > 0` and
`removed_at IS NULL`

**When** the author calls `remove_recognition/2` within the grace window

**Then** `removed_at` and `removed_by_id` are set, a compensating
`PointEntry` with `delta = -bonus_points` and
`reason = "recognition_removed"` is inserted, and the recipient's
`points_balance` is decremented by the same amount — all inside one
`Ecto.Multi`. The removed row disappears from `feed_public/0` but the
ledger keeps both rows for audit.

### F.Recognitions.9 — Grace window gates edits and removals

**Given** a recognition the current user authored

**When** less than 15 minutes have passed since `inserted_at`

**Then** the author can call `update_recognition/3` or
`remove_recognition/2`; when 15 minutes or more have passed, both calls
return `{:error, :outside_grace_window}` and the recognition is unchanged. Successful edits
redirect back to the recognition show page.
On the detail page, the author still sees the Edit and Remove actions after
the grace window, but they are disabled with a tooltip explaining the
15-minute limit. Non-authors always get `{:error, :unauthorized}`.

### F.Recognitions.10 — Public / private visibility is enforced at the boundary

**Given** a public recognition (`public = true, removed_at IS NULL`)

**When** any user reads the public feed, the recipient's profile, the
sender's profile, or `get_recognition!/2`

**Then** the recognition is visible to every viewer.

The House renders a `View` action only for recognitions where the current user
is the sender or recipient; Today renders `View` actions for the current user's
recent received recognitions. Both actions navigate directly to
`/recognitions/:id`.

**Given** a private recognition (`public = false`)

**When** the viewer is either the sender or the recipient

**Then** the recognition is filtered out of `feed_public/0`, but
`get_recognition!/2`, `received_by/2`, and `given_by/2` all return the row.

**Given** a private recognition

**When** any third-party viewer (not sender, not recipient) reads the same
surfaces

**Then** the recognition is omitted from `received_by/2` / `given_by/2` and
`get_recognition!/2` raises `Ecto.NoResultsError`. `/people/:id` and
`/recognitions/:id` therefore mask the body from third parties.
