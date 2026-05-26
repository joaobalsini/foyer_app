# Profile — spec

Profile is the staff member's personal recognition and rewards page. It renders a
`Foyer.Profile.Card` DTO that orchestrates User, Recognition, and Shift data into a
single typed surface. The page shows the viewer's identity (role, title, languages,
on-shift state), their recognition history (received and given in separate sections),
their Foyer points balance with an earnings breakdown, and a rewards catalog that is
visible but not yet redeemable. Profile is read-only in v1; no writes originate here.
Profile is accessible at `/me` for the current user; `/people/:id` surfaces the same
`profile_card` component for any colleague.

## Scope

**In scope (v1)**
- Identity header: avatar initials, name, title (job title), property code, on-shift
  indicator, languages.
- Recognition received: all recognitions where the viewer is the recipient, ordered
  newest-first. Private recognitions are visible to the recipient on their own profile
  but never visible on a colleague's profile view.
- Recognition given: all recognitions where the viewer is the sender, ordered
  newest-first. On a colleague's profile (PeopleLive :show), given recognitions are
  not shown (own-profile-only surface).
- Stats row: "Recognitions this month" count (received) and "Ack on time" placeholder
  (renders `—` until acknowledgement analytics land in a later group).
- Foyer points balance with an "How you earned them" earnings breakdown list.
- Rewards catalog: static list of reward items, each showing title, cost in points,
  and a "Coming soon" affordance in place of a redemption action.
- Mobile layout (bottom navigation, single-column scroll) matching `designs/profile/mobile-maya-okafor.html`
  and `designs/profile/mobile-recognitions-received.html`.
- Desktop layout matching the side-rail shell from `designs/profile/desktop-charlotte-voss.html`;
  the profile content column follows the same card/section structure as mobile.
- Role-aware rendering: on a manager's own profile, the "Given" section shows
  recognitions they sent; a manager viewing a colleague's profile does not see that
  colleague's "Given" list.
- The `profile_card` component is reused by `PeopleLive :show`.

**Out of scope (v1)**
- Rewards redemption — catalog is visible only; actions render "Coming soon".
- Profile editing (name, languages, notification preferences, shift availability).
- Viewing private recognitions on a colleague's profile (recipient only).
- Acknowledgement analytics (the "Ack on time" stat is a placeholder).
- Points ledger write path (points accumulate only through Recognition events, handled
  by the Recognitions group).
- Push notifications and full notification preference settings.

---

## Clauses

### F.Profile.1 — Identity header renders user attributes
**Given** a staff member is authenticated and on shift, and navigates to `/me`
**When** the page loads
**Then** the page renders the user's initials in a large avatar, their full name in
serif heading, their job title in mono label, their property/location code (e.g.
`LDN·MAY`), and their languages as a comma-separated string (e.g. `EN · FR · YO`).

### F.Profile.2 — On-shift indicator
**Given** the viewer is currently on shift
**When** the profile page renders
**Then** an "On shift" tag with the animated green pulse dot is shown beneath the
identity header.

### F.Profile.3 — Off-shift state renders without pulse
**Given** the viewer's shift has ended (or they have never started a shift)
**When** the profile page renders
**Then** the "On shift" tag is absent; no pulse dot is shown.

### F.Profile.4 — Recognitions received section: own profile
**Given** a staff member navigates to their own profile at `/me`
**When** the page loads
**Then** a "Received" section lists every recognition where the viewer is the
recipient, ordered newest-first, each card showing: the recognition body, the sender's
name and initials avatar, house value tags, any bonus points badge, and the relative
timestamp (e.g. "Yesterday", "Wed 22 Apr").

### F.Profile.5 — Private recognitions visible to recipient on own profile
**Given** a recognition exists with `public: false` and the viewer is the recipient
**When** the viewer loads `/me`
**Then** the private recognition appears in the "Received" section.

### F.Profile.6 — Private recognitions hidden from non-manager colleague reads
**Given** a recognition exists with `public: false`
**When** profile data is loaded for a viewer who is neither the recipient nor an authorized
manager
**Then** the private recognition does not appear in the returned recognition list. Staff users
cannot reach another user's profile UI at `/people/:id`; this context rule protects non-manager
read paths and any future reduced colleague surfaces.

### F.Profile.7 — Recognitions given section: own profile
**Given** a staff member navigates to their own profile at `/me`
**When** the page loads
**Then** a "Given" section lists every recognition where the viewer is the sender,
ordered newest-first, each showing the recipient's name, the recognition body, house
value tags, and any bonus points badge.

### F.Profile.8 — Staff cannot access another user's profile view
**Given** a staff user navigates to a colleague's profile at `/people/:id`
**When** `PeopleLive` handles the `:show` action
**Then** the user is redirected back to `/people` and the colleague's profile card is not
rendered. Staff users may only open their own profile (`/me`, or their own row's `View profile`
action in People).

### F.Profile.9 — Stats row: recognitions this month
**Given** the profile page renders
**When** the stats row is displayed
**Then** the "Recognitions this month" tile shows the count of recognitions received
where `inserted_at` falls within the current calendar month.

### F.Profile.10 — Stats row: ack on time placeholder
**Given** the profile page renders
**When** the "Ack on time" stat tile is displayed
**Then** the tile renders the literal value `—` (an em-dash placeholder), indicating
this metric is not yet implemented.

