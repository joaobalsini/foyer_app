# Recognitions Feature Spec

## Clauses

### F.Recognitions.1
- **Given** an on-shift user looking at the recognitions surface
- **When** they submit a recognition naming a colleague (not themselves), a body, and one or more
  house values
- **Then** the recognition is created with `sender_id` set to the current user, the recipient is
  the named colleague, and the row becomes visible according to its `public` flag.

### F.Recognitions.2
- **Given** an on-shift user composing a recognition
- **When** they pick themselves as the recipient and submit
- **Then** the context rejects the attempt with `{:error, :self_recognition}` and no recognition
  is created.

### F.Recognitions.3
- **Given** the recognitions form
- **When** a sender chooses house values
- **Then** the only accepted values are exactly `care`, `craft`, `warmth`, `discretion`,
  `initiative`, and `excellence`; any other token (e.g. `team`) is rejected by the changeset.

### F.Recognitions.4
- **Given** the recognitions form
- **When** a sender submits with an empty `values` list (or all values cleared)
- **Then** the changeset adds an error on `:values` ("choose at least one value") and the
  recognition is not inserted.

### F.Recognitions.5
- **Given** a sender composing a recognition with `bonus_points > 0`
- **When** the sender is a manager
- **Then** the bonus points are accepted and granted on the ledger; **when** the sender is staff,
  the value is silently normalised to `0` before insert so staff cannot grant bonus points.

### F.Recognitions.6
- **Given** a manager attaching bonus points
- **When** the attached value is one of `0`, `10`, `25`, `50`, `100`
- **Then** the recognition is accepted; **when** the value is any other integer (e.g. `15`), the
  context returns `{:error, :invalid_point_tier}` and no recognition or ledger row is written.

### F.Recognitions.7
- **Given** a successful `give/2` call with `bonus_points > 0`
- **When** the transaction commits
- **Then** the recognition insert, the matching positive `PointEntry` ledger row, and the
  recipient's `points_balance` increment all happen inside a single `Ecto.Multi`; if any step
  fails the whole transaction rolls back and no partial state remains.

### F.Recognitions.8
- **Given** an existing recognition with `bonus_points > 0` and `removed_at IS NULL`
- **When** the author calls `remove_recognition/2` within the grace window
- **Then** `removed_at` and `removed_by_id` are set, a compensating `PointEntry` with
  `delta = -bonus_points` and `reason = "recognition_removed"` is inserted, and the recipient's
  `points_balance` is decremented by the same amount — all inside one `Ecto.Multi`. The removed
  row disappears from `feed_public/0` but the ledger keeps both rows for audit.

### F.Recognitions.9
- **Given** a recognition the current user authored
- **When** less than 15 minutes have passed since `inserted_at`
- **Then** the author can call `update_recognition/3` or `remove_recognition/2`; **when** 15
  minutes or more have passed, both calls return `{:error, :outside_grace_window}` and the
  recognition is unchanged. Non-authors always get `{:error, :unauthorized}`.

### F.Recognitions.10
- **Given** a public recognition (`public = true, removed_at IS NULL`)
- **When** any user reads the public feed, the recipient's profile, the sender's profile, or
  `get_recognition!/2`
- **Then** the recognition is visible to every viewer.

- **Given** a private recognition (`public = false`)
- **When** the viewer is either the sender or the recipient
- **Then** the recognition is visible via `feed_public/0` is filtered out, but `get_recognition!/2`,
  `received_by/2`, and `given_by/2` all return the row.

- **Given** a private recognition
- **When** any third-party viewer (not sender, not recipient) reads the same surfaces
- **Then** the recognition is omitted from `received_by/2`/`given_by/2` and `get_recognition!/2`
  raises `Ecto.NoResultsError`. `/people/:id` and `/recognitions/:id` therefore mask the body
  from third parties.
