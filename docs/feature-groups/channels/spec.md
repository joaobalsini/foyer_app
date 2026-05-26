# Channels — spec

Channels are the operational rooms of the Linden property. They define the audience unit for
announcements, the scope of chat conversations, and the visibility boundary for shift handoffs. A
channel has a `kind` (`:department` or `:general`) and a stable `slug`. Membership is the only
mechanism that grants access: there is no manager override. `Foyer.Channels` owns the data model,
the membership read-API consumed by all other feature groups, and the People Directory surface that
lets on-shift staff see who is in each channel.

## Scope

**In scope**

- `Channel` and `Membership` Ecto schemas, migrations, and validations.
- Membership-scoped read APIs: `list_for_user/1`, `get!/1`, `list_all_with_member_counts/0`,
  `member_count/1`, and `member?/2`.
- Seeding rules: default property channels, manager membership in their operational channels
  (Leadership, Linden · All staff, and their managed department), staff membership scoped to their
  department.
- People Directory LiveView (`PeopleLive`) — the one user-facing surface this group owns. Renders
  a filterable list of staff, department filter options backed by channel membership counts,
  on-shift state, and channel membership pills on the colleague detail view.
- Slug uniqueness and `kind`-dependent structural constraints.
- `Channels.Behavior` behaviour and `ChannelsMock` Mox double wired through `FoyerWeb.LiveDeps`.
- Isolated and route smoke tests for all clauses.

**Out of scope (other groups or v2)**

- Channel administration UI (create / edit / archive channels) — v2.
- Announcement targeting logic and receipt roll-ups — House feature group.
- Chat conversation access and membership-gated room queries — Chat feature group.
- Shift handoff channel selection — Shifts feature group.
- Handoff channel visibility in Today — Today feature group.
- Any PubSub broadcast triggered by membership changes (no membership writes in v1).

---

## Clauses

### F.Channels.1 — Slug uniqueness

**Given** a channel with `slug: "housekeeping-floor-4"` already exists in the database.
**When** an attempt is made to insert a second channel with the same slug.
**Then** the operation fails with a changeset error on `:slug` (the unique index
`:channels_slug_index` is violated), and no second row is created.

### F.Channels.2 — Required fields on Channel

**Given** an empty `Channel` changeset.
**When** `Channel.changeset/2` is called with any combination of missing `:name`, `:slug`, or `:kind`.
**Then** the changeset is invalid and carries a `"can't be blank"` error for each missing required field.

### F.Channels.3 — Kind enum constraint

**Given** a `Channel` changeset.
**When** `kind` is set to any value other than `:department` or `:general`.
**Then** the changeset is invalid and carries an error on `:kind`.

### F.Channels.4 — Membership uniqueness

**Given** a `Membership` row for `(user_id: 1, channel_id: 5)` already exists.
**When** an attempt is made to insert a second `Membership` row with the same pair.
**Then** the operation fails with a changeset error on `[:user_id, :channel_id]`
(the unique index `:channel_memberships_user_id_channel_id_index` is violated).

### F.Channels.5 — Membership required fields

**Given** an empty `Membership` changeset.
**When** `Membership.changeset/2` is called without `:user_id` or `:channel_id`.
**Then** the changeset is invalid with a `"can't be blank"` error for each missing field.

### F.Channels.6 — `list_for_user/1` returns only the caller's channels

**Given** a user who is a member of "Housekeeping · Floor 4" and "All Housekeeping",
and NOT a member of "Leadership".
**When** `Foyer.Channels.list_for_user/1` is called with that user.
**Then** the result contains "Housekeeping · Floor 4" and "All Housekeeping", does NOT contain
"Leadership", and the channels are ordered alphabetically by name.

### F.Channels.7 — `list_for_user/1` returns empty list for a user with no memberships

**Given** a user who has no `Membership` rows.
**When** `Foyer.Channels.list_for_user/1` is called with that user.
**Then** the result is an empty list.

### F.Channels.8 — `get!/1` raises for unknown id

**Given** no channel with id 99999 exists.
**When** `Foyer.Channels.get!/1` is called with 99999.
**Then** an `Ecto.NoResultsError` is raised.

### F.Channels.9 — `list_all_with_member_counts/0` returns all channels with accurate counts

