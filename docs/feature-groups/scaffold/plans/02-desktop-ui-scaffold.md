# Plan 02 — Desktop UI scaffold

Status: revised after Codex review (v2)
Scope: desktop-responsive layouts for every surface that has a desktop
mock (Chat, House, Profile, Recognition, People Directory) plus an
inferred desktop layout for Today.
Spec: none — see [`../spec.md`](../spec.md)
Review: [`02-desktop-ui-scaffold-review.md`](./02-desktop-ui-scaffold-review.md)

---

## Revision log

**v2 — addressed Codex review of 2026-05-25.** Key changes (see review doc for
full rationale):

- §4.1: replaced `<.form action={~p"/session"} method="delete">` sign-out
  wrapper with `<.link method="delete" href={~p"/session"}>`, which Phoenix
  renders as a CSRF-protected form automatically. The old `<.form>` inside a
  `Phoenix.Component` without a backing struct was not guaranteed to emit a
  CSRF token.
- §5.5 / §5.6 removed entirely: `weekly-digest` and `my-announcements` are
  new House features (new routes, new actions, new context functions, new
  tests) — not desktop layout work. They are **deferred to a future House
  feature-group plan** with proper design artifacts, spec coverage, and
  authorization contract. The router gains no new announcement routes in
  this plan.
- §5.7 / §8.4: `:show` `handle_params/3` now loads the full inbox stream
  in addition to the room data, so a direct load or refresh of
  `/chat/:conversation_id` does not produce an empty left panel at desktop
  widths. Codex's dual-load proposal (load both `inbox_for/1` and room data
  inside `load_conversation/2`) was adopted; a single-LiveView consolidation
  was not required because `ChatLive` already handles all chat actions.
- §9.2: removed the smuggled-route tests (`weekly digest` / `my
  announcements`). Confirmed that `:ensure_manager` does **not** exist as an
  on_mount hook in `lib/foyer_web/user_auth.ex` — the file has only
  `:mount_public`, `:ensure_authenticated`, and `:ensure_on_shift`. Since
  the routes are removed, no manager-redirect test is needed.
- Nits addressed: §4.1 channel links now document that channel IDs are not
  yet passed (a non-goal); §12.5 CSRF concern downgraded from a manual-token
  risk to a resolved fact (replaced with `<.link method="delete">`); §12.3
  reworded as unvalidated risk (no mock files found in `designs/`); §8
  summary tightened to call out state changes explicitly; §11 step 14
  extended to include a 768 px / 820 px tablet pass.

**v1 — initial draft (2026-05-25).** Written against the mobile scaffold
implementation (plan 01, v2) and the desktop HTML mocks in `designs/`.
The Today desktop layout is inferred — no mock exists.

---

## 1. Goal & non-goals

### Goal

Every Foyer surface renders its designed desktop layout at `md:` (768 px)
and above — without changing any mobile layout, routing, LiveView modules,
schemas, or context functions. Specifically:

- A fixed left side-rail replaces the mobile bottom-nav at `md:` and wider.
  The side-rail shows the Foyer wordmark, property context ("The Linden"),
  user avatar + name, and four nav destinations (Today / House / Chat / Me).
  Channels are listed as a secondary group below the main nav. Sign-out lives
  at the bottom.
- The bottom-nav is hidden at `md:` and wider (`md:hidden` on the
  `<nav class="foyer-bottom-nav">`).
- Each surface gains a two-column layout at `md:`: the left column (fixed
  side-rail, ~15 rem wide) and a scrollable right content column.
- House and Recognition surfaces gain a second content panel at `lg:` (1024 px)
  for live-preview and receipt detail, matching the mocks.
- The inferred Today desktop shows the same briefing content in a wider centred
  card inside the two-column shell, without a Today-specific mock.
- All existing DOM IDs, LiveView event handlers, context calls, and smoke
  tests continue to pass unchanged.

### Non-goals (deferred, matching mobile plan deferrals)

The following are still out of scope and belong in per-feature-group plans:

- **PubSub-driven live updates.** Chat and House still load from DB on
  `handle_params`; no new broadcasts.
- **Real write paths.** Compose, give recognition, send message are still
  stubbed at `{:error, :not_implemented}`. The desktop compose panel renders
  the form; submission behaviour is unchanged.
- **Audience-targeting, ack roll-up, points ledger, scheduled publish.** Still
  deferred to feature groups.
- **Accessibility audit.** Basic ARIA landmarks and keyboard-accessible side-rail
  links are added (see §11), but no full WCAG AA contrast audit or screen-reader
  pass.
- **Dark mode.** The design is light-only; no `prefers-color-scheme` additions.
- **Tablet portrait collapse (narrow desktop).** At 768–900 px the side-rail
  is shown in full; a collapsed icon-only rail variant is acknowledged as a
  risk (§13) but deferred.
- **Inline side-rail channel switching.** Clicking a channel in the rail
  navigates to `/chat` (the inbox). Passing the channel's conversation ID to
  navigate directly to `/chat/:conversation_id` is deferred — it requires
  resolving the channel→conversation mapping, which belongs in the Chat
  feature-group plan. The `<.link navigate={~p"/chat"}>` in the HEEx skeleton
  reflects this; no event handler is added in the scaffold.
- **Today desktop mock.** No mock exists; the layout is inferred. See §5.1 for
  the explicit wireframe and §13 for the risk flag.
- **Production fonts.** `@font-face` for Instrument Serif and JetBrains Mono
  remains a follow-up branding ticket (per mobile plan implementation review).

---

## 2. Breakpoint strategy

**Use `md:` (768 px) as the primary breakpoint for the side-rail.**

Rationale:

- All desktop mocks show a 15 rem side-rail. At 768 px (the canonical `md:`
  breakpoint in Tailwind) a 15 rem (~240 px) rail plus a minimum ~500 px
  content area is still comfortable. Going to `lg:` (1024 px) would leave the
  desktop layout invisible on iPads in landscape (a common managers' device)
  and on smaller laptops.
- The mobile plan (§2.5, §8) already comments `@media (min-width: 768px)` as
  the point where bottom-nav hides. This plan makes that comment concrete.
- The People Directory (already partly responsive at `md:`) uses the same
  breakpoint, so `md:` is the established project convention.

**Use `lg:` (1024 px) for the secondary content panel** (House compose
preview, recognition sent-receipt column). The wider two-column content area
only makes sense when the viewport is wide enough for three zones (side-rail
+ main content + detail panel). At `md:` those surfaces remain single-column
within the content area.

---

## 3. Visual system additions

No new palette tokens are needed — the design mocks use the same warm-cream /
forest / claret / brass vocabulary already in `assets/css/app.css`. No new
migrations. No new schemas.

New CSS added to `assets/css/app.css`:

### 3.1 Shell layout primitives

```css
/* ---------------------------------------------------------------------------
   Desktop shell. Activated at md: via class toggling.
   Side-rail is 15 rem (240 px) fixed on the left.
   Content area fills the rest, scrolls independently.
   --------------------------------------------------------------------------- */

/* The top-level shell wrapper: side-rail + content side by side at md:. */
/* Applied to the <main> element in every LiveView (replaces .foyer-root at md:). */
.foyer-shell {
  background: var(--foyer-cream);
  min-height: 100vh;
}

/* Mobile: bottom-nav padding. Desktop: no bottom padding (side-rail, not bottom-nav). */
.foyer-content {
  padding-bottom: 5rem; /* room for bottom-nav on mobile */
}

@media (min-width: 768px) {
  .foyer-shell {
    display: flex;
    flex-direction: row;
  }

  .foyer-content {
    flex: 1;
    min-width: 0;       /* prevents flex children from overflowing */
    padding-bottom: 0;
    overflow-y: auto;
    max-height: 100vh;
  }
}

/* ---------------------------------------------------------------------------
   Side-rail.
   Hidden at < md:; fixed (sticky) column at md:+.
   --------------------------------------------------------------------------- */
.foyer-rail {
  display: none;
}

@media (min-width: 768px) {
  .foyer-rail {
    display: flex;
    flex-direction: column;
    width: 15rem;
    min-height: 100vh;
    position: sticky;
    top: 0;
    flex-shrink: 0;
    background: var(--foyer-cream);
    border-right: 1px solid var(--foyer-rule);
    padding: 1.25rem 0;
    gap: 0;
    overflow-y: auto;
  }
}

/* Rail wordmark / header block */
.foyer-rail__header {
  padding: 0 1rem 1rem;
  border-bottom: 1px solid var(--foyer-rule);
  margin-bottom: 0.75rem;
}

/* Rail nav item */
.foyer-rail__item {
  display: flex;
  align-items: center;
  gap: 0.6rem;
  padding: 0.55rem 1rem;
  border-radius: 0;
  text-decoration: none;
  font-family: "JetBrains Mono", ui-monospace, monospace;
  font-size: 0.72rem;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: var(--foyer-ink-soft);
  background: transparent;
  border: 0;
  cursor: pointer;
  width: 100%;
  text-align: left;
  transition: background 100ms ease, color 100ms ease;
}

.foyer-rail__item:hover {
  background: var(--foyer-cream-deep);
  color: var(--foyer-ink);
}

.foyer-rail__item[aria-current="page"],
.foyer-rail__item.is-active {
  color: var(--foyer-forest-deep);
  font-weight: 600;
}

/* Channels sub-group inside rail */
.foyer-rail__section {
  padding: 0.5rem 1rem 0.25rem;
  margin-top: 0.5rem;
}

/* Rail footer (user + sign-out) */
.foyer-rail__footer {
  margin-top: auto;
  padding: 0.75rem 1rem 0;
  border-top: 1px solid var(--foyer-rule);
}

/* ---------------------------------------------------------------------------
   Hide bottom-nav at desktop widths.
   --------------------------------------------------------------------------- */
@media (min-width: 768px) {
  .foyer-bottom-nav {
    display: none;
  }
}

/* ---------------------------------------------------------------------------
   Desktop two-column content grid (used inside .foyer-content at lg:).
   Used by House and Recognition for the compose + preview split.
   --------------------------------------------------------------------------- */
.foyer-content-cols {
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
  padding: 1.5rem;
}

@media (min-width: 1024px) {
  .foyer-content-cols {
    display: grid;
    grid-template-columns: 1fr 1fr;
    align-items: start;
    gap: 2rem;
  }
}
```

### 3.2 What is NOT changing

- No new CSS custom-property tokens.
- No `@apply` (forbidden by AGENTS.md).
- No daisyUI reintroduction.
- The `.foyer-root` and `.foyer-scroll` classes remain for mobile; the desktop
  shell wraps around them via new parent elements in the LiveView templates.

---

## 4. Shared chrome — the desktop side-rail

### 4.1 New component: `FoyerWeb.FoyerComponents.desktop_rail/1`

Added to `lib/foyer_web/components/foyer_components.ex`. The component is
rendered inside every LiveView template at desktop widths. On mobile it is
invisible (the `.foyer-rail` CSS rule sets `display: none` below `md:`).

```elixir
attr :active, :atom, required: true, values: [:today, :house, :chat, :me]
attr :current_scope, FoyerWeb.Scope, required: true
attr :channels, :list, default: []  # list of %Channel{} for the user
```

The rendered structure (HEEx skeleton):

```heex
<nav id="desktop-rail" class="foyer-rail" aria-label="Main navigation">
  <%!-- Wordmark --%>
  <div class="foyer-rail__header">
    <div class="foyer-serif text-xl">Foyer</div>
    <div class="foyer-mono">{@current_scope.user.department}</div>
  </div>

  <%!-- Primary nav --%>
  <.link id="rail-nav-today" navigate={~p"/today"}
    class={["foyer-rail__item", @active == :today && "is-active"]}
    aria-current={if @active == :today, do: "page", else: nil}>
    <.icon name="hero-home" class="size-4" /> Today
  </.link>

  <%= if @current_scope.on_shift? do %>
    <.link id="rail-nav-house" navigate={~p"/house"}
      class={["foyer-rail__item", @active == :house && "is-active"]}
      aria-current={if @active == :house, do: "page", else: nil}>
      <.icon name="hero-building-library" class="size-4" /> House
    </.link>
    <.link id="rail-nav-chat" navigate={~p"/chat"}
      class={["foyer-rail__item", @active == :chat && "is-active"]}
      aria-current={if @active == :chat, do: "page", else: nil}>
      <.icon name="hero-chat-bubble-left-right" class="size-4" /> Chat
    </.link>
    <.link id="rail-nav-me" navigate={~p"/me"}
      class={["foyer-rail__item", @active == :me && "is-active"]}
      aria-current={if @active == :me, do: "page", else: nil}>
      <.icon name="hero-user-circle" class="size-4" /> Me
    </.link>
  <% else %>
    <button id="rail-nav-house" type="button" disabled aria-disabled="true"
      class="foyer-rail__item opacity-40 cursor-not-allowed">
      <.icon name="hero-building-library" class="size-4" /> House
    </button>
    <button id="rail-nav-chat" type="button" disabled aria-disabled="true"
      class="foyer-rail__item opacity-40 cursor-not-allowed">
      <.icon name="hero-chat-bubble-left-right" class="size-4" /> Chat
    </button>
    <button id="rail-nav-me" type="button" disabled aria-disabled="true"
      class="foyer-rail__item opacity-40 cursor-not-allowed">
      <.icon name="hero-user-circle" class="size-4" /> Me
    </button>
  <% end %>

  <%!-- Channels sub-group (shown when list is not empty) --%>
  <%= if @channels != [] do %>
    <div class="foyer-rail__section">
      <div class="foyer-mono">Channels</div>
    </div>
    <.link :for={ch <- @channels}
      navigate={~p"/chat"}
      class="foyer-rail__item pl-6"
      id={"rail-channel-#{ch.id}"}>
      # {ch.name}
    </.link>
  <% end %>

  <%!-- Footer: current user + sign-out --%>
  <div class="foyer-rail__footer">
    <div class="flex items-center gap-2 mb-2">
      <FoyerWeb.FoyerComponents.avatar initials={@current_scope.user.initials} size={:sm} />
      <div>
        <div class="foyer-serif text-sm">{@current_scope.user.name}</div>
        <div class="foyer-mono">{@current_scope.user.title}</div>
      </div>
    </div>
    <.link method="delete" href={~p"/session"} class="foyer-rail__item" id="rail-sign-out">
      <.icon name="hero-arrow-right-on-rectangle" class="size-4" /> Sign out
    </.link>
  </div>
</nav>
```

**Important constraints:**

- Stable DOM IDs: `#desktop-rail`, `#rail-nav-today`, `#rail-nav-house`,
  `#rail-nav-chat`, `#rail-nav-me`. The smoke test extension asserts on these.
- When `on_shift?` is false, House / Chat / Me render as `<button disabled>`,
  matching the same belt-and-braces discipline as `bottom_nav/1`.
- Channels list is optional (`default: []`). Most LiveViews pass an empty list;
  ChatLive passes the user's channels after loading them in `handle_params/3`.
- The component does not do its own DB call. Channels are pre-loaded by the
  LiveView's `handle_params/3` to keep the component pure and testable in
  isolation. For LiveViews that do not load channels (Today, Profile, People),
  the channels list is simply empty and the section is not rendered.

### 4.2 Where `bottom_nav/1` hides

The CSS rule `@media (min-width: 768px) { .foyer-bottom-nav { display: none; } }`
(added in §3.1) handles this globally. No per-LiveView change is needed. The
`bottom_nav/1` component remains in every template for mobile; the CSS hides it
at desktop widths. This is the simplest, most resilient approach — there is no
conditional render logic needed in Elixir.

### 4.3 Shell wrapper structure change

Every LiveView currently renders:

```heex
<main class="foyer-root">
  <div class="foyer-scroll" id="<surface>">
    ...content...
    <FoyerComponents.bottom_nav ... />
  </div>
</main>
```

After this plan, every LiveView renders:

```heex
<main class="foyer-shell">
  <FoyerComponents.desktop_rail active={:today} current_scope={@current_scope} />
  <div class="foyer-content">
    <div class="foyer-scroll" id="<surface>">
      ...content (unchanged)...
      <FoyerComponents.bottom_nav ... />
    </div>
  </div>
</main>
```

The `foyer-root` class is **replaced** by `foyer-shell` on `<main>`, and a
new `<div class="foyer-content">` wrapper is inserted between `<main>` and the
existing `<div class="foyer-scroll">`. This is the only structural change to
every LiveView template. Mobile rendering is preserved: on small screens,
`.foyer-rail` is `display:none`, `.foyer-content` has `padding-bottom: 5rem`
for the bottom-nav, and the content scrolls as before.

---

## 5. Layout topology per surface

The ASCII wireframes below describe the **desktop layout only** (what the user
sees at `md:+`). Mobile layouts are unchanged in all cases.

### 5.1 Today (inferred — no desktop mock exists)

**This layout is inferred.** There is no `today/desktop-*.html` mock. The
design language observed across every other desktop mock is: 15 rem side-rail
on the left, warm-cream content area on the right, content max-width ~48 rem
centred in the content area. The Today briefing cards are naturally narrow
(phone-width is appropriate for reading briefing items); wrapping them in a
centred max-width column on desktop is the minimal-change approach.

Proposed layout:

```
┌──────────────┬─────────────────────────────────────────────────┐
│  Side-rail   │  Content column (max-w-2xl centred)             │
│  (15 rem)    │                                                  │
│              │  GOOD MORNING MAYA                               │
│  Today       │  Housekeeping · Floor 4  [search] [bell]        │
│  House       │                                                  │
│  Chat        │  ┌──────────────────────────────────────────┐   │
│  Me          │  │  On shift · Senior Housekeeper    End »  │   │
│              │  │  Handoff from your last shift            │   │
│  Channels    │  │  ┌────────────────────────────────────┐  │   │
│  # Floor 4   │  │  │ PINNED · ACTION  Suite 412 ...     │  │   │
│  # Linden    │  │  └────────────────────────────────────┘  │   │
│              │  └──────────────────────────────────────────┘   │
│  CV ·        │                                                  │
│  Sign out    │  [End-shift modal appears inline below when      │
│              │   live_action == :end_shift]                     │
└──────────────┴─────────────────────────────────────────────────┘
```

Concrete changes to `TodayLive.render/1`:

- `<main class="foyer-root">` → `<main class="foyer-shell">`.
- Insert `<FoyerComponents.desktop_rail active={:today} current_scope={@current_scope} />`.
- Insert `<div class="foyer-content">` wrapper.
- Existing `<div class="foyer-scroll" id="today">` gains `md:max-w-2xl md:mx-auto`.
- No `handle_params/3` changes. No new data loads.

**Flag for Codex review:** This is the one layout inferred without a mock. The
`md:max-w-2xl md:mx-auto` centred approach is conservative. An alternative
would be to show a second panel (e.g. the recognition feed) alongside the
briefing at `lg:`, but no mock justifies this. The plan chooses the
single-column centred approach until a mock is produced.

### 5.2 House — feed (HouseLive :index)

Mocks: `desktop-announcement-published-undo.html`, `desktop-my-announcements.html`.

```
┌──────────────┬─────────────────────────────────────────────────┐
│  Side-rail   │  The House          [Compose button — manager]  │
│              │  ─────────────────────────────────────────────  │
│              │  [All] [Announcements] [Recognition]            │
│              │                                                  │
│              │  ┌────────────────────────────────────────────┐ │
│              │  │ PINNED  Suite 412 — Allergy...             │ │
│              │  │ Charlotte Voss · All Housekeeping          │ │
│              │  └────────────────────────────────────────────┘ │
│              │  ┌────────────────────────────────────────────┐ │
│              │  │  Recognition for Maya Okafor ...          │ │
│              │  └────────────────────────────────────────────┘ │
└──────────────┴─────────────────────────────────────────────────┘
```

Desktop HouseLive uses the full content column for the feed — no second panel
at `md:`. The content column is bounded by `md:max-w-3xl` for readability.

Concrete changes to `HouseLive.render/1`:

- `<main class="foyer-root">` → `<main class="foyer-shell">`.
- Insert `<FoyerComponents.desktop_rail active={:house} current_scope={@current_scope} />`.
- Insert `<div class="foyer-content">`.
- Existing `<div class="foyer-scroll" id="house">` gains `md:max-w-3xl`.

### 5.3 House — compose (AnnouncementLive :new and :edit)

Mock: `desktop-compose.html`.

```
┌──────────────┬─────────────────────────────────────────┬──────────────────┐
│  Side-rail   │  Compose an announcement                │  Preview column  │
│              │  ──────────────────────────────────     │  (lg: only)      │
│              │  Title input                            │                  │
│              │  Body textarea                          │  ┌──────────────┐│
│              │  Audience select                        │  │ Suite 412 …  ││
│              │  Options: Pin / Ack / Translate         │  │ Charlotte    ││
│              │  [Publish]                              │  └──────────────┘│
└──────────────┴─────────────────────────────────────────┴──────────────────┘
```

At `lg:` the form and preview sit side by side using `.foyer-content-cols`.
At `md:` they stack (single column).

Concrete changes to `AnnouncementLive.render/1` (`:new` and `:edit` clauses):

- Same shell + rail wrapper as above.
- At `:new` / `:edit`, the `<div class="flex flex-col gap-3">` form wrapper
  becomes `<div class="foyer-content-cols">`, with the form as the first column.
- A second `<div>` preview column is conditionally shown at `lg:` — this is a
  static preview (form values are not yet live-synced; the compose title assigns
  are rendered via a simple `phx-change` that updates `@preview_title` and
  `@preview_body` assigns). The live preview is **scoped to this plan** —
  it is not a deferred feature-group write path; it is pure UI state.
  Implementation: add `@preview_title` and `@preview_body` assigns in `mount/3`,
  update them in a `handle_event("preview_change", attrs, socket)` via
  `phx-change="preview_change"` on the form. The preview panel renders a
  `<FoyerComponents.announcement_card>` driven by these assigns.
- Staff-compose-gated (mock: `desktop-staff-compose-gated.html`): staff users
  see a centred "Manager view only — Back to The House" message instead of the
  form. The current `AnnouncementLive` does not enforce this at the route level
  (compose is behind `:ensure_on_shift`, not `:ensure_manager`). The desktop
  plan adds a manager-only guard inside the render: if `!Scope.manager?(@current_scope)`
  and `@live_action == :new`, render the gated view instead of the form. This
  is a **render-only gate** — no new route or `on_mount` hook.

### 5.4 House — read receipts (AnnouncementLive :show)

Mock: `desktop-read-receipts.html`.

The read-receipts detail is a sub-view of the announcement show page (same
LiveView, same `:show` action). At desktop the announcement occupies the left
column and a receipts summary panel occupies the right column (at `lg:`).

```
┌──────────────┬──────────────────────────────┬────────────────────────────┐
│  Side-rail   │  Suite 412 — Allergy...      │  Read receipts (lg: only)  │
│              │  Requires acknowledgement    │                            │
│              │  Charlotte · Housekeeping    │  2 confirmed / 7 total     │
│              │                              │  [Aisha ✓] [Hugo ✓]        │
│              │  [I've read & understood]    │                            │
└──────────────┴──────────────────────────────┴────────────────────────────┘
```

At `md:` it remains single-column (announcement detail only, receipts below).

Concrete changes to `AnnouncementLive.render/1` (`:show` clause):

- Shell wrapper as above.
- The `:show` content wraps in `foyer-content-cols` at `lg:`. Left column:
  existing announcement detail. Right column: read receipt summary rendered
  from `@announcement.reads` and `@announcement.acks` (already preloaded by
  `get_announcement!/2` in §6.4 of the mobile plan). No new data load.
- The right column is `hidden lg:block`.

### 5.5 and 5.6 — House manager surfaces (deferred)

`/announcements/digest` (weekly digest) and `/announcements/mine` (my
announcements) are **not in scope for this plan**. They require new routes,
new `AnnouncementLive` actions, new `HousePort` callbacks, new context
functions, and dedicated tests — genuine new House feature work, not desktop
layout work. The desktop mocks for these surfaces (`desktop-weekly-digest.html`,
`desktop-my-announcements.html`) are also not present in
`docs/feature-groups/scaffold/designs/`, so there is no file-backed evidence
to implement them here.

These surfaces are **deferred to a future House feature-group plan** that
should include proper design artifacts, a spec prefix, route ordering analysis,
authorization contract, and query contracts. The router in this plan adds **no
new announcement routes**.

For reference, the correct ordering when those routes are eventually added must
place static paths before the parameterised catch-all:

```elixir
# Correct ordering — static paths first
live "/announcements/new", AnnouncementLive, :new
# (future: live "/announcements/digest", AnnouncementLive, :weekly_digest)
# (future: live "/announcements/mine", AnnouncementLive, :mine)
live "/announcements/:id", AnnouncementLive, :show
live "/announcements/:id/edit", AnnouncementLive, :edit
```

The current router already has this correct ordering (`/new`, `/:id`,
`/:id/edit`). No router changes are needed in this plan.

### 5.7 Chat — inbox (ChatLive :inbox)

Mock: `desktop-message-off-shift.html` (the inbox panel is on the left side
within the content area; the room panel on the right).

The desktop chat layout is a master-detail two-panel inside the content area.
The left panel lists conversations; the right panel shows the active room. On
mobile these are full-screen pages (inbox and room are different `live_action`
states). On desktop they can both show simultaneously — but that requires
holding two data sets in the same LiveView instance.

**Decision: desktop chat uses a side-panel layout where the conversation list
is always visible on the left (`md:w-72`) and the active room (or an empty
state) fills the right at `md:`.** Both panels are in the same template;
visibility is toggled by CSS, not by `live_action` state. The back-button
navigation (`<.link navigate={~p"/chat"}>`) that works on mobile is hidden at
`md:` (the left panel is always visible).

```
┌──────────────┬──────────────────────────┬──────────────────────────────────┐
│  Side-rail   │  Conversations (left)    │  Room (right, md:block)          │
│              │  ──────────────────────  │  ────────────────────────────    │
│              │  [search input]          │  Charlotte Voss                  │
│              │  ┌────────────────────┐  │  ─────────────────────────────   │
│              │  │ Charlotte (today)  │  │  [message bubbles stream]        │
│              │  │ Floor 4 (today)    │  │                                  │
│              │  │ Aisha (yesterday)  │  │  [text input] [Send]             │
│              │  └────────────────────┘  │  ─────────────────────────────   │
│              │                          │  ← (back link hidden at md:)     │
│              │  [New message]           │                                  │
└──────────────┴──────────────────────────┴──────────────────────────────────┘
```

Concrete changes to `ChatLive.render/1`:

- Shell wrapper as above.
- At `md:`, the `.foyer-scroll#chat` div changes to a flex row with two child
  panels: `<div id="chat-panel-inbox" class="md:w-72 md:border-r md:flex-shrink-0">` and
  `<div id="chat-panel-room" class="hidden md:flex md:flex-col md:flex-1">`.
- On mobile, the existing `cond` branches (`:show` vs `:inbox`) remain. At
  `md:`, both panels are rendered simultaneously: inbox is always shown, room is
  shown when `@conversation` is set (`md:block` when `@conversation != nil`,
  otherwise a placeholder "Select a conversation").
- The `#back-to-inbox` link becomes `md:hidden` (no need to navigate away from
  inbox at desktop).
- **`handle_params/3` change for `:show`:** a direct visit, refresh, or shared
  link to `/chat/:conversation_id` starts with an empty `@streams.conversations`
  (ChatLive mounts it as `stream(:conversations, [])`). To ensure the left panel
  is populated on direct loads, the `:show` clause (via `load_conversation/2`)
  must also call `inbox_for/1` and stream-reset conversations:

  ```elixir
  defp load_conversation(socket, id) do
    scope = socket.assigns.current_scope
    conversations = FoyerWeb.LiveDeps.chat().inbox_for(scope.user)
    channels = FoyerWeb.LiveDeps.channels().list_for_user(scope.user)
    on_shift_ids = FoyerWeb.LiveDeps.shifts().users_on_shift_ids()

    conversation = FoyerWeb.LiveDeps.chat().get_conversation!(id, scope.user)
    messages = FoyerWeb.LiveDeps.chat().list_messages(conversation)

    {:noreply,
     socket
     |> stream(:conversations, conversations, reset: true)
     |> assign(:channels, channels)
     |> assign(:on_shift_ids, on_shift_ids)
     |> assign(:conversation, conversation)
     |> assign(:page_title, conversation_title(conversation, scope.user.id))
     |> stream(:messages, messages, reset: true)}
  end
  ```

  When navigating from `:inbox` → `:show` within the same LiveView instance,
  the `reset: true` re-streams conversations (no flicker; the same items are
  returned). On a direct load the panel is populated. This is the dual-load
  approach: both inbox and room data are loaded in `handle_params/3` for `:show`.
  A single-LiveView consolidation was not needed because `ChatLive` already
  handles all chat actions in one module.

### 5.8 Chat — off-shift DM (desktop-message-off-shift.html)

The mock shows an off-shift banner in the room when messaging an off-shift
colleague. This is **a room-view feature**, not a separate action. The banner
is rendered when `@conversation` has a participant whose `user_id` is not in the
`@on_shift_ids` MapSet.

- Add `@on_shift_ids` assign to `ChatLive.mount/3`:
  `assign(socket, :on_shift_ids, MapSet.new())`.
- In `handle_params/3` for `:show`, load
  `LiveDeps.shifts().users_on_shift_ids()` and assign to `@on_shift_ids`.
- In the room template, show a banner `<div id="off-shift-banner">...</div>`
  when the other participant is off shift.

This is a **read-only data point** (no new write path) and requires only the
`Shifts.users_on_shift_ids/0` call that already exists.

### 5.9 Recognition — give (RecognitionsLive :new)

Mock: `desktop-give.html`, `desktop-staff-give-no-points.html`.

```
┌──────────────┬──────────────────────────────────┬───────────────────────────┐
│  Side-rail   │  Give recognition (form left)    │  Preview col (lg: only)   │
│              │  Recipient select                │                           │
│              │  The story textarea              │  ┌──────────────────────┐ │
│              │  House values chips              │  │ For Hugo Brandt      │ │
│              │  Visibility toggle               │  │ Initiative · Care    │ │
│              │  Bonus points (manager only)     │  │ Charlotte · just now │ │
│              │  [Send recognition]              │  └──────────────────────┘ │
└──────────────┴──────────────────────────────────┴───────────────────────────┘
```

Concrete changes to `RecognitionsLive.render/1` (`:new` clause):

- Shell wrapper as above.
- At `lg:`, wrap form + preview in `.foyer-content-cols`.
- Preview column: a static `<FoyerComponents.recognition_card>` seeded from
  `@preview_recipient_name`, `@preview_body`, `@preview_values` assigns, updated
  via `phx-change="preview_change"` on the form. Add `@preview_*` assigns to
  `mount/3` and a `handle_event("preview_change", ...)` handler.
- `desktop-staff-give-no-points`: no bonus points fieldset for staff — already
  gated by `Scope.manager?/1` in the existing template. No change needed.

### 5.10 Recognition — sent confirmation (RecognitionsLive :show — undo state)

Mock: `desktop-recognition-sent-undo.html`.

The confirmation state (60-second undo window) is a feature-group concern. The
desktop plan does **not** implement the undo timer. The mock's layout is noted:
single-column receipt card on the right side of the content area, no second
panel. The existing `:show` render already handles display. The desktop shell
wrapper is added; no other changes.

### 5.11 Recognition — people directory (PeopleLive)

Mock: `desktop-people-directory.html`.

`PeopleLive` already has a partial responsive layout (`hidden md:block` on the
filters aside). The desktop plan completes it: the aside becomes a proper
rail-style sidebar within the content area, and the people list moves to the
right column.

```
┌──────────────┬──────────────────────────┬───────────────────────────────────┐
│  Side-rail   │  Filters (md: sidebar)   │  People list                      │
│              │  All                     │  ┌───────────────────────────────┐│
│              │  On shift                │  │ Maya Okafor · Sr. Housekeeper ││
│              │  Off shift               │  │ [On shift]                    ││
│              │  Managers                │  ├───────────────────────────────┤│
│              │                          │  │ Rafael Mendes · Night Mgr     ││
│              │  [Channels]              │  └───────────────────────────────┘│
└──────────────┴──────────────────────────┴───────────────────────────────────┘
```

Concrete changes to `PeopleLive.render/1`:

- Shell wrapper as above.
- The existing `<aside class="hidden md:block ...">` changes to
  `<aside class="hidden md:block md:w-48 md:flex-shrink-0 ...">`
  and the people list `<ul>` gets `md:flex-1`.
- A `<div class="md:flex md:gap-4">` wrapper groups aside + list.
- The existing people-row link and avatar markup is unchanged.

### 5.12 Profile — Charlotte Voss / Me (ProfileLive and PeopleLive :show)

Mock: `desktop-charlotte-voss.html`.

The profile desktop layout shows the header block on the left of the content
area and the recognitions feed + stats on the right at `lg:`.

```
┌──────────────┬──────────────────────────┬───────────────────────────────────┐
│  Side-rail   │  Profile header          │  Recognitions + stats (lg: only)  │
│              │  Avatar · Name · Title   │                                   │
│              │  Languages               │  Recognitions this month: 2       │
│              │  [On shift]              │  ┌───────────────────────────────┐│
│              │  Stats row               │  │ Quietly handled...            ││
│              │                          │  └───────────────────────────────┘│
└──────────────┴──────────────────────────┴───────────────────────────────────┘
```

Concrete changes to `FoyerComponents.profile_card/1`:

- Wrap the header block and the recognitions sections in `.foyer-content-cols`
  at `lg:`.
- Header (`<header>`) + stats grid: left column.
- Recognitions (received + given) + points + rewards: right column.
- At `md:` and below: single column, existing layout.

Since `profile_card/1` is used by both `ProfileLive` and `PeopleLive :show`,
the change is made once in the component.

---

## 6. `Layouts.app` changes

`Layouts.app/1` currently renders `{render_slot(@inner_block)}` plus the flash
group. No changes to the component function signature or the flash group are
needed — the desktop shell is built entirely inside the LiveView templates and
the `foyer_components.ex` module.

**Flash positioning at desktop:** The existing `.foyer-flash` CSS already uses
`position: fixed; top: 1rem; right: 1rem`. At desktop widths the flash
appears in the top-right corner of the viewport, which is outside the side-rail.
No change needed.

---

## 7. Schema, context, and migration changes

### 7.1 No new migrations

The desktop layout adds no new DB tables or columns. All data required by the
desktop views is already loaded by existing context functions.

### 7.2 New context functions

None. The §5.5/§5.6 surfaces are deferred; no new port callbacks or context
functions are added by this plan.

### 7.3 N+1 avoidance

- `desktop_rail/1` reads `@channels` from a pre-computed assign. ChatLive
  already calls `list_for_user/1` in `handle_params/3` for the `:inbox` and
  `:new_message` actions. For `:show`, channels are also loaded inside
  `load_conversation/2` (see §5.7). This is one extra query per page load for
  ChatLive `:show`. Backed by the existing `index(:channel_memberships,
  [:user_id])`.
- Other surfaces pass `channels: []` to `desktop_rail/1` and do not load
  channels, so there is no regression.

### 7.4 Mock additions to `Foyer.HouseMock`

No new callbacks are added to `Foyer.HousePort` in this plan (§5.5/§5.6 are
deferred). The existing `stub_with(Foyer.HouseMock, Foyer.House)` in the
desktop smoke test setup covers all current port functions without change.

---

## 8. LiveView module changes

Most changes are in `render/1` templates. Several LiveViews also require
`mount/3` and `handle_params/3` changes to support the desktop layout:
`AnnouncementLive` gains `@preview_*` assigns in `mount/3`;
`RecognitionsLive` gains `@preview_*` assigns in `mount/3`;
`ChatLive` gains `@on_shift_ids` and `@channels` in `mount/3`, and its
`load_conversation/2` gains inbox + channels + on_shift_ids loads (see §5.7).
These state changes are load-data-for-layout changes — they are not deferred
feature writes.

### 8.1 `FoyerWeb.TodayLive`

File: `lib/foyer_web/live/today_live.ex`

- `render/1`: replace `<main class="foyer-root">` with `<main class="foyer-shell">`, insert `<FoyerComponents.desktop_rail>` and `<div class="foyer-content">`, add `md:max-w-2xl md:mx-auto` to `<div class="foyer-scroll" id="today">`.
- No `handle_params/3` changes.

### 8.2 `FoyerWeb.HouseLive`

File: `lib/foyer_web/live/house_live.ex`

- `render/1`: shell wrapper, rail, content div, `md:max-w-3xl` on feed.
- No `handle_params/3` changes.

### 8.3 `FoyerWeb.AnnouncementLive`

File: `lib/foyer_web/live/announcement_live.ex`

- `mount/3`: add `assign(:preview_title, "")`, `assign(:preview_body, "")`.
- `handle_params/3`:
  - `:new` clause: same, no changes.
  - `:show` clause: no changes.
  - `:edit` clause: populate `preview_title` / `preview_body` from the
    loaded announcement.
  - No new `:weekly_digest` or `:mine` clauses — those are deferred (§5.5/§5.6).
- `handle_event`: add `"preview_change"` handler — updates `@preview_title`
  and `@preview_body` from form params (no DB write, no port call).
- `render/1`:
  - `:new` / `:edit`: add `.foyer-content-cols` wrapper with form left, static
    preview right (hidden below `lg:`). Add `phx-change="preview_change"` to
    the compose form.
  - `:show`: add `.foyer-content-cols` wrapper with announcement detail left
    and read-receipts summary right (hidden below `lg:`).
  - Staff-compose gate: add manager guard in `:new` render.

### 8.4 `FoyerWeb.ChatLive`

File: `lib/foyer_web/live/chat_live.ex`

- `mount/3`: add `assign(:on_shift_ids, MapSet.new())` and
  `assign(:channels, [])`.
- `handle_params/3`:
  - `:show` clause: the private `load_conversation/2` helper is extended to
    also load `inbox_for/1`, `list_for_user/1` (channels), and
    `users_on_shift_ids/0`, as shown in §5.7. This ensures the desktop left
    panel is populated on direct loads.
  - `:inbox` clause: also load channels for the rail
    (`LiveDeps.channels().list_for_user(scope.user)` and assign to `@channels`).
  - `:new_message` clause: channels already loaded.
- `render/1`:
  - Replace shell structure (as per §4.3).
  - Pass `channels={@channels}` to `desktop_rail/1`.
  - At `md:`, inbox and room panels coexist. The inbox panel
    (`#chat-panel-inbox`) is `block md:flex-shrink-0 md:w-72 md:border-r`.
    The room panel (`#chat-panel-room`) is `hidden md:flex md:flex-col md:flex-1`.
  - Room panel shows the conversation, messages stream, and compose form when
    `@conversation != nil`; shows a placeholder message ("Select a
    conversation") otherwise.
  - The off-shift banner inside the room (§5.8) is added.
  - `#back-to-inbox` link gets `md:hidden`.

### 8.5 `FoyerWeb.RecognitionsLive`

File: `lib/foyer_web/live/recognitions_live.ex`

- `mount/3`: add `assign(:preview_recipient_name, "")`, `assign(:preview_body, "")`, `assign(:preview_values, [])`.
- `handle_params/3`: `:new` clause adds `people` (already there); no other changes.
- `handle_event`: add `"preview_change"` handler.
- `render/1`:
  - `:new` clause: `.foyer-content-cols` wrapper at `lg:`, preview column.
  - `:index` clause: shell wrapper.
  - `:show` clause: shell wrapper.
  - `:edit` clause: shell wrapper.

### 8.6 `FoyerWeb.ProfileLive`

File: `lib/foyer_web/live/profile_live.ex`

- `render/1`: shell wrapper. The profile card (`profile_card/1` component) gets the two-column treatment at `lg:`.
- No other changes.

### 8.7 `FoyerWeb.PeopleLive`

File: `lib/foyer_web/live/people_live.ex`

- `render/1`:
  - Shell wrapper.
  - Replace the existing naive `hidden md:block` aside with the proper
    `md:flex md:gap-4` content container holding aside + list.
  - Pass `active={:me}` to `desktop_rail/1` (People is under the "Me"
    destination in the mocks — the side-rail does not have a separate "People"
    item, confirming the design's intent for People to be a sub-page of Me).

---

## 9. Smoke test additions

The existing smoke test (`test/foyer_web/smoke_test.exs`) asserts on
surface content. This plan adds a second test module:

Path: `test/foyer_web/smoke_test.exs`

Tagged `:integration`, `async: true`, same fixture setup as the scaffold smoke
test (imports `FoyerWeb.ScaffoldFixtures`, uses `stub_with` to bind real
contexts).

### 9.1 Limitation of `Phoenix.LiveViewTest`

`Phoenix.LiveViewTest` does not control viewport width. It renders HTML
server-side; CSS `@media` rules are not evaluated. Therefore, the test cannot
assert that the side-rail is **visible** — CSS visibility is a browser concern.

**What we can assert:**

- The side-rail element is **present in the DOM** (by ID `#desktop-rail`).
- Rail nav items carry the correct IDs (`#rail-nav-today`, `#rail-nav-house`,
  etc.) and the expected `aria-current="page"` attribute on the active item.
- The bottom-nav element is also **present in the DOM** (it is present in the
  HTML; CSS hides it at desktop, but the DOM presence is always true). We do not
  assert it is hidden — that is a CSS concern, not a server-rendered concern.
- The off-shift banner element is present in the chat room DOM when the other
  participant is off shift.

The plan is honest about this limitation — tests prove structural correctness
(DOM shape), not visual correctness (CSS breakpoint rendering).

### 9.2 Test skeleton

```elixir
defmodule FoyerWeb.DesktopSmokeTest do
  use FoyerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Mox
  import FoyerWeb.ScaffoldFixtures

  @moduletag :integration

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    stub_with(Foyer.AccountsMock, Foyer.Accounts)
    stub_with(Foyer.ShiftsMock, Foyer.Shifts)
    stub_with(Foyer.ChannelsMock, Foyer.Channels)
    stub_with(Foyer.HouseMock, Foyer.House)
    stub_with(Foyer.RecognitionsMock, Foyer.Recognitions)
    stub_with(Foyer.ChatMock, Foyer.Chat)
    stub_with(Foyer.ProfileMock, Foyer.Profile)
    stub_with(Foyer.TodayMock, Foyer.Today)

    fixtures = seed_scaffold!()
    {:ok, fixtures}
  end

  describe "desktop side-rail presence" do
    test "Today renders desktop rail with correct nav IDs", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/today")

      assert has_element?(view, "#desktop-rail")
      assert has_element?(view, "#rail-nav-today[aria-current='page']")
      assert has_element?(view, "#rail-nav-house")
      assert has_element?(view, "#rail-nav-chat")
      assert has_element?(view, "#rail-nav-me")
    end

    test "House renders desktop rail with House active", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/house")

      assert has_element?(view, "#desktop-rail")
      assert has_element?(view, "#rail-nav-house[aria-current='page']")
    end

    test "Chat renders desktop rail with Chat active", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/chat")

      assert has_element?(view, "#desktop-rail")
      assert has_element?(view, "#rail-nav-chat[aria-current='page']")
    end

    test "Profile (/me) renders desktop rail with Me active", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/me")

      assert has_element?(view, "#desktop-rail")
      assert has_element?(view, "#rail-nav-me[aria-current='page']")
    end

    test "Rail disables House/Chat/Me for off-shift user", ctx do
      conn = sign_in(ctx.conn, ctx.jamal)
      {:ok, view, _html} = live(conn, ~p"/today")

      assert has_element?(view, "#rail-nav-house[disabled]")
      assert has_element?(view, "#rail-nav-chat[disabled]")
      assert has_element?(view, "#rail-nav-me[disabled]")
    end
  end

  describe "chat desktop panels" do
    test "chat inbox includes both inbox and room panel elements", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/chat")

      assert has_element?(view, "#chat-panel-inbox")
      assert has_element?(view, "#chat-panel-room")
    end

    test "off-shift banner present in room when other participant is off shift", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/chat/#{ctx.maya_charlotte.id}")
      # Charlotte is on shift in fixtures; banner should not appear.
      refute has_element?(view, "#off-shift-banner")
    end

    test "direct load of chat room populates inbox panel", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/chat/#{ctx.maya_charlotte.id}")
      # The dual-load in load_conversation/2 ensures conversations are streamed
      # even on a direct room load, so the inbox panel is not empty.
      assert has_element?(view, "#chat-panel-inbox")
      assert has_element?(view, "#inbox")
    end
  end
end
```

**Note on `ensure_manager` hook:** `lib/foyer_web/user_auth.ex` has only three
`on_mount/4` clauses — `:mount_public`, `:ensure_authenticated`, and
`:ensure_on_shift`. There is no `:ensure_manager` clause. The §5.5/§5.6
deferral removes any need for such a hook in this plan. If the future House
feature-group plan adds manager-only routes, it must either add an
`:ensure_manager` on_mount hook to `UserAuth` or use an inline guard in
`handle_params/3` — that decision belongs to that plan.

---

## 10. Accessibility

### 10.1 What this plan adds

- `<nav id="desktop-rail" aria-label="Main navigation">` — proper ARIA landmark.
- `<main>` element wrapping all LiveView content — already present via the
  existing `<main class="foyer-root">` pattern.
- `aria-current="page"` on the active rail item — added to `desktop_rail/1`
  (mirrors the `bottom_nav/1` pattern).
- Rail `<button disabled aria-disabled="true">` for off-shift items — mirrors
  `bottom_nav/1` pattern.
- Sign-out uses `<.link method="delete" href={~p"/session"}>`, which Phoenix
  renders as a CSRF-protected form automatically. This is correct inside a
  `Phoenix.Component` without a backing struct.

### 10.2 What is deferred

- Focus management when navigating between chat panels on desktop (tab order
  across two side-by-side panels should route to the active panel first).
- Full WCAG AA contrast audit on rail text against cream background.
- Skip-to-content link (standard accessibility affordance for keyboard users).

These are flagged for the per-surface feature-group plans to pick up.

---

## 11. Step-by-step execution order

Each step names the files it touches. The implementing agent follows these
steps verbatim without deviation.

**Step 1 — Add CSS layout primitives to `assets/css/app.css`.**

Files: `assets/css/app.css`.

Add the new CSS rules from §3.1 to `app.css` after the existing
`.foyer-flash` block:

- `.foyer-shell`, `.foyer-content` with responsive variants.
- `.foyer-rail` and its children (`.foyer-rail__header`, `.foyer-rail__item`,
  `.foyer-rail__section`, `.foyer-rail__footer`).
- `@media (min-width: 768px) { .foyer-bottom-nav { display: none; } }`.
- `.foyer-content-cols` with the `lg:` grid variant.

Run `mix format` and check the server compiles (`mix compile --warnings-as-errors`).

**Step 2 — Add `desktop_rail/1` component to `foyer_components.ex`.**

Files: `lib/foyer_web/components/foyer_components.ex`.

Add the new `desktop_rail/1` component with the HEEx skeleton from §4.1.
Add its `attr` declarations above the function. The component uses
`<.link navigate>`, `<.link method="delete">`, `<.icon>`, and
`<FoyerWeb.FoyerComponents.avatar>`.

Verify: `mix credo --strict` passes; `mix compile --warnings-as-errors` passes.

**Step 3 — Update `TodayLive` template.**

Files: `lib/foyer_web/live/today_live.ex`.

Apply shell wrapper changes from §8.1. Run `mix test
test/foyer_web/smoke_test.exs` — all existing Today tests must still
pass.

**Step 4 — Update `HouseLive` template.**

Files: `lib/foyer_web/live/house_live.ex`.

Apply shell wrapper changes from §8.2. Run `mix test
test/foyer_web/smoke_test.exs`.

**Step 5 — Update `AnnouncementLive` — compose and show.**

Files: `lib/foyer_web/live/announcement_live.ex`.

- Add `@preview_title`, `@preview_body` assigns to `mount/3`.
- Add `"preview_change"` event handler.
- Add `phx-change="preview_change"` to the compose forms (`:new` and `:edit`).
- Wrap `:new` and `:edit` renders in `.foyer-content-cols` with preview column.
- Add manager gate to `:new` render.
- Wrap `:show` render in `.foyer-content-cols` with read-receipts column.
- Add shell wrapper to all render clauses.

Run `mix test test/foyer_web/smoke_test.exs`.

**Step 6 — Update `ChatLive` for desktop two-panel layout.**

Files: `lib/foyer_web/live/chat_live.ex`.

- Add `@on_shift_ids` and `@channels` assigns to `mount/3`.
- Update `handle_params/3` clauses to load `on_shift_ids` and `channels`.
- Restructure `render/1` for the two-panel layout (§8.4).

Run `mix test test/foyer_web/smoke_test.exs`.

**Step 7 — Update `RecognitionsLive` for desktop layout.**

Files: `lib/foyer_web/live/recognitions_live.ex`.

- Add `@preview_*` assigns to `mount/3`.
- Add `"preview_change"` handler.
- Wrap `:new` in `.foyer-content-cols`.
- Add shell wrapper to all render clauses.

Run `mix test test/foyer_web/smoke_test.exs`.

**Step 8 — Update `ProfileLive` template.**

Files: `lib/foyer_web/live/profile_live.ex`.

Apply shell wrapper from §8.6. The two-column split is in the shared component.

**Step 9 — Update `FoyerComponents.profile_card/1` for desktop layout.**

Files: `lib/foyer_web/components/foyer_components.ex`.

Wrap header + recognitions in `.foyer-content-cols` at `lg:` (§5.12). The
component is used by both `ProfileLive` and `PeopleLive :show`.

Run `mix test test/foyer_web/smoke_test.exs`.

**Step 10 — Update `PeopleLive` template.**

Files: `lib/foyer_web/live/people_live.ex`.

Apply shell wrapper and the aside + list flex layout from §8.7 and §5.11.

Run `mix test test/foyer_web/smoke_test.exs`.

**Step 11 — Write the desktop smoke test.**

Files: `test/foyer_web/smoke_test.exs`.

Write the test from §9.2. Run `mix test test/foyer_web/smoke_test.exs`.
Fix any failures before proceeding.

**Step 12 — Full test suite + static checks.**

Run:

```bash
mix test
mix format --check-formatted
mix credo --strict
mix dialyzer
```

All must pass with 0 errors / issues. Fix anything that does not pass before
marking the plan complete.

**Step 13 — Manual walkthrough (not automated).**

Start `mix phx.server` and open each surface in a browser at three widths:

- **1280 px** — full desktop: side-rail visible, bottom-nav hidden, two-column
  layouts render correctly.
- **768 px / 820 px** — the plan's highest-risk breakpoint (`md:`): side-rail
  visible, content area has at least ~500 px, nothing overflows.
- **375 px** — mobile: side-rail hidden, bottom-nav visible, layouts unchanged.

This step is manual; it is not part of the automated gate.

---

## 12. Risks & open questions

### 12.1 Today desktop — no mock (high-risk, flag for Codex)

The Today surface has no desktop mock. The plan infers a centred single-column
layout (`md:max-w-2xl md:mx-auto`). This is conservative and unlikely to be
wrong in spirit, but a product decision (whether Today should show a second
panel — e.g. the recognition feed — at desktop widths) has not been made. The
Codex reviewer should push hard on this. If the product team produces a Today
desktop mock before execution, the plan must be updated.

### 12.2 `md:` breakpoint vs. `lg:` for side-rail

Chosen: `md:` (768 px). Risk: narrow tablets in portrait mode (768 px wide) get
the side-rail and no bottom-nav. The side-rail is 15 rem (240 px), leaving 528 px
for content, which is tight but functional. An alternative is `lg:` (1024 px),
which would give the side-rail only to laptops and desktops. The `md:` choice is
consistent with the existing `PeopleLive` partial responsive layout and the
comment in the mobile plan's CSS. If the product team determines `lg:` is
correct, only the CSS breakpoints change — no HEEx or component changes.

### 12.3 Tablet portrait collapse

At 768 px the side-rail is always shown expanded (15 rem). A collapsed icon-only
rail variant (2.5 rem wide) may exist in some Foyer mocks, but
`docs/feature-groups/scaffold/designs/` contains no files in this workspace —
the existence of collapse-toggle designs is **unvalidated**. This remains a
deferred enhancement. The risk is that 768–900 px viewports feel cramped. The
plan's CSS does not add a collapse toggle; this is explicitly left for the
per-surface feature groups.

### 12.4 Chat two-panel state management

The desktop chat two-panel approach (§5.7) keeps inbox and room data in the
same LiveView instance across `handle_params/3` calls. When a user navigates
from `/chat` to `/chat/:id`, the `:show` `handle_params/3` resets `@streams.messages`
but does not reset `@streams.conversations`. This is intentional: the inbox
panel should not flicker when a room is opened. The risk is that the inbox
stream becomes stale between navigations (if a new conversation arrives via
PubSub). Since PubSub broadcasts are still stubbed in the scaffold, this risk
is deferred. When the Chat feature group wires PubSub, the inbox broadcast
handler will need to use `stream_insert/3` (not `reset: true`) to avoid
clearing the messages stream.

### 12.5 Sign-out in rail — resolved

The sign-out uses `<.link method="delete" href={~p"/session"}>` (§4.1). Phoenix
renders this as a CSRF-protected form automatically — no manual token injection
is needed. This was an open question in v1 and is resolved in v2.

### 12.6 `preview_change` event and mobile scroll

Adding `phx-change="preview_change"` to the compose form fires a server
round-trip on every keystroke on mobile too (not just desktop). This is
acceptable for the scaffold because the handler is cheap (no DB call, no port
call). If performance is a concern for the full feature implementation, the
`phx-debounce="300"` attribute should be added. This is noted here but not
required for the scaffold.

### 12.7 Future: House manager surfaces (open question for executor)

`/announcements/digest` and `/announcements/mine` are deferred. When the House
feature-group plan eventually adds them, the executor will need to decide whether
to add a new `:ensure_manager` on_mount hook to `UserAuth` (cleaner, enforced at
the router level) or use an inline `handle_params/3` guard with redirect (no hook
needed, but the route is not protected at the session level). This plan takes no
position — it is an open question for that future plan.

---

## 13. Pre-empting Codex objections

- **No `Application.put_env/3` in tests.** The desktop smoke test (§9.2) uses
  `stub_with` in `setup`, identical to the existing scaffold smoke test.
- **N+1 queries.** The `desktop_rail/1` channels list is loaded in
  `handle_params/3`, not the component. No lazy-loading hidden in templates.
- **Migration reversibility.** No migrations in this plan. All changes are pure
  UI layout.
- **No secrets in source.** No env vars, credentials, or tokens introduced.
- **`mix credo --strict` cleanliness.** No multi-module files. No `@apply` in
  CSS. No `is_` predicate function names.
- **`handle_params/3` discipline.** The `preview_change` event handler is a
  pure assign update, not a DB call. The `load_conversation/2` data loads are
  in `handle_params/3`, not `mount/3`.
- **LiveView streams.** The chat inbox panel uses the existing
  `@streams.conversations` stream. The `reset: true` in `load_conversation/2`
  ensures consistency on direct room loads without producing a blank panel.
- **Test isolation.** The desktop smoke test owns its fixtures via
  `FoyerWeb.ScaffoldFixtures.seed_scaffold!/0`, same as the scaffold smoke test.
  No shared global state.
- **Scope.** This plan adds no new routes, no new schemas, no new migrations,
  and no new context functions. It wraps existing surfaces in a desktop shell
  and fixes the chat direct-load data gap.