### F.Profile.11 — Foyer points balance
**Given** the profile page renders
**When** the Foyer points section is displayed
**Then** the section shows the heading "Foyer points", the user's current
`points_balance` as a large number, and the subtitle "Earned through recognition.
Trade for time, meals, the spa, or pass it on as a donation."

### F.Profile.12 — Points earnings breakdown
**Given** the profile page renders
**When** the "How you earned them" disclosure is present
**Then** it lists the recognitions that contributed points to the balance (those where
`bonus_points > 0`), each row showing sender initials, the recognition body snippet,
and the points amount. If no point-bearing recognitions exist, the disclosure is
hidden or shows an empty state.

### F.Profile.13 — Rewards catalog renders all items
**Given** the profile page renders
**When** the rewards catalog section is displayed
**Then** every reward item in the catalog is shown, each with: an icon or glyph, the
reward title, the cost in points, and a brief description line.

### F.Profile.14 — Rewards catalog items are non-redeemable
**Given** any reward item in the catalog
**When** the user interacts with or clicks on a reward item
**Then** no redemption action is triggered; the item either has no interactive element
or renders a "Coming soon" label in place of a redeem button. No form submission or
event handler for redemption exists in v1.

### F.Profile.15 — Rewards catalog: insufficient-points affordance
**Given** a reward item whose cost exceeds the viewer's `points_balance`
**When** the catalog renders
**Then** the item's cost label is visually dimmed or the item is styled differently to
communicate that the viewer does not currently have enough points, without blocking
visibility of the item.

### F.Profile.16 — Mobile layout matches design
**Given** the profile page is rendered at a phone-width viewport (≤ 640 px)
**When** the page is displayed
**Then** the layout matches `designs/profile/mobile-recognitions-received.html`:
single-column scroll, identity header at top, stats row as a two-column grid, stacked
Received/Given recognition sections, points section, rewards catalog, and the fixed
bottom navigation (Today / House / Chat / Me).

### F.Profile.17 — Desktop layout uses side-rail shell
**Given** the profile page is rendered at a desktop-width viewport (≥ 768 px)
**When** the page is displayed
**Then** the `FoyerComponents.desktop_rail` component is rendered in both `ProfileLive`
(`/me`) and `PeopleLive :show` (`/people/:id`), the profile content occupies the main
content column, and the bottom navigation is hidden (consistent with all other desktop
surfaces). The side-rail is not injected by `Layouts.app` — each LiveView is
responsible for including it.

### F.Profile.18 — Profile page is not accessible off-shift
**Given** a user's shift has ended (they are off-shift)
**When** they attempt to navigate to `/me`
**Then** they are redirected to `/today` with a flash message, because `/me` is gated
by the `:ensure_on_shift` on_mount hook.

### F.Profile.19 — Managers can open full profiles from People
**Given** a manager is on-shift and navigates to `/people/:id`, or clicks a row's
`View profile` action
**When** the page loads for a valid colleague id
**Then** `PeopleLive` renders the same full `profile_card` treatment used by `/me`,
including received recognitions, private recognitions, given recognitions, points, and
rewards. Non-manager staff do not see `View profile` actions for other users.

### F.Profile.20 — Empty recognitions state
**Given** a user has received no recognitions
**When** their profile page renders
**Then** the "Received" section renders an empty-state message (e.g. "No recognitions
yet") rather than a blank list, and the "Recognitions this month" stat shows `0`.

### F.Profile.21 — House value tags on recognition cards
**Given** a recognition includes one or more house values (e.g. `care`, `craft`,
`discretion`)
**When** the recognition card renders in the Received or Given section
**Then** each house value appears as a tag on the card (e.g. `CARE`, `CRAFT`).

### F.Profile.22 — Bonus points badge on recognition cards
**Given** a recognition was sent with `bonus_points > 0`
**When** the recognition card renders
**Then** a badge showing the points amount (e.g. `+25 pts`) is visible on the card.

### F.Profile.23 — Private-recognition filtering is enforced at the context boundary
**Given** a viewer is not the recipient of a recognition with `public: false`
**When** `Foyer.Profile.profile_for(subject, viewer)` is called with a different subject
and viewer
**Then** the returned `Card.received` list does not contain any recognition with
`public: false`, and `Card.given` is empty. This rule is asserted by a unit test
against the context directly, not only by a LiveView render test.

### F.Profile.24 — Points balance may not reconcile with bonus-point earnings breakdown
**Given** the profile page renders the "How you earned them" breakdown
**When** the breakdown lists recognitions with `bonus_points > 0`
**Then** the UI labels the section as bonus-point earnings and does not imply that the
sum of those amounts equals `points_balance`. `points_balance` is the authoritative
balance; the earnings list is illustrative. If no point-bearing recognitions exist, the
disclosure is hidden or shows an empty state.

### F.Profile.25 — Property code comes from application config, not the User schema
**Given** the identity header renders the property/location code (e.g. `LDN·MAY`)
**When** the page loads
**Then** the property code is read from application config
(`Application.get_env(:foyer, :property_code, "LDN·MAY")`), not from a user schema
field. In the v1 POC, all users share the same single-property code. Adding a per-user
or per-channel property code is a v2 concern.

### F.Profile.26 — `/me` is only the current user's own profile
**Given** an authenticated on-shift user navigates to `/me`
**When** `ProfileLive` loads the profile card
**Then** the profile is loaded from the current scope's user only; no route parameter can
select another user's full self-profile. Managers access other users' full profiles through
`/people/:id`; staff users can only access their own full profile.