**Given** "Housekeeping · Floor 4" has 4 members and "Leadership" has 3 members.
**When** `Foyer.Channels.list_all_with_member_counts/0` is called.
**Then** the result is a list of `{%Channel{}, non_neg_integer()}` tuples, one per channel,
ordered alphabetically by channel name, with each count matching the actual number of
`Membership` rows for that channel. Channels with no members have a count of `0`.

### F.Channels.10 — `member?/2` accurately reflects membership

**Given** a user who is a member of "All Housekeeping" and NOT a member of "Leadership".
**When** `Foyer.Channels.member?/2` is called with that user and each channel.
**Then** it returns `true` for "All Housekeeping" and `false` for "Leadership".

### F.Channels.11 — `member_count/1` returns the count for a single channel

**Given** "F&B" channel has exactly 2 members.
**When** `Foyer.Channels.member_count/1` is called with the "F&B" channel.
**Then** the result is `2`.

### F.Channels.15 — People Directory renders the desktop list from the design

**Given** a user is authenticated and on shift and navigates to `/people`.
**When** `PeopleLive` renders the `:index` action.
**Then** the page matches `designs/recognition/desktop-people-directory.html`: a "People"
heading, a `{count} colleagues · The Linden` summary, compact filter chips, and a list row for
every seeded user. Each row shows the user's avatar initials, name, title, status text, an
explicit `Message` action, and a `View profile` action only when the current user is allowed by
F.Profile.8 / F.Profile.19. The current user's own row is visually marked with `You`, uses a
`Your profile` action, and does not render a `Message` action. The row itself is not a link, and no
row is missing.

### F.Channels.16 — People Directory shows on-shift pulse for on-shift colleagues

**Given** user A is on shift and user B is not on shift.
**When** `PeopleLive` renders the `:index` action.
**Then** user A's row shows the on-shift indicator (the `foyer-pulse` element with the "On shift"
label) and user B's row does not show it.

### F.Channels.17 — People Directory uses design filters, not row-level channel pills

**Given** a user is a member of "Housekeeping · Floor 4" and "All Housekeeping".
**When** `PeopleLive` renders the directory index.
**Then** the directory shows channel membership as filter options in the `Department` menu, using
real `list_all_with_member_counts/0` data, but does not render channel pills inside each person
row. Row-level channel memberships are reserved for the colleague detail view in F.Channels.22.

### F.Channels.18 — People Directory is gated to on-shift users

**Given** a user is authenticated but off shift.
**When** the user navigates directly to `/people`.
**Then** the user is redirected to `/today` with a flash message indicating they must start their
shift, and the People Directory page is not rendered.

### F.Channels.19 — Channel membership is access-only, no manager override

**Given** a manager user who is NOT a member of "Engineering".
**When** `Foyer.Channels.list_for_user/1` is called for that manager.
**Then** "Engineering" does NOT appear in the result. Manager role alone does not grant
membership in channels the manager was not explicitly added to.

### F.Channels.20 — `list_all_with_member_counts/0` is N+1-free

**Given** any number of channels exist.
**When** `Foyer.Channels.list_all_with_member_counts/0` executes.
**Then** it issues at most 2 database queries regardless of the number of channels (one for
channels, one grouped count query over memberships — or a single join query).

### F.Channels.21 — People Directory filters by department and on-shift state

**Given** a user is authenticated and on shift and navigates to `/people`.
**When** the user selects a channel from the `Department` filter menu.
**Then** only rows for users who have a real `Membership` record in that channel are shown.
All other users are removed from the list. Clearing the filter (or selecting "All") restores
the full unfiltered people list.

**And when** the user selects the `On shift` filter.
**Then** only rows for users whose ids are present in `Shifts.users_on_shift_ids/0` are shown.

### F.Channels.22 — Colleague detail view channel memberships come from a Channels-owned API

**Given** a user navigates to `/people/:id` (the colleague detail view).
**When** `PeopleLive` renders the `:show` action.
**Then** the channel membership pills shown for the target user are loaded via
`Channels.list_for_user/1` (or `LiveDeps.channels().list_for_user/1`), assigned to a
dedicated socket assign owned by the Channels surface. They are NOT sourced from accidental
preloads on `Foyer.Profile.Card` or from `Profile.profile_for/1`.
