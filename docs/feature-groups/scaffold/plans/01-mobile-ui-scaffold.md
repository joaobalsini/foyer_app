# Plan 01 — Mobile-first UI scaffold

Status: revised after Codex review (v2)
Scope: cross-cutting scaffold for all feature groups (Today, House, Announcements,
Recognitions, Chat, Channels, Profile, Shifts, People Directory)
Spec: none — see [`../spec.md`](../spec.md)
Review: [`01-mobile-ui-scaffold-review.md`](./01-mobile-ui-scaffold-review.md)

---

## Revision log

**v2 — addressed Codex review of 2026-05-25.** Key changes (see review doc for
full rationale):

- §3 / §4: replaced the single `live_session :authenticated` block + brittle
  `socket.view` introspection with **three live_sessions** (`:public`,
  `:authenticated_today`, `:authenticated_on_shift`) and matching on_mount
  hooks (`:mount_public`, `:ensure_authenticated`, `:ensure_on_shift`).
- §11.3: `config/test.exs` now points at **Mox mocks**, not real contexts.
  Smoke test uses `Mox.stub_with/2` + `verify_on_exit!`. `Application.put_env/3`
  in tests is explicitly forbidden.
- §6.4 / §6.6: `House.get_announcement!/2` and `Chat.get_conversation!/2` now
  bake **membership authorization** into the read query. Smoke test asserts an
  unauthorized-access redirect.
- §5.13: added unique + check constraints — one open shift per user, unique
  channel membership, non-negative `bonus_points`, `kind ↔ channel_id` pairing
  check, direct-conversation `direct_key` uniqueness, partial pinned-feed
  index, and the additional inbox / feed-ordering / handoff-lookup indexes the
  review flagged.
- §6.1 / §6.6: spelled out the N+1-free queries — `list_people/1` preloads
  `memberships: :channel`, `inbox_for/1` uses Postgres `DISTINCT ON
  (conversation_id)` for latest message per row.
- §6.7 / §6.8: `Foyer.Today.brief_for/1` and `Foyer.Profile.profile_for/1`
  now return typed `Foyer.Today.Briefing` and `Foyer.Profile.Card` structs
  (DTOs), not bare maps. Today is explicitly a **read-only orchestrator** —
  writes still flow through Shifts/House/Recognitions.
- §7: UserPickerLive moves list loading from `mount/3` to `handle_params/3`;
  HouseLive computes `channel_options` outside HEEx; pilcrow typographic
  decoration replaced with the `<.icon>` component; `.foyer-serif`
  letter-spacing set to `0`; submit button gets `type="submit"` and a stable
  `id`.
- §10: smoke-test redirect assertion uses `{:error, {:redirect, %{to:
  "/today"}}}` (not `:live_redirect`); bottom-nav links get stable IDs and
  the test asserts on the IDs, not on broad `a, button` selectors; the test
  now also `render_click`s Start shift, End shift, and "I've read & understood"
  since those writes are implemented.
- §13: step 5 uses `mix ecto.migrate` (not `ecto.reset`); Dialyzer moves to
  after LiveViews are in place; `mix phx.server` is a manual instruction;
  step 1 documents that `mix deps.get` requires network.
- §15: open questions resolved in-line; this section becomes
  acknowledgements rather than blocking questions.

The strengths the review called out (§1 scoping, §2.1 daisyUI rip-out, §4
`Layouts.app` contract, §5 typed schemas, §7 `handle_params/3` discipline,
§10 sandbox-owned fixtures) were preserved untouched.

---

## 1. Goal & non-goals

### Goal

A mobile-first, content-complete walkthrough of every Foyer surface, rendered against
real Postgres-backed seeds and a real Phoenix router, so that:

- Every LiveView module exists at its final route with its final name.
- Every Ecto schema is migrated, indexed, and carries an explicit `@type t`.
- Every context has a context behavior, a real implementation that reads from Repo, and
  a Mox mock wired through `FoyerWeb.LiveDeps`.
- The bottom-nav (Today / House / Chat / Me) and desktop side-rail surfaces all render
  the design's warm-cream + forest visual language — not the default daisyUI demo.
- The current-scope mechanism (fake POC user picker, on-mount hook, off-shift gate,
  manager vs staff role) is in place so feature-group work plugs into it without
  re-deriving the contract.
- A single `:integration` smoke test walks every surface and asserts on key designed
  copy, so that any future regression in routing / on-mount / layout wiring blows up
  loudly.

### Non-goals (deferred to feature-group work)

The following are deliberately **out of scope** for this plan. They belong in the
per-feature-group plans that follow.

- **PubSub-driven live updates.** Chat lists messages from the DB on `handle_params`;
  no broadcast/subscribe yet. Subscribe stubs are added on mount but emit no events.
- **Real write paths for everything besides shift start/end and acknowledgement.**
  Compose announcement, give recognition, send message, create-group-chat etc. all
  render their forms but the submit handler returns `{:noreply, put_flash(socket,
  :info, "Not implemented in scaffold")}` and routes back. Justified in §14.
- **Audience-targeting validation, ack receipts roll-up, points ledger, rewards
  redemption.** Schemas exist and queries are real, but business rules around them
  are stubbed.
- **Translations, attachments, mentions, mute, scheduled publish, edit/remove grace
  windows.** Designs show the buttons; handlers are inert.
- **Isolated `live_isolated/3` tests with scenario modules.** Infrastructure is
  added (Mox mocks, scenario folder layout, harness placeholder) but no scenarios
  are written. See §11 and §14.
- **Production authentication.** Per FOYER.md v1, a fake user picker on `/`.
- **Desktop layout polish.** Desktop side-rail renders for the People Directory
  surface only (since the design shows it there). Other LiveViews use the mobile
  bottom-nav at all widths — feature groups will add desktop variants.
- **Accessibility audit.** ARIA labels are added on icon-only buttons (per the
  designs) but no full keyboard/contrast pass.

---

## 2. Visual system

The designs ship a small, consistent vocabulary: warm cream background, forest green
accents, claret for "this needs attention", brass for points, a serif heading face,
a mono micro-label face, and four reusable atoms (`foyer-avatar`, `foyer-pulse`,
`foyer-tag`, `foyer-btn`, `foyer-rule`). The plan **distils these into a small set
of `@layer components` rules in `assets/css/app.css`** so HEEx templates can read
naturally (`class="foyer-tag claret"`) and Tailwind utilities still work for layout.

### 2.1 daisyUI: rip it out

**Decision: remove daisyUI plugin imports from `app.css`.** Reasons:

- AGENTS.md says *"Always manually write your own tailwind-based components instead
  of using daisyUI for a unique, world-class design."*
- The design language is the opposite of the daisyUI default look. Keeping daisyUI
  in the bundle costs ~30 KB and provides theme variables that conflict with the
  Foyer palette.
- `core_components.ex` currently uses a handful of daisyUI classes (`btn`,
  `btn-primary`, `alert`, `select`, `textarea`, `input`, `table`, `list`,
  `fieldset`, `checkbox`, `toast`). The plan replaces those with hand-written
  Tailwind equivalents inside `core_components.ex` so we keep the `<.input>` /
  `<.button>` / `<.flash>` API that AGENTS.md requires LiveViews to use.
- The dark/light theme toggle in `Layouts.app` is removed — the Foyer design is
  light only. The `<script>` block in `root.html.heex` that sets `data-theme` is
  removed too.

Concretely, this means:

1. Delete the two `@plugin "../vendor/daisyui-theme" { ... }` blocks and the
   `@plugin "../vendor/daisyui" { themes: false }` block from `assets/css/app.css`.
   Leave the heroicons plugin.
2. Delete `assets/vendor/daisyui.js`, `assets/vendor/daisyui-theme.js` files (and
   note in mix.exs comments that the corresponding `curl` lines are no longer
   needed).
3. Rewrite the bodies of `flash/1`, `button/1`, `input/1`, `header/1`, `table/1`,
   `list/1`, `theme_toggle/1` in `lib/foyer_web/components/core_components.ex` to
   use Tailwind utilities + the Foyer custom classes below. Keep their **attr
   contract identical** so callers don't have to change.
4. Remove `theme_toggle/1` invocation from `Layouts.app/1`. Remove the theme
   `<script>` from `root.html.heex`.

### 2.2 Palette (CSS custom properties in `:root`)

Added in `assets/css/app.css`, before the Tailwind import is consumed:

```css
:root {
  --foyer-cream: #f6f1e7;           /* warm cream — page bg, surface */
  --foyer-cream-deep: #ece4d2;      /* one notch deeper — cards, hover */
  --foyer-ink: #1f231f;             /* primary text */
  --foyer-ink-soft: #4b4f48;        /* secondary text */
  --foyer-rule: #d8cdb4;            /* hairline */
  --foyer-forest: #2e4434;          /* primary action */
  --foyer-forest-deep: #1f3025;     /* forest hover */
  --foyer-moss: #6e8a5d;            /* on-shift / positive */
  --foyer-claret: #7a2e2e;          /* urgent / pinned */
  --foyer-claret-soft: #f2dede;     /* claret pill bg */
  --foyer-brass: #b9883a;           /* points accent */
  --foyer-brass-soft: #f3e6c8;
}

html, body { background: var(--foyer-cream); color: var(--foyer-ink); }
```

These are the canonical hex values for the implementing agent. They are tuned to
match the visual rhythm of the design extracts — warm cream + forest + claret +
brass. If the implementing agent finds the cream is too yellow next to the
forest, the value is allowed to shift within `#f4ede0 .. #f8f2e8`; document the
final pick in a code comment.

### 2.3 Typography

**Decision: bundle the fonts locally** rather than pulling Google Fonts via a
`<link>` in `root.html.heex`. Reasons: AGENTS.md restricts external script/link
references; a self-hosted woff2 is one HTTP request from our own origin; it also
keeps the `mix precommit` deterministic when run without network.

- **Instrument Serif (Regular + Italic)** → headings (`.foyer-serif`).
- **JetBrains Mono (Regular)** → micro-labels, timestamps, ALL-CAPS tags
  (`.foyer-mono`).
- **System sans (`-apple-system, "Inter", sans-serif`)** → body. No bundled
  webfont needed.

Files land at `priv/static/fonts/` and are referenced from `app.css` via
`@font-face` blocks. Bundle the woff2 from
[Instrument Serif on GitHub](https://github.com/Instrument/serif) and
[JetBrains Mono](https://github.com/JetBrains/JetBrainsMono); commit the two
woff2s to the repo (these are open-licensed).

```css
@font-face {
  font-family: "Instrument Serif";
  src: url("/fonts/instrument-serif-regular.woff2") format("woff2");
  font-weight: 400;
  font-style: normal;
  font-display: swap;
}
@font-face {
  font-family: "Instrument Serif";
  src: url("/fonts/instrument-serif-italic.woff2") format("woff2");
  font-weight: 400;
  font-style: italic;
  font-display: swap;
}
@font-face {
  font-family: "JetBrains Mono";
  src: url("/fonts/jetbrains-mono-regular.woff2") format("woff2");
  font-weight: 400;
  font-style: normal;
  font-display: swap;
}
```

### 2.4 Component utilities

Added to `assets/css/app.css` after the Tailwind import, so they can be used as
plain class names in HEEx (the project does not use `@apply`, per AGENTS.md):

```css
/* Typography atoms */
.foyer-serif { font-family: "Instrument Serif", Georgia, serif; font-weight: 400; letter-spacing: 0; }
.foyer-mono { font-family: "JetBrains Mono", ui-monospace, monospace; font-size: 0.7rem; text-transform: uppercase; letter-spacing: 0.08em; color: var(--foyer-ink-soft); }

/* Avatar */
.foyer-avatar {
  display: inline-flex; align-items: center; justify-content: center;
  width: 2.25rem; height: 2.25rem; border-radius: 9999px;
  background: var(--foyer-cream-deep); color: var(--foyer-ink);
  font-family: "Instrument Serif", Georgia, serif;
  font-size: 0.9rem; letter-spacing: 0.02em;
  border: 1px solid var(--foyer-rule);
}
.foyer-avatar.sm { width: 1.75rem; height: 1.75rem; font-size: 0.75rem; }
.foyer-avatar.lg { width: 3.5rem; height: 3.5rem; font-size: 1.25rem; }

/* On-shift pulse dot */
.foyer-pulse {
  display: inline-block; width: 0.55rem; height: 0.55rem; border-radius: 9999px;
  background: var(--foyer-moss);
  box-shadow: 0 0 0 0 rgba(110, 138, 93, 0.6);
  animation: foyer-pulse 2.1s infinite;
}
@keyframes foyer-pulse {
  0%   { box-shadow: 0 0 0 0 rgba(110, 138, 93, 0.5); }
  70%  { box-shadow: 0 0 0 8px rgba(110, 138, 93, 0); }
  100% { box-shadow: 0 0 0 0 rgba(110, 138, 93, 0); }
}
@media (prefers-reduced-motion: reduce) { .foyer-pulse { animation: none; } }

/* Tags */
.foyer-tag {
  display: inline-flex; align-items: center; gap: 0.3rem;
  padding: 0.15rem 0.55rem; border-radius: 9999px;
  font-family: "JetBrains Mono", ui-monospace, monospace;
  font-size: 0.65rem; text-transform: uppercase; letter-spacing: 0.08em;
}
.foyer-tag.claret  { background: var(--foyer-claret-soft); color: var(--foyer-claret); }
.foyer-tag.moss    { background: rgba(110, 138, 93, 0.15); color: var(--foyer-forest-deep); }
.foyer-tag.forest  { background: var(--foyer-forest); color: var(--foyer-cream); }
.foyer-tag.outline { background: transparent; color: var(--foyer-ink-soft); border: 1px solid var(--foyer-rule); }

/* Buttons */
.foyer-btn {
  display: inline-flex; align-items: center; justify-content: center; gap: 0.4rem;
  padding: 0.7rem 1.1rem; border-radius: 0.5rem;
  font-family: "Instrument Serif", Georgia, serif; font-size: 1rem;
  background: var(--foyer-cream-deep); color: var(--foyer-ink);
  border: 1px solid var(--foyer-rule);
  transition: transform 80ms ease, background 120ms ease;
  cursor: pointer;
}
.foyer-btn:hover { background: #e3d8be; }
.foyer-btn:active { transform: translateY(1px); }
.foyer-btn.forest { background: var(--foyer-forest); color: var(--foyer-cream); border-color: var(--foyer-forest-deep); }
.foyer-btn.forest:hover { background: var(--foyer-forest-deep); }
.foyer-btn.ghost  { background: transparent; border-color: transparent; color: var(--foyer-ink); }
.foyer-btn.sm     { padding: 0.45rem 0.75rem; font-size: 0.85rem; }

/* Hairline rule */
.foyer-rule { border: 0; border-top: 1px solid var(--foyer-rule); margin: 0.8rem 0; }

/* Root + scroll container for the mobile shell */
.foyer-root  { background: var(--foyer-cream); min-height: 100vh; padding-bottom: 5rem; /* room for bottom-nav */ }
.foyer-scroll { padding: 1rem; display: flex; flex-direction: column; gap: 1rem; }
```

The implementing agent **must not** use `@apply` (forbidden by AGENTS.md) — these
are written as plain CSS rules.

### 2.5 Bottom navigation

Concretely a sticky bar at the bottom of the viewport, fixed at all phone widths
and hidden on `md:` and up (since the desktop side-rail takes over). See §8 for
the component contract.

---

## 3. Routing & live_session

### 3.1 Final router

The router uses **three** `live_session`s: `:public` (unauthenticated
landing), `:authenticated_today` (authenticated, off-shift allowed — Today
only), and `:authenticated_on_shift` (authenticated and on shift —
everything else). This replaces the v1 attempt at a single authenticated
session with `socket.view` introspection — the latter is not a stable
LiveView 1.1 contract.

```elixir
defmodule FoyerWeb.Router do
  use FoyerWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FoyerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user        # custom plug — see §3.3
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", FoyerWeb do
    pipe_through :browser

    # POC user picker — unauthenticated landing.
    live_session :public,
      on_mount: [{FoyerWeb.UserAuth, :mount_public}] do
      live "/", UserPickerLive, :index
    end

    # Authenticated but off-shift allowed: Today only.
    live_session :authenticated_today,
      on_mount: [{FoyerWeb.UserAuth, :ensure_authenticated}] do
      live "/today",                       TodayLive,        :index
      live "/today/end-shift",             TodayLive,        :end_shift
    end

    # Authenticated AND on shift. Off-shift users are redirected to /today.
    live_session :authenticated_on_shift,
      on_mount: [{FoyerWeb.UserAuth, :ensure_on_shift}] do
      live "/house",                       HouseLive,        :index
      live "/house/new",                   HouseLive,        :compose
      live "/house/:id",                   AnnouncementLive, :show
      live "/chat",                        ChatLive,         :inbox
      live "/chat/new",                    ChatLive,         :new_message
      live "/chat/:conversation_id",       ChatRoomLive,     :show
      live "/recognize",                   RecognizeLive,    :new
      live "/me",                          ProfileLive,      :me
      live "/people",                      PeopleLive,       :index
      live "/people/:id",                  ProfileLive,      :show
    end

    # POC session helpers — controllers, not LiveViews, because they mutate
    # the session and then redirect.
    post "/session/pick/:user_id", SessionController, :pick
    delete "/session",             SessionController, :sign_out
  end

  if Application.compile_env(:foyer, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser
      live_dashboard "/dashboard", metrics: FoyerWeb.Telemetry
    end
  end
end
```

### 3.2 `fetch_current_user/2` plug

Lives in `lib/foyer_web/user_auth.ex`. Reads `:current_user_id` from session,
loads the user (and their current shift) via `Foyer.Accounts.get_user!/1`, and
assigns `conn.assigns[:current_user]` and `conn.assigns[:current_shift]`. If the
session is empty, assigns nil for both — the LiveView `on_mount` handles the
redirect, not the plug, so HTTP-rendered LiveView mount has access to the same
state as the websocket mount.

### 3.3 `on_mount` hooks — three clauses

Three clauses on a single `FoyerWeb.UserAuth` module. No route introspection
required — the live_session block decides which clause runs.

```elixir
defmodule FoyerWeb.UserAuth do
  use FoyerWeb, :verified_routes

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [redirect: 2, put_flash: 3]

  alias Foyer.Accounts
  alias Foyer.Shifts
  alias FoyerWeb.Scope

  @spec on_mount(atom(), map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()} | {:halt, Phoenix.LiveView.Socket.t()}
  def on_mount(:mount_public, _params, session, socket) do
    {:cont, assign(socket, :current_scope, load_scope(session))}
  end

  def on_mount(:ensure_authenticated, _params, session, socket) do
    case load_scope(session) do
      nil ->
        {:halt,
         socket
         |> put_flash(:error, "Please pick a user.")
         |> redirect(to: ~p"/")}

      %Scope{} = scope ->
        {:cont, assign(socket, :current_scope, scope)}
    end
  end

  def on_mount(:ensure_on_shift, _params, session, socket) do
    case load_scope(session) do
      nil ->
        {:halt,
         socket
         |> put_flash(:error, "Please pick a user.")
         |> redirect(to: ~p"/")}

      %Scope{on_shift?: false} ->
        {:halt,
         socket
         |> put_flash(:info, "Start your shift to enter the rest of Foyer.")
         |> redirect(to: ~p"/today")}

      %Scope{} = scope ->
        {:cont, assign(socket, :current_scope, scope)}
    end
  end
end
```

Notes:

- The off-shift gate is enforced at the **route level** by
  `:ensure_on_shift`. A `live(conn, ~p"/house")` call from an off-shift user
  returns `{:error, {:redirect, %{to: "/today"}}}` (NOT `:live_redirect` —
  that variant is deprecated and not what `on_mount` redirects produce).
- `put_flash/3` is allowed before `redirect/2` in `on_mount`.
- The picker (`/`) uses `:mount_public` so it does not loop on itself.
- Defence in depth: the bottom-nav (§8) also renders House/Chat/Me as
  disabled buttons when `scope.on_shift?` is false, so clicking is prevented
  in the UI before the route guard fires. The route guard catches direct
  navigation / typed URLs / bookmarks.

---

## 4. Scope module

Lives in `lib/foyer_web/scope.ex`.

```elixir
defmodule FoyerWeb.Scope do
  @moduledoc """
  The per-connection scope. Built once in the on_mount hook and threaded into
  every LiveView template via `@current_scope`. Layouts and the bottom-nav
  read role and on-shift state from this struct.
  """
  use TypedStruct

  alias Foyer.Accounts.User
  alias Foyer.Shifts.Shift

  typedstruct enforce: true do
    field :user, User.t()
    field :on_shift?, boolean()
    field :shift, Shift.t() | nil
    field :role, :manager | :staff
  end

  @spec for_user(User.t(), Shift.t() | nil) :: t()
  def for_user(%User{} = user, shift) do
    %__MODULE__{
      user: user,
      on_shift?: not is_nil(shift),
      shift: shift,
      role: user.role
    }
  end

  @spec manager?(t()) :: boolean()
  def manager?(%__MODULE__{role: :manager}), do: true
  def manager?(%__MODULE__{}), do: false
end
```

Then in `UserAuth` (one shared helper, used by all three `on_mount` clauses):

```elixir
defp load_scope(%{"current_user_id" => user_id}) when not is_nil(user_id) do
  case Foyer.Accounts.get_user(user_id) do
    nil ->
      nil

    %Foyer.Accounts.User{} = user ->
      shift = Foyer.Shifts.current_shift_for(user)
      FoyerWeb.Scope.for_user(user, shift)
  end
end
defp load_scope(_), do: nil
```

Yes, `Scope` uses `typed_struct` — see §13 step 1 for the dep and §15 for
the rationale. It's a small dep but the Foyer codebase will gain more DTOs
(`Foyer.Today.Briefing`, `Foyer.Profile.Card`), so introducing it here pays
off across the project.

The implementing agent must **add the `<Layouts.app flash={@flash}
current_scope={@current_scope}>` wrapper to every LiveView template** — this
is the v1.8 contract per AGENTS.md.

---

## 5. Data model

All schemas live in `lib/foyer/<context>/<schema>.ex`. Every schema declares
`@type t :: %__MODULE__{...}` directly under the `schema` block, per
`docs/ARCHITECTURE.md`.

### 5.1 Accounts.User — `lib/foyer/accounts/user.ex`

```elixir
defmodule Foyer.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          initials: String.t() | nil,
          role: :manager | :staff | nil,
          department: String.t() | nil,
          title: String.t() | nil,
          languages: [String.t()] | nil,
          points_balance: integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "users" do
    field :name, :string
    field :initials, :string
    field :role, Ecto.Enum, values: [:manager, :staff]
    field :department, :string
    field :title, :string
    field :languages, {:array, :string}, default: []
    field :points_balance, :integer, default: 0

    has_many :memberships, Foyer.Channels.Membership
    has_many :channels, through: [:memberships, :channel]

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :initials, :role, :department, :title, :languages, :points_balance])
    |> validate_required([:name, :initials, :role, :department, :title])
  end
end
```

### 5.2 Shifts.Shift — `lib/foyer/shifts/shift.ex`

```elixir
defmodule Foyer.Shifts.Shift do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          user_id: integer() | nil,
          started_at: DateTime.t() | nil,
          ended_at: DateTime.t() | nil,
          handoff_note: String.t() | nil,
          handoff_channel_id: integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "shifts" do
    belongs_to :user, Foyer.Accounts.User
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime
    field :handoff_note, :string
    belongs_to :handoff_channel, Foyer.Channels.Channel

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(shift, attrs) do
    shift
    |> cast(attrs, [:user_id, :started_at, :ended_at, :handoff_note, :handoff_channel_id])
    |> validate_required([:user_id, :started_at])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:handoff_channel_id)
  end
end
```

A user is **on shift iff** there is a `shifts` row with `user_id = ?` and
`ended_at IS NULL`. We do not store an `is_on_shift` boolean on User.

### 5.3 Channels.Channel — `lib/foyer/channels/channel.ex`

```elixir
defmodule Foyer.Channels.Channel do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          slug: String.t() | nil,
          kind: :department | :general | nil
        }

  schema "channels" do
    field :name, :string
    field :slug, :string
    field :kind, Ecto.Enum, values: [:department, :general]

    has_many :memberships, Foyer.Channels.Membership
    has_many :members, through: [:memberships, :user]

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(channel, attrs) do
    channel
    |> cast(attrs, [:name, :slug, :kind])
    |> validate_required([:name, :slug, :kind])
    |> unique_constraint(:slug)
  end
end
```

`member_count` is **not** stored on the schema (review §"Open Questions"):
denormalised counters are only worth carrying if the writes maintaining
them are implemented. Since channel membership writes are deferred to the
Channels feature group, the scaffold computes member counts at query time
(see §6.3 `list_all/1`). The desktop side-rail in §7.9 reads the count from
the projected query result, not from a column.

### 5.4 Channels.Membership — `lib/foyer/channels/membership.ex`

```elixir
defmodule Foyer.Channels.Membership do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          user_id: integer() | nil,
          channel_id: integer() | nil
        }

  schema "channel_memberships" do
    belongs_to :user, Foyer.Accounts.User
    belongs_to :channel, Foyer.Channels.Channel
    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(m, attrs) do
    m
    |> cast(attrs, [:user_id, :channel_id])
    |> validate_required([:user_id, :channel_id])
    |> unique_constraint([:user_id, :channel_id])
  end
end
```

### 5.5 House.Announcement — `lib/foyer/house/announcement.ex`

```elixir
defmodule Foyer.House.Announcement do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          author_id: integer() | nil,
          channel_id: integer() | nil,
          title: String.t() | nil,
          body: String.t() | nil,
          pinned_at: DateTime.t() | nil,
          requires_ack: boolean() | nil,
          published_at: DateTime.t() | nil
        }

  schema "announcements" do
    belongs_to :author, Foyer.Accounts.User
    belongs_to :channel, Foyer.Channels.Channel
    field :title, :string
    field :body, :string
    field :pinned_at, :utc_datetime
    field :requires_ack, :boolean, default: false
    field :published_at, :utc_datetime

    has_many :reads, Foyer.House.AnnouncementRead
    has_many :acks, Foyer.House.AnnouncementAck

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(a, attrs) do
    a
    |> cast(attrs, [:author_id, :channel_id, :title, :body, :pinned_at, :requires_ack, :published_at])
    |> validate_required([:author_id, :channel_id, :title, :body, :published_at])
  end
end
```

### 5.6 House.AnnouncementRead — `lib/foyer/house/announcement_read.ex`

```elixir
defmodule Foyer.House.AnnouncementRead do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          announcement_id: integer() | nil,
          user_id: integer() | nil,
          read_at: DateTime.t() | nil
        }

  schema "announcement_reads" do
    belongs_to :announcement, Foyer.House.Announcement
    belongs_to :user, Foyer.Accounts.User
    field :read_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(r, attrs) do
    r
    |> cast(attrs, [:announcement_id, :user_id, :read_at])
    |> validate_required([:announcement_id, :user_id, :read_at])
    |> unique_constraint([:announcement_id, :user_id])
  end
end
```

### 5.7 House.AnnouncementAck — `lib/foyer/house/announcement_ack.ex`

Same shape as Read but with `ack_at`.

### 5.8 Recognitions.Recognition — `lib/foyer/recognitions/recognition.ex`

```elixir
defmodule Foyer.Recognitions.Recognition do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          sender_id: integer() | nil,
          recipient_id: integer() | nil,
          body: String.t() | nil,
          values: [String.t()] | nil,
          bonus_points: integer() | nil,
          public: boolean() | nil,
          inserted_at: DateTime.t() | nil
        }

  @house_values ~w(care craft discretion initiative warmth excellence team)

  schema "recognitions" do
    belongs_to :sender, Foyer.Accounts.User
    belongs_to :recipient, Foyer.Accounts.User
    field :body, :string
    field :values, {:array, :string}, default: []
    field :bonus_points, :integer, default: 0
    field :public, :boolean, default: true

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @spec house_values() :: [String.t()]
  def house_values, do: @house_values

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(r, attrs) do
    r
    |> cast(attrs, [:sender_id, :recipient_id, :body, :values, :bonus_points, :public])
    |> validate_required([:sender_id, :recipient_id, :body])
    |> validate_subset(:values, @house_values)
    |> validate_number(:bonus_points, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
  end
end
```

`bonus_points` enforcement (only managers can set > 0) is in the context, not
the changeset — managers v staff isn't a field-level rule.

### 5.9 Chat.Conversation — `lib/foyer/chat/conversation.ex`

```elixir
defmodule Foyer.Chat.Conversation do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          kind: :direct | :channel | nil,
          channel_id: integer() | nil,
          direct_key: String.t() | nil,
          last_message_at: DateTime.t() | nil
        }

  schema "conversations" do
    field :kind, Ecto.Enum, values: [:direct, :channel]
    belongs_to :channel, Foyer.Channels.Channel
    field :direct_key, :string
    field :last_message_at, :utc_datetime

    has_many :participants, Foyer.Chat.Participant
    has_many :messages, Foyer.Chat.Message

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(c, attrs) do
    c
    |> cast(attrs, [:kind, :channel_id, :direct_key, :last_message_at])
    |> validate_required([:kind])
    |> validate_kind_channel_pair()
    |> maybe_put_direct_key(attrs)
    |> unique_constraint(:direct_key, name: :conversations_direct_key_unique)
    |> unique_constraint(:channel_id, name: :conversations_channel_id_unique)
    |> check_constraint(:kind, name: :conversation_kind_channel_pair)
  end

  defp validate_kind_channel_pair(cs) do
    case {get_field(cs, :kind), get_field(cs, :channel_id)} do
      {:channel, nil} -> add_error(cs, :channel_id, "required for channel conversations")
      {:direct, id} when not is_nil(id) -> add_error(cs, :channel_id, "must be nil for direct conversations")
      _ -> cs
    end
  end

  # Caller (Foyer.Chat.find_or_create_direct/2) is expected to pass the two
  # user_ids; we derive the canonical key here so callers do not have to
  # remember the min/max convention.
  defp maybe_put_direct_key(cs, %{participant_user_ids: [a, b]}) when is_integer(a) and is_integer(b) do
    [low, high] = Enum.sort([a, b])
    put_change(cs, :direct_key, "#{low}-#{high}")
  end
  defp maybe_put_direct_key(cs, _attrs), do: cs

  @spec direct_key([integer()]) :: String.t()
  def direct_key([a, b]) when is_integer(a) and is_integer(b) do
    [low, high] = Enum.sort([a, b])
    "#{low}-#{high}"
  end
end
```

Two denormalised fields and the rationale:

- `last_message_at` — for inbox sort. Maintained by `send_message/3` when
  feature groups implement it; seeds populate it.
- `direct_key` — canonical key for two-party DMs (e.g. `"5-12"`). Combined
  with a partial `unique_index` (§5.13), this prevents the app from creating
  two separate Maya↔Charlotte DMs by race or by bug.

### 5.10 Chat.Participant — `lib/foyer/chat/participant.ex`

For direct conversations only.

```elixir
defmodule Foyer.Chat.Participant do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          conversation_id: integer() | nil,
          user_id: integer() | nil
        }

  schema "conversation_participants" do
    belongs_to :conversation, Foyer.Chat.Conversation
    belongs_to :user, Foyer.Accounts.User
    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(p, attrs) do
    p
    |> cast(attrs, [:conversation_id, :user_id])
    |> validate_required([:conversation_id, :user_id])
    |> unique_constraint([:conversation_id, :user_id])
  end
end
```

### 5.11 Chat.Message — `lib/foyer/chat/message.ex`

```elixir
defmodule Foyer.Chat.Message do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          conversation_id: integer() | nil,
          author_id: integer() | nil,
          body: String.t() | nil,
          inserted_at: DateTime.t() | nil
        }

  schema "chat_messages" do
    belongs_to :conversation, Foyer.Chat.Conversation
    belongs_to :author, Foyer.Accounts.User
    field :body, :string

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(m, attrs) do
    m
    |> cast(attrs, [:conversation_id, :author_id, :body])
    |> validate_required([:conversation_id, :author_id, :body])
    |> validate_length(:body, min: 1, max: 4000)
  end
end
```

### 5.12 Chat.MessageRead — `lib/foyer/chat/message_read.ex`

```elixir
defmodule Foyer.Chat.MessageRead do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          message_id: integer() | nil,
          user_id: integer() | nil,
          read_at: DateTime.t() | nil
        }

  schema "chat_message_reads" do
    belongs_to :message, Foyer.Chat.Message
    belongs_to :user, Foyer.Accounts.User
    field :read_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(r, attrs) do
    r
    |> cast(attrs, [:message_id, :user_id, :read_at])
    |> validate_required([:message_id, :user_id, :read_at])
    |> unique_constraint([:message_id, :user_id])
  end
end
```

### 5.13 Migrations — chronological order

Run `mix ecto.gen.migration <name>` to get timestamps; the implementing agent
runs them **one at a time, in this order, in a single sitting** so the embedded
`YYYYMMDDHHMMSS_` prefixes increase monotonically.

1. `create_users` — `id`, `name :string null:false`, `initials :string null:false`,
   `role :string null:false`, `department :string null:false`, `title :string`,
   `languages {:array,:string} default:[]`, `points_balance :integer default:0 null:false`,
   `timestamps :utc_datetime`. Indexes: `index(:users, [:role])`.
2. `create_channels` — `id`, `name`, `slug` unique, `kind`, `member_count`,
   `timestamps`. Indexes: `unique_index(:channels, [:slug])`.
3. `create_channel_memberships` — `id`, `user_id` FK (`on_delete: :delete_all`),
   `channel_id` FK (`on_delete: :delete_all`), `timestamps`. Indexes:
   `unique_index(:channel_memberships, [:user_id, :channel_id])`,
   `index(:channel_memberships, [:channel_id])`.
4. `create_shifts` — `id`, `user_id` FK (`on_delete: :delete_all`), `started_at`
   (utc_datetime, null:false), `ended_at` (utc_datetime, null:true),
   `handoff_note :text`, `handoff_channel_id` FK to channels
   (`on_delete: :nilify_all`), `timestamps`. Indexes:
   - `index(:shifts, [:user_id, :ended_at])` (covers "current shift" lookup)
   - `index(:shifts, [:handoff_channel_id, :ended_at])` (drives `last_handoff_for/1`)
   - **`unique_index(:shifts, [:user_id], where: "ended_at IS NULL", name: :shifts_one_open_shift_per_user)`**
     — enforces "at most one open shift per user" at the DB layer, so
     `start_shift/1` cannot accidentally race itself into duplicate open
     shifts.
5. `create_announcements` — `id`, `author_id` FK, `channel_id` FK,
   `title :string`, `body :text`, `pinned_at`, `requires_ack :boolean
   default:false null:false`, `published_at`, `timestamps`. Indexes:
   - `index(:announcements, [:channel_id, :pinned_at, :published_at])`
     (covers the feed ordering — `pinned_at desc nulls last, published_at desc`)
   - `index(:announcements, [:author_id])`
   - **Partial pinned index** for the global pinned-feed query:
     ```elixir
     create index(:announcements, [:pinned_at, :published_at],
              where: "pinned_at IS NOT NULL",
              name: :announcements_pinned_feed_index)
     ```
6. `create_announcement_reads` — `id`, `announcement_id` FK, `user_id` FK,
   `read_at`, `timestamps`. Indexes:
   `unique_index(:announcement_reads, [:announcement_id, :user_id],
   name: :announcement_reads_announcement_id_user_id_index)`,
   `index(:announcement_reads, [:user_id])`.
7. `create_announcement_acks` — same shape as reads, `ack_at` instead of
   `read_at`. Unique index named explicitly so the changeset's
   `unique_constraint([:announcement_id, :user_id])` can name it.
8. `create_recognitions` — `id`, `sender_id` FK, `recipient_id` FK,
   `body :text`, `values {:array,:string} default:[]`, **`bonus_points :integer
   default: 0, null: false`**, `public :boolean default:true null:false`,
   `timestamps inserted_at_only`. Indexes + constraints:
   - `index(:recognitions, [:recipient_id, :inserted_at])`
   - `index(:recognitions, [:sender_id])`
   - `index(:recognitions, [:public, :inserted_at])`
   - **`create constraint(:recognitions, :bonus_points_non_negative, check: "bonus_points >= 0")`**
9. `create_conversations` — `id`, `kind :string null:false`, `channel_id` FK
   (`on_delete: :delete_all`), `last_message_at`, **`direct_key :string`**
   (denormalised canonical key for DMs — see §5.9 for derivation),
   `timestamps`. Indexes + constraints:
   - `index(:conversations, [:last_message_at])`
   - `unique_index(:conversations, [:channel_id], where: "kind = 'channel'",
     name: :conversations_channel_id_unique)`
   - **`unique_index(:conversations, [:direct_key], where: "kind = 'direct'",
     name: :conversations_direct_key_unique)`** — prevents duplicate Maya↔Charlotte DMs.
   - **`create constraint(:conversations, :conversation_kind_channel_pair,
     check: "(kind = 'channel' AND channel_id IS NOT NULL) OR (kind = 'direct' AND channel_id IS NULL)")`**
   - **`create constraint(:conversations, :conversation_kind_enum,
     check: "kind IN ('direct', 'channel')")`** — defence in depth around the Ecto.Enum.
10. `create_conversation_participants` — `id`, `conversation_id` FK
    (`on_delete: :delete_all`), `user_id` FK (`on_delete: :delete_all`),
    `timestamps`. Indexes:
    `unique_index(:conversation_participants, [:conversation_id, :user_id])`,
    `index(:conversation_participants, [:user_id, :conversation_id])`
    (covers inbox-side lookup `where p.user_id = ?`).
11. `create_chat_messages` — `id`, `conversation_id` FK
    (`on_delete: :delete_all`), `author_id` FK, `body :text null:false`,
    `timestamps inserted_at_only`. Indexes:
    `index(:chat_messages, [:conversation_id, :inserted_at])`,
    `index(:chat_messages, [:author_id])`.
12. `create_chat_message_reads` — `id`, `message_id` FK
    (`on_delete: :delete_all`), `user_id` FK, `read_at`, `timestamps`. Indexes:
    `unique_index(:chat_message_reads, [:message_id, :user_id])`,
    `index(:chat_message_reads, [:user_id])`.
13. (Also in 3 — restated for emphasis) Channel memberships unique index
    named explicitly so the changeset can refer to it:
    `unique_index(:channel_memberships, [:user_id, :channel_id],
    name: :channel_memberships_user_id_channel_id_index)`.

All migrations use `change/0` (reversible). No data migrations in this plan.

#### Member counts

Per the review's open question: **denormalised `member_count` is removed
from the migration and schema** until membership writes exist that can
maintain it (deferred to the Channels feature group). The People Directory
and the audience picker compute `member_count` at query time
(`select: count(m.id)` over `channel_memberships`). See §5.3 for the
schema change.

---

## 6. Contexts & context behaviors

Every context module lives at `lib/foyer/<context>.ex`, schemas under
`lib/foyer/<context>/<schema>.ex`. Every port lives at
`lib/foyer/<context>/behavior.ex`.

For each context, the plan documents:

- **Port `@callback`s** — the only functions LiveViews call through `LiveDeps`.
- **Public `@spec`s on the real context** (includes everything the port declares,
  plus a few `*_changeset/2` helpers used by LiveView forms).
- **Implementation tag** — for each function: `:real` (implemented against
  Repo) or `:stub` (raises `RuntimeError`, "TODO: implemented in feature-group
  <X>"). Reads are real; most writes are stubs except shift start/end and
  announcement ack/read, which the smoke test exercises.

### 6.1 Foyer.Accounts — `lib/foyer/accounts.ex` + `lib/foyer/accounts/behavior.ex`

```elixir
defmodule Foyer.Accounts.Behavior do
  alias Foyer.Accounts.User

  @callback list_pickable_users() :: [User.t()]
  @callback get_user!(integer() | String.t()) :: User.t()
  @callback get_user(integer() | String.t()) :: User.t() | nil
  @callback list_people(opts :: keyword()) :: [User.t()]
end

defmodule Foyer.Accounts do
  @behaviour Foyer.Accounts.Behavior

  @spec list_pickable_users() :: [Accounts.User.t()]   # :real — for /
  @spec get_user!(integer() | String.t()) :: Accounts.User.t()  # :real
  @spec get_user(integer() | String.t()) :: Accounts.User.t() | nil  # :real — UserAuth.load_scope/1 uses this
  @spec list_people(keyword()) :: [Accounts.User.t()]  # :real — for /people
  @spec current_shift_for(Accounts.User.t()) :: Shifts.Shift.t() | nil  # :real (delegates to Shifts)
end
```

`list_people/1` returns users with their memberships **fully preloaded**
(channel included), so the People Directory template can render
`p.memberships |> Enum.map(& &1.channel.name)` without an N+1 walk. The
open-shift state is joined into the result with a `left_join` (or returned
via a projected DTO if the agent prefers — both options are fine).

```elixir
@spec list_people(keyword()) :: [User.t()]
def list_people(_opts \\ []) do
  from(u in User,
    order_by: [asc: u.name],
    preload: [memberships: :channel]
  )
  |> Repo.all()
end
```

The desktop directory's "On shift" pills are driven by a separate cheap
lookup: `Shifts.users_on_shift_ids/0` returns a `MapSet` of user_ids with
open shifts, and the template checks `MapSet.member?(on_shift_ids, p.id)`.
This keeps the people query simple and avoids a complex `left_join` to
`shifts` with a `WHERE ended_at IS NULL`.

### 6.2 Foyer.Shifts — `lib/foyer/shifts.ex` + `lib/foyer/shifts/behavior.ex`

```elixir
defmodule Foyer.Shifts.Behavior do
  alias Foyer.Accounts.User
  alias Foyer.Shifts.Shift

  @callback current_shift_for(User.t()) :: Shift.t() | nil
  @callback last_handoff_for(User.t()) :: Shift.t() | nil
  @callback users_on_shift_ids() :: MapSet.t(integer())
  @callback start_shift(User.t()) :: {:ok, Shift.t()} | {:error, Ecto.Changeset.t()}
  @callback end_shift(Shift.t(), attrs :: map()) :: {:ok, Shift.t()} | {:error, Ecto.Changeset.t()}
end
```

- `current_shift_for/1` — :real. `from s in Shift, where: s.user_id == ^uid and is_nil(s.ended_at), order_by: [desc: s.started_at], limit: 1` and preload `:handoff_channel`.
- `last_handoff_for/1` — :real. Most recent **other user's** shift that
  ended in the last 24h on a channel the given user is a member of, ordered
  by `ended_at desc`, preload `:user, :handoff_channel`. This drives Today's
  "Handoff from your last shift" card. For the scaffold, it's keyed by the
  user's home department channel (look up the seeded Floor 4 channel for
  Maya, see §9). Backed by `index(:shifts, [:handoff_channel_id, :ended_at])`.
- `users_on_shift_ids/0` — :real. `from s in Shift, where: is_nil(s.ended_at),
  select: s.user_id` → `MapSet.new/1`. Used by `Accounts.list_people/1` and
  the People Directory template to render on-shift pulses without N+1.
- `start_shift/1` — :real. Insert `%Shift{user_id: ..., started_at:
  DateTime.utc_now()}`. The DB-level unique index
  `shifts_one_open_shift_per_user` is the canonical guard against duplicate
  open shifts; the changeset attaches `unique_constraint(:user_id, name:
  :shifts_one_open_shift_per_user)` so violations surface as
  `{:error, changeset}`, not raised exceptions.
- `end_shift/2` — :real. Update the given shift with `ended_at`,
  `handoff_note`, `handoff_channel_id`.

Both writes ARE implemented (not stubbed) because the smoke test toggles them.

### 6.3 Foyer.Channels — `lib/foyer/channels.ex` + `lib/foyer/channels/behavior.ex`

```elixir
defmodule Foyer.Channels.Behavior do
  alias Foyer.Accounts.User
  alias Foyer.Channels.Channel

  @callback list_for_user(User.t()) :: [Channel.t()]
  @callback list_all_with_member_counts() :: [{Channel.t(), non_neg_integer()}]
  @callback get!(integer() | String.t()) :: Channel.t()
end
```

All :real. `list_for_user/1` joins memberships, returns ordered by name.
`list_all_with_member_counts/0` is the audience picker source — it returns
tuples `{%Channel{}, count}` from a single query joining `channels` to a
grouped `channel_memberships` subquery, since `member_count` is no longer
denormalised on the schema (see §5.3).

### 6.4 Foyer.House — `lib/foyer/house.ex` + `lib/foyer/house/behavior.ex`

```elixir
defmodule Foyer.House.Behavior do
  alias Foyer.Accounts.User
  alias Foyer.House.Announcement

  @callback feed_for(User.t(), opts :: keyword()) :: [Announcement.t()]
  @callback list_pinned_for(User.t()) :: [Announcement.t()]
  @callback get_announcement!(integer() | String.t(), User.t()) :: Announcement.t()
  @callback acknowledge(Announcement.t(), User.t()) :: {:ok, term()} | {:error, term()}
  @callback mark_read(Announcement.t(), User.t()) :: {:ok, term()} | {:error, term()}
  @callback compose_changeset(map()) :: Ecto.Changeset.t()
  @callback create_announcement(User.t(), map()) :: {:ok, Announcement.t()} | {:error, Ecto.Changeset.t()}
  @callback needs_ack_from(User.t()) :: [Announcement.t()]
end
```

- `feed_for/2` — :real. Returns announcements where `channel_id` is in the
  user's memberships, ordered `pinned_at desc nulls last, published_at desc`.
  Preloads `:author, :channel, :acks, :reads`. Backed by
  `index(:announcements, [:channel_id, :pinned_at, :published_at])`.
- `list_pinned_for/1` — :real, filtered subset of `feed_for/2`, uses the
  partial `announcements_pinned_feed_index`.
- `get_announcement!/2` — :real, **with membership authorization baked
  in**. Maya cannot open a Leadership-only announcement she is not a member
  of — the query raises `Ecto.NoResultsError` (caller is responsible for
  redirect/flash). Spec:

  ```elixir
  @spec get_announcement!(integer() | String.t(), User.t()) :: Announcement.t()
  def get_announcement!(id, %User{id: user_id}) do
    from(a in Announcement,
      join: m in Foyer.Channels.Membership,
        on: m.channel_id == a.channel_id and m.user_id == ^user_id,
      where: a.id == ^id,
      preload: [:author, :channel, :reads, :acks]
    )
    |> Repo.one!()
  end
  ```

  AnnouncementLive's `handle_params/3` rescues `Ecto.NoResultsError` and
  redirects to `/house` with a flash. The smoke test exercises this path
  (§10).
- `acknowledge/2`, `mark_read/2` — :real. `Repo.insert/2` with the unique
  index handling the idempotency.
- `compose_changeset/1` — :real. Returns `Announcement.changeset/2` over an
  empty struct.
- `create_announcement/2` — **:stub**. Raises with `"TODO: implemented in
  feature-group house"`. The compose LiveView's submit handler catches the
  flash anyway (see §7.3) — the stub is never actually called in the smoke
  test because the test only opens the form, doesn't submit. Justification
  in §14: write paths beyond shift/ack require business rules
  (audience-target validation, grace window, etc.) that belong with the
  feature group.
- `needs_ack_from/1` — :real. Subquery for Today's "Needs your
  acknowledgement" section.

### 6.5 Foyer.Recognitions — `lib/foyer/recognitions.ex` + `lib/foyer/recognitions/behavior.ex`

```elixir
defmodule Foyer.Recognitions.Behavior do
  alias Foyer.Accounts.User
  alias Foyer.Recognitions.Recognition

  @callback feed_public(opts :: keyword()) :: [Recognition.t()]
  @callback received_by(User.t()) :: [Recognition.t()]
  @callback given_by(User.t()) :: [Recognition.t()]
  @callback compose_changeset(map()) :: Ecto.Changeset.t()
  @callback give(User.t(), map()) :: {:ok, Recognition.t()} | {:error, Ecto.Changeset.t()}
end
```

- `feed_public/1` — :real. `public: true`, ordered `inserted_at desc`,
  preload `:sender, :recipient`.
- `received_by/1`, `given_by/1` — :real.
- `compose_changeset/1` — :real.
- `give/2` — **:stub**. Same reasoning as `create_announcement/2`.

### 6.6 Foyer.Chat — `lib/foyer/chat.ex` + `lib/foyer/chat/behavior.ex`

```elixir
defmodule Foyer.Chat.Behavior do
  alias Foyer.Accounts.User
  alias Foyer.Chat.{Conversation, Message}

  @callback inbox_for(User.t()) :: [Conversation.t()]
  @callback get_conversation!(integer() | String.t(), User.t()) :: Conversation.t()
  @callback list_messages(Conversation.t()) :: [Message.t()]
  @callback compose_changeset(map()) :: Ecto.Changeset.t()
  @callback send_message(Conversation.t(), User.t(), map()) :: {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
end
```

- `inbox_for/1` — :real. Both direct conversations the user participates in
  and channel conversations for channels the user is a member of. Filter
  `last_message_at IS NOT NULL` (designs note empty convos are hidden).
  Order `last_message_at desc`. Preloads:
  - for `:direct` — the other participant (`participants: :user`)
  - for `:channel` — the channel
  - latest message — fetched in **one extra query** using Postgres
    `DISTINCT ON (conversation_id)` over the conversation_ids returned by
    the first query, ordered by `inserted_at desc`. Result is zipped into
    the conversation list in Elixir (single pass, no N+1). Spelled out:

    ```elixir
    @spec inbox_for(User.t()) :: [Conversation.t()]
    def inbox_for(%User{id: user_id}) do
      conversations =
        from(c in Conversation,
          left_join: p in Foyer.Chat.Participant,
            on: p.conversation_id == c.id and p.user_id == ^user_id,
          left_join: m in Foyer.Channels.Membership,
            on: m.channel_id == c.channel_id and m.user_id == ^user_id,
          where: not is_nil(c.last_message_at)
                 and (not is_nil(p.id) or not is_nil(m.id)),
          order_by: [desc: c.last_message_at],
          preload: [:channel, participants: :user]
        )
        |> Repo.all()

      conv_ids = Enum.map(conversations, & &1.id)

      latest_by_id =
        from(msg in Foyer.Chat.Message,
          where: msg.conversation_id in ^conv_ids,
          distinct: msg.conversation_id,
          order_by: [asc: msg.conversation_id, desc: msg.inserted_at]
        )
        |> Repo.all()
        |> Map.new(&{&1.conversation_id, &1})

      Enum.map(conversations, fn c ->
        %{c | messages: [Map.get(latest_by_id, c.id)] |> Enum.reject(&is_nil/1)}
      end)
    end
    ```

    Backed by `index(:chat_messages, [:conversation_id, :inserted_at])` and
    `index(:conversation_participants, [:user_id, :conversation_id])`.
- `get_conversation!/2` — :real, **with membership authorization baked in**.
  Direct conversations require the user to be a participant; channel
  conversations require the user to be a channel member.

  ```elixir
  @spec get_conversation!(integer() | String.t(), User.t()) :: Conversation.t()
  def get_conversation!(id, %User{id: user_id}) do
    from(c in Conversation,
      left_join: p in Foyer.Chat.Participant,
        on: p.conversation_id == c.id and p.user_id == ^user_id,
      left_join: m in Foyer.Channels.Membership,
        on: m.channel_id == c.channel_id and m.user_id == ^user_id,
      where: c.id == ^id and (not is_nil(p.id) or not is_nil(m.id)),
      preload: [:channel, participants: :user]
    )
    |> Repo.one!()
  end
  ```

  ChatRoomLive's `handle_params/3` rescues `Ecto.NoResultsError` and
  redirects to `/chat`.
- `list_messages/1` — :real. `order_by inserted_at asc`, preload `:author`.
- `compose_changeset/1` — :real, returns Message changeset.
- `send_message/3` — **:stub**.

### 6.7 Foyer.Profile — `lib/foyer/profile.ex` + `lib/foyer/profile/behavior.ex`

Profile context is **read-only** and **wraps Accounts + Recognitions**, so the
ProfileLive doesn't have to depend on two contexts directly (keeps LiveView
slim per ARCHITECTURE.md "fat contexts").

Profile returns a **typed DTO**, not a bare map, per ARCHITECTURE.md's
"typed boundaries, no bare maps" rule. The DTO lives at
`lib/foyer/profile/card.ex`:

```elixir
defmodule Foyer.Profile.Card do
  @moduledoc """
  Read-model returned by `Foyer.Profile.profile_for/1`. The shape consumed
  by `FoyerWeb.ProfileLive`.
  """
  use TypedStruct

  alias Foyer.Accounts.User
  alias Foyer.Recognitions.Recognition

  typedstruct enforce: true do
    field :user, User.t()
    field :received, [Recognition.t()]
    field :given, [Recognition.t()]
    field :points, integer()
    field :on_shift?, boolean()
  end
end
```

```elixir
defmodule Foyer.Profile.Behavior do
  alias Foyer.Accounts.User
  alias Foyer.Profile.Card

  @callback profile_for(User.t()) :: Card.t()
end
```

`profile_for/1` is :real — composes `Accounts.get_user!`,
`Recognitions.received_by`, `Recognitions.given_by`, and
`Shifts.current_shift_for`, then builds a `%Card{}`.

### 6.8 Foyer.Today — `lib/foyer/today.ex` + `lib/foyer/today/behavior.ex`

`Foyer.Today` is the **read-only orchestrator** for the morning-briefing
surface. It is the only context in the codebase that calls cousin contexts
(Shifts, House, Recognitions); we accept this targeted exception to
ARCHITECTURE.md's "no cousin calls" rule because:

- TodayLive needs an aggregated view across three sibling domains.
- Pushing the aggregation into TodayLive violates "fat contexts, slim
  LiveViews" worse.
- The risk of an orchestrator god-object is bounded by keeping Today
  strictly **read-only**: it has no `start_shift`, no `acknowledge`, no
  `give_recognition`. Writes still flow to the owning context's port
  directly from the relevant LiveView event handler.

See §14 (Risks) for the trade-off acknowledgement.

The briefing is returned as a **typed DTO** (`Foyer.Today.Briefing`), not a
bare map:

```elixir
defmodule Foyer.Today.Briefing do
  @moduledoc """
  Aggregated morning-briefing read-model. Returned by
  `Foyer.Today.brief_for/1`.
  """
  use TypedStruct

  alias Foyer.Accounts.User
  alias Foyer.Shifts.Shift
  alias Foyer.House.Announcement
  alias Foyer.Recognitions.Recognition

  typedstruct enforce: true do
    field :user, User.t()
    field :shift, Shift.t() | nil
    field :on_shift?, boolean()
    field :handoff, Shift.t() | nil
    field :needs_ack, [Announcement.t()]
    field :recent_recognition, [Recognition.t()]
    field :waiting_count, non_neg_integer()
  end
end
```

```elixir
defmodule Foyer.Today.Behavior do
  alias Foyer.Accounts.User
  alias Foyer.Today.Briefing

  @callback brief_for(User.t()) :: Briefing.t()
end
```

`brief_for/1` is :real — assembles the struct by calling `Shifts`, `House`,
and `Recognitions`. `waiting_count` is `length(needs_ack)` for the scaffold.

### 6.9 LiveDeps additions

`lib/foyer_web/live_deps.ex` adds one accessor per context above:

```elixir
defmodule FoyerWeb.LiveDeps do
  def accounts,     do: Application.fetch_env!(:foyer, :accounts_context)
  def shifts,       do: Application.fetch_env!(:foyer, :shifts_context)
  def channels,     do: Application.fetch_env!(:foyer, :channels_context)
  def house,        do: Application.fetch_env!(:foyer, :house_context)
  def recognitions, do: Application.fetch_env!(:foyer, :recognitions_context)
  def chat,         do: Application.fetch_env!(:foyer, :chat_context)
  def profile,      do: Application.fetch_env!(:foyer, :profile_context)
  def today,        do: Application.fetch_env!(:foyer, :today_context)
end
```

Keep the module's existing `@moduledoc` intact.

---

## 7. LiveViews

Conventions for every LiveView:

- File: `lib/foyer_web/live/<name>_live.ex`. Single module, template inline via
  `~H` (no separate `.html.heex` file — keeps the module under ~150 LOC and
  matches the rest of the LiveView surface).
- `mount/3`: cheap — only `assign/3` of UI defaults and form initialization;
  PubSub `subscribe/1` calls if needed (Chat only).
- `handle_params/3`: every database load, every port call, lives here.
- `current_scope` is read from socket assigns via `socket.assigns.current_scope`.
- Every template starts with `<Layouts.app flash={@flash} current_scope={@current_scope}>`.

### 7.1 FoyerWeb.UserPickerLive — `/`

Per ARCHITECTURE.md, data loading lives in `handle_params/3`, not `mount/3`
— even for a cheap query, so the rule stays consistent across LiveViews.

```elixir
def mount(_params, _session, socket), do: {:ok, assign(socket, users: [])}

def handle_params(_params, _uri, socket) do
  {:noreply,
   assign(socket, :users, FoyerWeb.LiveDeps.accounts().list_pickable_users())}
end
```

Renders one row per user with a `<.form>` submit button. SessionController
puts `current_user_id` in the session and redirects to `/today`.

Template skeleton:

```elixir
~H"""
<Layouts.app flash={@flash} current_scope={@current_scope}>
  <main class="foyer-root">
    <div class="foyer-scroll" id="user-picker">
      <div class="foyer-mono">Foyer - The Linden, Mayfair, London</div>
      <h1 class="foyer-serif text-3xl">Pick a user</h1>
      <p class="text-foyer-ink-soft">POC demo - no password.</p>
      <ul class="flex flex-col gap-2">
        <li :for={u <- @users}>
          <.form for={%{} |> to_form()} id={"pick-#{u.id}"} action={~p"/session/pick/#{u.id}"} method="post">
            <button
              class="foyer-btn w-full text-left"
              id={"pick-btn-#{u.id}"}
              type="submit"
            >
              <span class="foyer-avatar">{u.initials}</span>
              <span class="flex-1">
                <span class="foyer-serif">{u.name}</span>
                <span class="foyer-mono block">{u.title}</span>
              </span>
            </button>
          </.form>
        </li>
      </ul>
    </div>
  </main>
</Layouts.app>
"""
```

Note the `type="submit"` on the button — it's the default for buttons
inside `<form>`, but AGENTS.md asks for explicit attributes on key
interactive elements. The button also carries a stable `id` so smoke /
isolated tests can `element("#pick-btn-#{maya.id}")` reliably.

### 7.2 FoyerWeb.TodayLive — `/today` and `/today/end-shift`

Mount: `assign(socket, briefing: nil, end_shift_form: nil)`.

`handle_params/3`:

- For `:index`: `briefing = LiveDeps.today().brief_for(scope.user)` (returns
  `%Foyer.Today.Briefing{}`).
- For `:end_shift`: load briefing as above + initialise `end_shift_form` from
  a `Shift.changeset(%Shift{}, %{handoff_channel_id: nil, handoff_note: ""})`.

Events:

- `"start_shift"` → `LiveDeps.shifts().start_shift(scope.user)`, then `push_navigate(socket, to: "/today")`.
- `"end_shift_submit"` → `LiveDeps.shifts().end_shift(scope.shift, params)`,
  then `push_navigate(socket, to: "/today")`.

Template skeleton (covers ALL three states: off-shift, on-shift staff, on-shift manager).
Renders branches with `cond` (Elixir does NOT support `else if`, per AGENTS.md):

```elixir
~H"""
<Layouts.app flash={@flash} current_scope={@current_scope}>
  <main class="foyer-root">
    <div class="foyer-scroll" id="today">
      <header class="flex items-start justify-between">
        <div>
          <div class="foyer-mono">{header_eyebrow(@current_scope)}</div>
          <h1 class="foyer-serif text-3xl">{greeting(@current_scope)}</h1>
        </div>
        <div class="flex gap-2">
          <button aria-label="Search" class="foyer-btn ghost sm">
            <.icon name="hero-magnifying-glass" class="size-5" />
          </button>
          <button aria-label="Notifications" class="foyer-btn ghost sm">
            <.icon name="hero-bell" class="size-5" />
          </button>
        </div>
      </header>

      <%= cond do %>
        <% not @current_scope.on_shift? -> %>
          <section id="off-shift" class="bg-foyer-cream-deep rounded-lg p-4 flex flex-col gap-3">
            <div class="flex items-center gap-2">
              <span class="foyer-tag outline">Off shift · notifications paused</span>
            </div>
            <p class="foyer-serif text-xl">
              You're off the clock.<br /><em>Rest is part of the work.</em>
            </p>
            <p>You won't receive notifications until you start your next shift.</p>
            <button class="foyer-btn forest" phx-click="start_shift" id="start-shift-btn">
              <span class="foyer-pulse"></span>Start shift
            </button>
            <div class="foyer-mono">While you were off · {@briefing.waiting_count} waiting</div>
          </section>

        <% FoyerWeb.Scope.manager?(@current_scope) -> %>
          <section id="manager-today" class="flex flex-col gap-3">
            <div class="flex items-center gap-3">
              <span class="foyer-pulse"></span>
              <div>On shift · {@current_scope.user.title}</div>
              <.link patch={~p"/today/end-shift"} class="foyer-btn sm ml-auto">End shift</.link>
            </div>
            <.link navigate={~p"/house/new"} id="compose-cta" class="foyer-btn forest">
              <.icon name="hero-pencil-square" class="size-4" />
              New announcement
            </.link>
            <%!-- live posts list + acks-you-owe list, both rendered from @briefing --%>
          </section>

        <% true -> %>
          <section id="on-shift-staff" class="flex flex-col gap-3">
            <div class="flex items-center gap-3">
              <span class="foyer-pulse"></span>
              <div>On shift · {@current_scope.user.title}</div>
              <.link patch={~p"/today/end-shift"} class="foyer-btn sm ml-auto" id="end-shift-link">
                End shift
              </.link>
            </div>
            <div :if={@briefing.handoff} id="handoff-card" class="rounded-lg border border-foyer-rule p-3">
              <div class="foyer-mono">Handoff from your last shift</div>
              <div class="flex items-center gap-2 mt-2">
                <span class="foyer-avatar">{@briefing.handoff.user.initials}</span>
                <div>
                  <div>{@briefing.handoff.user.name}</div>
                  <div class="foyer-mono">Night · ended {format_time(@briefing.handoff.ended_at)}</div>
                </div>
              </div>
              <p class="foyer-serif mt-2">"{@briefing.handoff.handoff_note}"</p>
            </div>
            <div :if={@briefing.needs_ack != []} id="needs-ack">
              <div class="foyer-mono">Needs your acknowledgement</div>
              <.link
                :for={a <- @briefing.needs_ack}
                navigate={~p"/house/#{a.id}"}
                id={"needs-ack-#{a.id}"}
                class="block rounded-lg border border-foyer-rule p-3 mt-2"
              >
                <span class="foyer-tag claret">Pinned · Action</span>
                <div class="foyer-serif mt-2">{a.title}</div>
                <div class="flex items-center gap-2 mt-2">
                  <span class="foyer-avatar sm">{a.author.initials}</span>
                  <span>{a.author.name} · {a.channel.name}</span>
                </div>
              </.link>
            </div>
          </section>
      <% end %>

      <%= if @live_action == :end_shift do %>
        <div id="end-shift-modal" class="rounded-lg border border-foyer-rule p-4 mt-4">
          <h2 class="foyer-serif text-xl">Anything the next shift needs to know?</h2>
          <.form
            for={@end_shift_form}
            id="end-shift-form"
            phx-submit="end_shift_submit"
            class="flex flex-col gap-3 mt-3"
          >
            <.input field={@end_shift_form[:handoff_note]} type="textarea" label="Handoff note" />
            <button class="foyer-btn forest sm" type="submit">Clock out</button>
          </.form>
        </div>
      <% end %>

      <FoyerWeb.FoyerComponents.bottom_nav active={:today} current_scope={@current_scope} />
    </div>
  </main>
</Layouts.app>
"""
```

Helpers `header_eyebrow/1`, `greeting/1`, `format_time/1` are private
functions on TodayLive.

### 7.3 FoyerWeb.HouseLive — `/house` and `/house/new`

Mount: `stream(socket, :feed, [])`.

`handle_params/3`:

- `:index`: `feed = LiveDeps.house().feed_for(scope.user)`, then
  `stream(socket, :feed, feed, reset: true)` + `assign(socket, :compose_form,
  nil)`. (Streams are mandatory for collections per AGENTS.md.)
- `:compose`: same feed plus:
  - `compose_form = to_form(LiveDeps.house().compose_changeset(%{}))`
  - `channels = LiveDeps.channels().list_for_user(scope.user)`
  - **`channel_options = Enum.map(channels, &{&1.name, &1.id})`** —
    pre-shaped here so the HEEx template stays declarative (no `Enum.map`
    in templates).

Events:

- `"compose_submit"` → calls `LiveDeps.house().create_announcement/2`. **Stub
  raises**, but the smoke test never submits this form, so this is fine.
  The submit handler wraps the call in `try/rescue RuntimeError ->
  put_flash(:info, "Compose not implemented in scaffold")` so a real user
  click doesn't 500.

Template skeleton:

```elixir
~H"""
<Layouts.app flash={@flash} current_scope={@current_scope}>
  <main class="foyer-root">
    <div class="foyer-scroll" id="house">
      <header class="flex items-start justify-between">
        <div>
          <div class="foyer-mono">The Linden · Mayfair, London</div>
          <h1 class="foyer-serif text-3xl">The House</h1>
        </div>
      </header>
      <div class="flex gap-2" role="tablist" id="house-filters">
        <button class="foyer-btn sm" id="filter-all">All</button>
        <button class="foyer-btn sm" id="filter-announcements">Announcements</button>
        <button class="foyer-btn sm" id="filter-recognition">Recognition</button>
      </div>
      <.link navigate={~p"/recognize"} id="recognize-cta" class="foyer-btn sm self-start">Recognize</.link>

      <div id="house-feed" phx-update="stream" class="flex flex-col gap-3">
        <div :for={{id, item} <- @streams.feed} id={id}>
          <FoyerWeb.FoyerComponents.announcement_card announcement={item} />
        </div>
      </div>

      <%= if @live_action == :compose do %>
        <div id="compose-panel" class="rounded-lg border border-foyer-rule p-4 mt-4">
          <h2 class="foyer-serif text-2xl">New announcement</h2>
          <.form for={@compose_form} id="compose-form" phx-submit="compose_submit" class="flex flex-col gap-3">
            <.input field={@compose_form[:title]} type="text" label="Title" />
            <.input field={@compose_form[:body]} type="textarea" label="The detail" />
            <.input
              field={@compose_form[:channel_id]}
              type="select"
              label="To - audience"
              options={@channel_options}
            />
            <button class="foyer-btn forest" type="submit">Publish</button>
          </.form>
        </div>
      <% end %>

      <FoyerWeb.FoyerComponents.bottom_nav active={:house} current_scope={@current_scope} />
    </div>
  </main>
</Layouts.app>
"""
```

### 7.4 FoyerWeb.AnnouncementLive — `/house/:id`

Mount: `assign(socket, announcement: nil)`.

`handle_params/3`: load announcement with membership-authorized
`get_announcement!/2` (§6.4). Rescue `Ecto.NoResultsError` and redirect to
`/house` with a flash — this is the unauthorized-access path the smoke
test exercises.

```elixir
def handle_params(%{"id" => id}, _uri, socket) do
  scope = socket.assigns.current_scope

  try do
    a = FoyerWeb.LiveDeps.house().get_announcement!(id, scope.user)
    FoyerWeb.LiveDeps.house().mark_read(a, scope.user)
    {:noreply, assign(socket, :announcement, a)}
  rescue
    Ecto.NoResultsError ->
      {:noreply,
       socket
       |> put_flash(:error, "That announcement is not available to you.")
       |> push_navigate(to: ~p"/house")}
  end
end
```

Events: `"acknowledge"` → `LiveDeps.house().acknowledge(a, scope.user)` +
`put_flash(:info, "Acknowledged")` + reload.

Template renders the title, author block, body, "Audience" tag, the "X / Y
team confirmed" pill, and the "I've read & understood" button (visible when
`a.requires_ack and current user has not acked`).

Critical strings to render (substring-safe): `Suite 412` + `Allergy
protocol in effect`, `Requires acknowledgement`, `I've read & understood`,
and `Acknowledged` after the ack click.

### 7.5 FoyerWeb.ChatLive — `/chat` and `/chat/new`

Mount: subscribe stub — the `:ensure_on_shift` hook runs first so
`socket.assigns.current_scope` is guaranteed when mount executes:

```elixir
def mount(_params, _session, socket) do
  if connected?(socket) do
    scope = socket.assigns.current_scope
    Phoenix.PubSub.subscribe(Foyer.PubSub, "chat:inbox:#{scope.user.id}")
  end

  {:ok, stream(socket, :conversations, [])}
end
```

(No publishes in v0 — but the subscribe path is exercised.)

`handle_params/3`:

- `:inbox`: `LiveDeps.chat().inbox_for(scope.user)` → `stream(:conversations, ...)`.
- `:new_message`: load `LiveDeps.accounts().list_people()` + `LiveDeps.channels().list_for_user(scope.user)`.

Template renders Pinned and All conversations groups, the search input, and the "New message" sheet
with People and Channels tabs.

### 7.6 FoyerWeb.ChatRoomLive — `/chat/:conversation_id`

Mount: subscribe `chat:room:<id>`, `stream(:messages, [])`.

`handle_params/3`: load conversation + messages via `LiveDeps.chat().list_messages/1`,
then `stream(socket, :messages, messages, reset: true)`.

Events:

- `"send_message"` → `LiveDeps.chat().send_message/3` (stub — same flash trick).

Template uses the streams pattern AGENTS.md mandates:

```heex
<div id="messages" phx-update="stream" class="flex flex-col gap-2">
  <div :for={{dom_id, msg} <- @streams.messages} id={dom_id}>
    <FoyerWeb.FoyerComponents.message_bubble message={msg} current_user_id={@current_scope.user.id} />
  </div>
</div>
```

### 7.7 FoyerWeb.RecognizeLive — `/recognize`

Mount: assign `form = to_form(LiveDeps.recognitions().compose_changeset(%{}))`,
`people = LiveDeps.accounts().list_people()`.

`handle_params/3`: no-op.

Events: `"give_submit"` → `LiveDeps.recognitions().give/2` (stub → flash).

Template renders the "To", "The story", "House values" (chips), "Visibility"
(public/private toggle), and — only when `FoyerWeb.Scope.manager?(@current_scope)`
— the "Bonus points" tier picker.

### 7.8 FoyerWeb.ProfileLive — `/me` and `/people/:id`

Mount: `assign(socket, card: nil)`.

`handle_params/3`:

- `:me` → `card = LiveDeps.profile().profile_for(scope.user)` (returns
  `%Foyer.Profile.Card{}`).
- `:show` → `target = LiveDeps.accounts().get_user!(id); card =
  LiveDeps.profile().profile_for(target)`.

Template renders the avatar + name + role + languages + on-shift tag + the
stats row (Recognitions this month, Ack on time placeholder), the
Received/Given tabs (just two `<div>`s in v0, no live filter), the points
balance, and the rewards catalog (six static cards, copy lifted directly from
`mobile-recognitions-received.html`).

### 7.9 FoyerWeb.PeopleLive — `/people`

Mount: `assign(socket, people: [])`.

`handle_params/3`: `LiveDeps.accounts().list_people()`.

Template uses the **desktop layout** — a side-rail on `md:` and up, the people
table on the right. On mobile, the side-rail is hidden and the table shows full
width. Each row is a `<.link navigate={~p"/people/#{p.id}"}>` so clicking a
person opens their profile.

---

## 8. Shared components

A single module `lib/foyer_web/components/foyer_components.ex` exports the
following components. Single module (not split into many files) — they're all
small and tightly coupled to the same visual vocabulary.

```elixir
defmodule FoyerWeb.FoyerComponents do
  use Phoenix.Component
  import FoyerWeb.CoreComponents, only: [icon: 1]

  alias FoyerWeb.Scope

  attr :active, :atom, required: true, values: [:today, :house, :chat, :me]
  attr :current_scope, FoyerWeb.Scope, required: true

  def bottom_nav(assigns)

  attr :initials, :string, required: true
  attr :size, :atom, default: :md, values: [:sm, :md, :lg]
  attr :class, :string, default: nil
  def avatar(assigns)

  attr :variant, :atom, required: true, values: [:claret, :moss, :forest, :outline]
  attr :class, :string, default: nil
  slot :inner_block, required: true
  def tag(assigns)

  attr :class, :string, default: nil
  slot :inner_block, required: true
  def section_label(assigns)   # the .foyer-mono small-caps eyebrow

  def pulse(assigns)

  attr :announcement, Foyer.House.Announcement, required: true
  def announcement_card(assigns)

  attr :recognition, Foyer.Recognitions.Recognition, required: true
  def recognition_card(assigns)

  attr :conversation, Foyer.Chat.Conversation, required: true
  def conversation_row(assigns)

  attr :message, Foyer.Chat.Message, required: true
  attr :current_user_id, :integer, required: true
  def message_bubble(assigns)
end
```

`bottom_nav/1` highlights the active tab and links to `/today`, `/house`,
`/chat`, `/me`. The four interactive elements carry **stable DOM IDs** so
tests can assert on them precisely:

- `#bottom-nav-today` (always an `<a>` or `<.link>`)
- `#bottom-nav-house`
- `#bottom-nav-chat`
- `#bottom-nav-me`

The visible labels "Today", "House", "Chat", "Me" sit inside the elements
(the smoke test asserts on the IDs, not on free-text matching against
"a, button").

When `current_scope.on_shift?` is false, House / Chat / Me render as
`<button id="bottom-nav-X" disabled aria-disabled="true">` instead of
`<.link>`. This is **belt-and-braces** with the route-level
`:ensure_on_shift` guard:

- The disabled button stops normal taps, so off-shift users do not generate
  pointless redirects from clicks.
- The route guard catches everything else — typed URLs, bookmarks,
  `push_navigate` calls, deep links from notifications.

The smoke test exercises both: it asserts the disabled state at `/today`
AND asserts the redirect when navigating to `/house` directly.

`announcement_card/1` renders the design's pinned/ack-required card. Includes
the "Pinned" tag (claret), title (`.foyer-serif`), body, audience line, and
either an "Acknowledge" button (when `requires_ack` and the announcement is
not yet acked by the viewer — but for the scaffold we always link to the
announcement detail page rather than handling ack inline) or a "View details"
link. Critical strings: `Pinned`, `Acknowledge`, the announcement title.

`recognition_card/1` renders the recognition glyph, "Recognition for <name>"
eyebrow, body, sender row.

`conversation_row/1` renders avatar/#, name, time, last message preview, and a
small unread dot when unread (placeholder boolean — wired up by feature group).

`message_bubble/1` renders one bubble, aligned right when `message.author_id ==
current_user_id`.

---

## 9. Seeds

`priv/repo/seeds.exs` is rewritten end-to-end. The file is **idempotent** —
it `Repo.delete_all/1` on every table before inserting. The file should
`import Ecto.Query` per AGENTS.md.

### 9.1 Property header

The string `"The Linden · Mayfair, London"` is rendered in `HouseLive` and
`UserPickerLive`. It is not stored in the DB (no `Property` schema in v0); it
is hard-coded in the template strings.

### 9.2 Channels (in order)

| slug | name | kind | seeded members |
| --- | --- | --- | --- |
| `housekeeping-floor-4` | Housekeeping · Floor 4 | department | Maya, Aisha, Hugo, Charlotte |
| `all-housekeeping` | All Housekeeping | department | Maya, Aisha, Charlotte, Jamal, Nina, Olu, Kasia |
| `f-and-b` | F&B | department | Sébastien, Elin |
| `concierge-front-office` | Concierge & Front Office | department | Tomás, Leila |
| `engineering` | Engineering | department | Hugo |
| `leadership` | Leadership | department | Charlotte, Rafael, Sébastien |
| `linden-all` | Linden · All staff | general | all 14 users |

`member_count` is set from the seeded count above.

### 9.3 Users (the full cast)

```
Maya Okafor — Senior Housekeeper · Floor 4 — staff — Housekeeping — EN, FR, YO — 245 pts
Charlotte Voss — Dir. of Housekeeping — manager — Housekeeping — EN, FR — 0 pts
Rafael Mendes — Night Manager — manager — Front Office — EN, PT, ES — 0 pts
Aisha Bello — Housekeeper · Fl. 4 — staff — Housekeeping — EN, YO — 60 pts
Tomás Ruiz — Concierge — staff — Front Office — EN, ES — 30 pts
Elin Larsen — F&B Captain — staff — F&B — EN, SV — 0 pts
Priya Shah — Spa Therapist — staff — Spa — EN, HI — 0 pts
Hugo Brandt — Engineering — staff — Engineering — EN, DE — 100 pts
Leila Haddad — Front Office — staff — Front Office — EN, AR, FR — 25 pts
Sébastien Roy — Executive Chef — manager — F&B — EN, FR — 0 pts
Jamal Mensah — Housekeeper · Fl. 2 — staff — Housekeeping — EN, TL — 0 pts
Nina Köhler — Housekeeper · Fl. 3 — staff — Housekeeping — EN, DE — 0 pts
Olu Sanya — Houseman — staff — Housekeeping — EN, YO — 0 pts
Kasia Piotrowska — Housekeeper · Fl. 5 — staff — Housekeeping — EN, PL — 0 pts
```

Initials are first letter of first name + first letter of last name. Insert
order is preserved so `id` is stable — the smoke test uses `Repo.get_by/2`
by name, not by hardcoded id.

### 9.4 Shifts

- **Maya** has an open shift (`started_at: 06:00 UTC today`, `ended_at: nil`).
- **Rafael** has a completed night shift (ended ~2h ago) with `handoff_note:
  "Rafael · 06:08 — quiet night, 206 settled."` and `handoff_channel_id:
  housekeeping-floor-4`.
- **Charlotte** has an open shift starting 07:30 today.
- **Aisha**, **Hugo**, **Tomás**, **Elin**, **Priya**, **Leila**, **Sébastien**:
  all currently on shift (open shifts started this morning).
- **Jamal**, **Nina**, **Olu**, **Kasia**: off shift (no open shifts; last
  ended yesterday).

This setup means the smoke test can pick **Maya for the on-shift staff path**,
**Charlotte for the manager path**, and **Jamal for the off-shift path**.

### 9.5 Announcements

- `Suite 412 — Allergy protocol in effect` — author Charlotte, channel
  `all-housekeeping`, `requires_ack: true`, `pinned_at: 07:42 today`,
  `published_at: 07:42 today`, body lifted from the design.
- `Truffle menu launches Thursday` — author Sébastien, channel `f-and-b`,
  yesterday's date, not pinned, `requires_ack: false`.
- `Reminder — the new umbrella stand` — author Tomás, channel
  `concierge-front-office`, two days ago, not pinned.
- `New uniform supplier — measurements by Friday` — author Charlotte,
  channel `all-housekeeping`, yesterday, not pinned, `requires_ack: true`.

For `Suite 412`: insert 2 `AnnouncementAck` rows (for Aisha and Hugo). Insert
3 `AnnouncementRead` rows (the two ackers + Rafael).

### 9.6 Recognitions

- Rafael → Maya, yesterday, public, values `["care", "discretion"]`, body:
  `"Quietly handled a 02:14 guest issue with grace — Mrs. Achebe in 206 called the next morning to praise her by name."`
- Charlotte → Maya, Wed Apr 22, public, values `["craft", "excellence"]`, body:
  `"Three months running as Floor 4 lead with the highest \"would stay again\" score in the property. Steady, quiet, exceptional."`
- Leila → Hugo, two days ago, public, values `["initiative", "craft"]`,
  bonus_points 0, body lifted from design.

### 9.7 Conversations & messages

| kind | participants / channel | last_message_at |
| --- | --- | --- |
| direct | Maya + Charlotte | 08:14 today |
| channel | `housekeeping-floor-4` | 08:02 today |
| direct | Maya + Aisha | yesterday |
| channel | `linden-all` | yesterday |
| direct | Maya + Rafael | Monday |

Direct conversations have two `conversation_participants` rows each. Channel
conversations have a `channel_id` set, `participants` empty.

Messages (insert in chronological order so `inserted_at` matches the times in
the designs):

- For Maya↔Charlotte: four messages as in `mobile-1to1-typing-receipts.html`
  (08:11, 08:12, 08:13, 08:14).
- For Floor 4 channel: three messages as in `mobile-group-floor4.html`
  (07:55 Aisha, 08:00 Hugo, 08:02 Maya).
- For Maya↔Aisha and Linden·All: one message each from yesterday.
- For Maya↔Rafael: one message Monday.

### 9.8 Pseudocode skeleton

```elixir
# priv/repo/seeds.exs
import Ecto.Query
alias Foyer.Repo
alias Foyer.Accounts.User
alias Foyer.Channels.{Channel, Membership}
alias Foyer.Shifts.Shift
alias Foyer.House.{Announcement, AnnouncementRead, AnnouncementAck}
alias Foyer.Recognitions.Recognition
alias Foyer.Chat.{Conversation, Participant, Message}

# 0. Wipe — order matters (FKs).
for schema <- [Message, Participant, Conversation, Recognition, AnnouncementAck, AnnouncementRead, Announcement, Shift, Membership, Channel, User] do
  Repo.delete_all(schema)
end

# 1. Users (returns map of name => %User{}).
users = insert_users()

# 2. Channels + memberships.
channels = insert_channels()
insert_memberships(users, channels)

# 3. Shifts (open + handoff).
insert_shifts(users, channels)

# 4. Announcements + reads + acks.
insert_announcements(users, channels)

# 5. Recognitions.
insert_recognitions(users)

# 6. Conversations + messages.
insert_conversations(users, channels)

IO.puts("Seeded #{Repo.aggregate(User, :count)} users, #{Repo.aggregate(Channel, :count)} channels, ...")
```

The implementing agent writes `insert_*` helpers inline at the bottom of the
file (no `defmodule` — seeds run as a script).

---

## 10. Smoke test

Path: `test/foyer_web/smoke_test.exs`. Tagged `:integration` because
it hits the real Repo with seeded data. `async: false` is **required** because
the test uses the shared sandbox and asserts on seeded rows owned by another
process (the seed script runs through `mix test` alias).

Wait — re-read TESTING_GUIDE.md and the user's brief. They want this test to
run against seeds. The `test` alias is
`["ecto.create --quiet", "ecto.migrate --quiet", "test"]` — seeds are NOT
re-run on every test. Instead, the test **inserts its own fixtures inline**
via `Foyer.Repo`, exercising the real schemas. That's what
`Foyer.DataCase.setup_sandbox` is for: `async: true` works fine because each
test owns its sandbox transaction.

**Decision: `async: true`, fixtures created in `setup`, not seeds.** The seed
script (§9) is still implemented because dev mode needs it for manual
walkthrough, but the smoke test does not rely on it. Justification documented
inline in the test file: "seeds.exs is for manual demo; this test owns its
fixtures so it stays sandboxed and async."

### 10.1 Skeleton

```elixir
defmodule FoyerWeb.ScaffoldSmokeTest do
  # async: true — each test owns its sandbox transaction, fixtures inserted
  # in setup. We do NOT rely on priv/repo/seeds.exs (which is for manual demo).
  use FoyerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Mox
  import FoyerWeb.ScaffoldFixtures   # see §11

  @moduletag :integration

  # Mox verifies any expectations set per test on exit. Smoke tests only
  # use `stub_with` (no `expect`), so this is a guard for future edits.
  setup :verify_on_exit!

  # set_mox_from_context lets the LiveView process (a separate pid) see the
  # stubs we register on the test process. Without it, LiveView->LiveDeps
  # calls hit Mox in `:private` mode and fail. `verify_on_exit!` still
  # works under this mode.
  setup :set_mox_from_context

  setup do
    # `config/test.exs` points LiveDeps at Foyer.*Mock modules. We bind each
    # mock to the real context so the smoke test exercises the real Repo
    # path. Future isolated tests should `stub_with` a scenario module
    # instead of a real context — they MUST NOT use Application.put_env/3
    # (forbidden by TESTING_GUIDE.md).
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

  describe "user picker" do
    test "lists every seeded user with their initials", %{conn: conn, maya: maya} do
      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ "Pick a user"
      assert html =~ maya.name
      assert html =~ maya.initials
    end
  end

  describe "Today — on-shift staff (Maya)" do
    test "renders briefing and bottom-nav, with on-shift status pill", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/today")

      assert has_element?(view, "#today")
      # Greeting copy is checked by substring + Maya's name to avoid breaking
      # on non-ASCII spaces in design extracts.
      assert render(view) =~ "Good morning"
      assert render(view) =~ "Maya"
      assert render(view) =~ "Housekeeping"
      assert render(view) =~ "Floor 4"
      assert render(view) =~ "Handoff from your last shift"
      assert render(view) =~ "Suite 412"
      assert render(view) =~ "Allergy protocol in effect"
      assert render(view) =~ "Pinned"

      # Bottom-nav assertions: stable IDs, not free-text element matching.
      assert has_element?(view, "#bottom-nav-today")
      assert has_element?(view, "#bottom-nav-house")
      assert has_element?(view, "#bottom-nav-chat")
      assert has_element?(view, "#bottom-nav-me")
    end
  end

  describe "Today — manager (Charlotte)" do
    test "shows compose CTA", ctx do
      conn = sign_in(ctx.conn, ctx.charlotte)
      {:ok, view, _html} = live(conn, ~p"/today")

      assert has_element?(view, "#compose-cta")
      assert render(view) =~ "Good morning"
      assert render(view) =~ "Charlotte"
    end
  end

  describe "Today — off-shift (Jamal)" do
    test "renders the off-shift card with Start shift, and starts shift on click", ctx do
      conn = sign_in(ctx.conn, ctx.jamal)
      {:ok, view, _html} = live(conn, ~p"/today")

      assert has_element?(view, "#off-shift")
      assert render(view) =~ "You're off the clock."
      assert has_element?(view, "#start-shift-btn", "Start shift")

      # Bottom-nav House/Chat/Me are disabled buttons (defence in depth).
      assert has_element?(view, "#bottom-nav-house[disabled]")
      assert has_element?(view, "#bottom-nav-chat[disabled]")

      # Click Start shift -> Jamal is now on shift -> can reach /house.
      view |> element("#start-shift-btn") |> render_click()

      conn = sign_in(build_conn(), ctx.jamal)
      {:ok, _house_view, _html} = live(conn, ~p"/house")
    end

    test "off-shift gate redirects /house to /today", ctx do
      conn = sign_in(ctx.conn, ctx.jamal)

      assert {:error, {:redirect, %{to: "/today"}}} = live(conn, ~p"/house")
    end

    test "off-shift gate redirects /chat to /today", ctx do
      conn = sign_in(ctx.conn, ctx.jamal)

      assert {:error, {:redirect, %{to: "/today"}}} = live(conn, ~p"/chat")
    end
  end

  describe "End shift" do
    test "Maya can submit the end-shift form", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/today/end-shift")

      assert has_element?(view, "#end-shift-form")

      view
      |> form("#end-shift-form", shift: %{handoff_note: "All clear in 412."})
      |> render_submit()

      # Maya is now off shift -> /house redirects to /today.
      conn = sign_in(build_conn(), ctx.maya)
      assert {:error, {:redirect, %{to: "/today"}}} = live(conn, ~p"/house")
    end
  end

  describe "House" do
    test "lists feed with pinned + recognition + non-pinned posts", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/house")

      assert render(view) =~ "The House"
      assert render(view) =~ "Suite 412"
      assert render(view) =~ "Allergy protocol in effect"
      assert render(view) =~ "Pinned"
      assert has_element?(view, "#recognize-cta")
    end

    test "compose page opens (for manager)", ctx do
      conn = sign_in(ctx.conn, ctx.charlotte)
      {:ok, view, _html} = live(conn, ~p"/house/new")
      assert has_element?(view, "#compose-form")
      assert render(view) =~ "New announcement"
    end

    test "announcement detail renders ack action and click acks the announcement", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/house/#{ctx.suite_412.id}")

      assert render(view) =~ "Requires acknowledgement"
      assert has_element?(view, "button", "I've read & understood")

      view |> element("button", "I've read & understood") |> render_click()
      assert render(view) =~ "Acknowledged"
    end

    test "unauthorized: Maya cannot open a Leadership-only announcement", ctx do
      # ctx.leadership_only_announcement is seeded into the Leadership
      # channel, where Maya is NOT a member.
      conn = sign_in(ctx.conn, ctx.maya)

      assert {:error, {:redirect, %{to: "/house"}}} =
               live(conn, ~p"/house/#{ctx.leadership_only_announcement.id}")
    end
  end

  describe "Chat" do
    test "inbox lists the seeded conversations", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/chat")

      assert render(view) =~ "Messages"
      assert render(view) =~ "Charlotte Voss"
      assert render(view) =~ "Housekeeping"
      assert render(view) =~ "Floor 4"
    end

    test "room renders messages", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/chat/#{ctx.maya_charlotte.id}")
      # Substring match on stable English copy; do not depend on exact
      # non-ASCII punctuation from the design extracts.
      assert render(view) =~ "Morning Maya"
    end

    test "new message picker lists colleagues", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/chat/new")
      assert render(view) =~ "New message"
      assert render(view) =~ "Hugo Brandt"
    end
  end

  describe "Recognize" do
    test "form renders with house values", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/recognize")
      assert render(view) =~ "Give recognition"
      for v <- ~w(Care Craft Discretion Initiative Warmth Excellence Team) do
        assert render(view) =~ v
      end
    end

    test "manager sees bonus points tiers", ctx do
      conn = sign_in(ctx.conn, ctx.charlotte)
      {:ok, view, _html} = live(conn, ~p"/recognize")
      assert render(view) =~ "Bonus points"
      assert render(view) =~ "+50"
    end
  end

  describe "Profile / Me" do
    test "Me opens current user profile with received recognitions", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/me")
      assert render(view) =~ "Maya Okafor"
      assert render(view) =~ "Quietly handled a 02:14 guest issue"
      assert render(view) =~ "Foyer points"
    end

    test "/people/:id is reachable", ctx do
      conn = sign_in(ctx.conn, ctx.maya)
      {:ok, view, _html} = live(conn, ~p"/people/#{ctx.hugo.id}")
      assert render(view) =~ "Hugo Brandt"
    end
  end

  describe "People directory" do
    test "lists the cast", ctx do
      conn = sign_in(ctx.conn, ctx.charlotte)
      {:ok, view, _html} = live(conn, ~p"/people")
      assert render(view) =~ "People"
      assert render(view) =~ "Maya Okafor"
      # Substring; do not depend on the accented "é" rendering identically
      # in HTML output.
      assert render(view) =~ "bastien Roy"
    end
  end
end
```

Note on copy assertions: test against **substrings and stable element IDs**,
never against design-extract strings with non-ASCII punctuation (em-dash,
middle-dot, non-breaking space). Production copy itself should use ASCII
punctuation where possible (the design extracts use Unicode for typography,
but code copy should not depend on it). This is the resolution of the
review's open question about exact-copy unicode assertions.

### 10.2 `sign_in/2`

Lives in `test/support/conn_case.ex` (added to the `using` block as
`import FoyerWeb.ConnCase`). The helper:

```elixir
def sign_in(conn, user) do
  conn
  |> Phoenix.ConnTest.init_test_session(%{})
  |> Plug.Conn.put_session(:current_user_id, user.id)
end
```

---

## 11. Test infrastructure

### 11.1 `test/test_helper.exs` additions

```elixir
ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Foyer.Repo, :manual)

# Mox mocks — one per context behavior. config/test.exs (§11.3) points LiveDeps
# at THESE mocks; tests use Mox.stub_with/2 to bind a real context or a
# scenario module per scope. Tests MUST NOT mutate :foyer, :*_context with
# Application.put_env/3 (forbidden by TESTING_GUIDE.md).
Mox.defmock(Foyer.AccountsMock, for: Foyer.Accounts.Behavior)
Mox.defmock(Foyer.ShiftsMock, for: Foyer.Shifts.Behavior)
Mox.defmock(Foyer.ChannelsMock, for: Foyer.Channels.Behavior)
Mox.defmock(Foyer.HouseMock, for: Foyer.House.Behavior)
Mox.defmock(Foyer.RecognitionsMock, for: Foyer.Recognitions.Behavior)
Mox.defmock(Foyer.ChatMock, for: Foyer.Chat.Behavior)
Mox.defmock(Foyer.ProfileMock, for: Foyer.Profile.Behavior)
Mox.defmock(Foyer.TodayMock, for: Foyer.Today.Behavior)

# Scenario placeholder folders are NOT created yet — they will be added by
# feature-group plans as the first isolated test for that group is written.
# Folder convention (per docs/TESTING_GUIDE.md):
#
#   test/support/scenarios/<context>/empty.ex
#   test/support/scenarios/<context>/busy.ex
#   ...
#
# Each scenario module implements the corresponding context behavior and is
# wired via `Mox.stub_with(Foyer.XMock, MyScenario)`. See feature-group
# plans for the first usage.
```

### 11.2 `config/dev.exs` additions

```elixir
config :foyer,
  accounts_context:     Foyer.Accounts,
  shifts_context:       Foyer.Shifts,
  channels_context:     Foyer.Channels,
  house_context:        Foyer.House,
  recognitions_context: Foyer.Recognitions,
  chat_context:         Foyer.Chat,
  profile_context:      Foyer.Profile,
  today_context:        Foyer.Today
```

### 11.3 `config/test.exs` additions

Test config points LiveDeps at **Mox mocks**, per TESTING_GUIDE.md. The
smoke test (§10) uses `Mox.stub_with/2` in `setup` to bind each mock to the
real context, so the smoke path still exercises the real Repo. Future
isolated tests use `Mox.stub_with/2` to bind a **scenario module** (e.g.
`Foyer.HouseScenarios.Empty`) — they MUST NOT call
`Application.put_env(:foyer, :house_context, …)` (forbidden by
TESTING_GUIDE.md).

```elixir
config :foyer,
  accounts_context:     Foyer.AccountsMock,
  shifts_context:       Foyer.ShiftsMock,
  channels_context:     Foyer.ChannelsMock,
  house_context:        Foyer.HouseMock,
  recognitions_context: Foyer.RecognitionsMock,
  chat_context:         Foyer.ChatMock,
  profile_context:      Foyer.ProfileMock,
  today_context:        Foyer.TodayMock
```

Why this matters: a future feature-group test that forgets to bind a mock
will get a clear `Mox.UnexpectedCallError` instead of accidentally hitting
the real DB. The smoke test is the **only** test that binds every mock to
real contexts; everything else opts in per-scenario.

### 11.4 `config/runtime.exs` additions

Nothing — runtime config does not touch context modules. They are fixed at
compile time per environment.

### 11.5 `test/support/scaffold_fixtures.ex`

New file. Exports `seed_scaffold!/0` returning a fixtures map. Inserts the
same fixtures as §9 but trimmed to what the smoke test actually asserts
against — keeps the test fast.

```elixir
defmodule FoyerWeb.ScaffoldFixtures do
  alias Foyer.Repo
  alias Foyer.Accounts.User
  # … aliases

  @spec seed_scaffold!() :: map()
  def seed_scaffold! do
    # Insert: Maya, Charlotte, Rafael, Aisha, Hugo, Jamal, Tomás, Leila,
    #   Sébastien, Elin, Priya, Nina, Olu, Kasia
    # Channels: housekeeping-floor-4, all-housekeeping, f-and-b,
    #   concierge-front-office, engineering, leadership, linden-all
    # Memberships
    # Shifts: open for Maya/Charlotte/Aisha/Hugo/Tomás/Leila/Sébastien/Elin/Priya,
    #   ended (with handoff) for Rafael, none-current for Jamal/Nina/Olu/Kasia
    # 1 pinned ack-required announcement (Suite 412)
    # 1 Leadership-only announcement (Maya is NOT a member -> auth test)
    # 1 recognition (Rafael → Maya)
    # 2 conversations + 4 messages
    %{
      maya: maya, charlotte: charlotte, jamal: jamal, hugo: hugo, rafael: rafael,
      suite_412: suite_412,
      leadership_only_announcement: leadership_only_announcement,
      maya_charlotte: maya_charlotte
    }
  end
end
```

`test/support/scaffold_fixtures.ex` is auto-compiled in `:test` because
`mix.exs` already lists `test/support` for the test env (line 40).

### 11.6 mix.exs

- **Add `{:typed_struct, "~> 0.3"}`** as a runtime dep — used by
  `FoyerWeb.Scope` (and any future non-Ecto DTOs).
- **mox is already a dep** at line 73; no change.
- The `precommit` alias already runs `compile --warnings-as-errors`,
  `deps.unlock --unused`, `format`, `test`. The plan does not change it but
  the final step in the execution order (§13) runs it.

```elixir
defp deps do
  [
    # ... existing deps ...
    {:typed_struct, "~> 0.3"}
  ]
end
```

---

## 12. Mix changes

Summary of every diff to `mix.exs`:

1. `{:typed_struct, "~> 0.3"}` added to `deps/0`.
2. `aliases/0` gets a new entry: `"ecto.seed": ["run priv/repo/seeds.exs"]`
   for manual demo work.
3. The `"ecto.setup"` alias is unchanged — already runs seeds via `"run
   priv/repo/seeds.exs"`.

---

## 13. Step-by-step execution order

Each step lists the files touched and the verification command. Implementing
agent runs the verification at the end of each step; if it fails the agent
fixes the issue before moving on.

| # | What | Files touched | Verify |
| - | --- | --- | --- |
| 1 | Add `typed_struct` dep, run `mix deps.get`. **Note: requires network**; if the execution environment is offline, the implementing agent should batch this with steps that don't need network and run `mix deps.get` once when network is available. | `mix.exs`, `mix.lock` | `mix deps.get` |
| 2 | Strip daisyUI from CSS + delete vendor files. Add Foyer palette/typography/component utilities. Remove `theme_toggle/1` from `layouts.ex` and the theme `<script>` from `root.html.heex`. Drop the navbar from `Layouts.app/1` (Foyer renders its own headers). Keep `<.flash_group flash={@flash}/>` inside `Layouts.app/1`. | `assets/css/app.css`, `assets/vendor/daisyui.js` (delete), `assets/vendor/daisyui-theme.js` (delete), `lib/foyer_web/components/layouts.ex`, `lib/foyer_web/components/layouts/root.html.heex` | `mix compile --warnings-as-errors` |
| 3 | Rewrite `core_components.ex` button/input/flash/header/table/list to drop daisyUI classes. Public API (attr lists) unchanged. | `lib/foyer_web/components/core_components.ex` | `mix compile --warnings-as-errors`, manual render check |
| 4 | Add the two woff2 font files under `priv/static/fonts/`. | `priv/static/fonts/instrument-serif-regular.woff2`, `…-italic.woff2`, `jetbrains-mono-regular.woff2` | font requests resolve at `/fonts/*` |
| 5 | Create all migrations (§5.13) in chronological order: `mix ecto.gen.migration create_users`, etc. Write each `change/0` body. **Use `mix ecto.migrate`, not `mix ecto.reset`** — the existing seeds file is still the generated one until step 17, and `ecto.reset` would run it after a table-shape change and crash. | `priv/repo/migrations/*` | `mix ecto.migrate` |
| 6 | Create all Ecto schemas (§5.1–§5.12), the `Foyer.Today.Briefing` DTO, and the `Foyer.Profile.Card` DTO. Each module includes its `@type t` (schemas) or `typedstruct` (DTOs). | `lib/foyer/accounts/user.ex`, `lib/foyer/channels/{channel,membership}.ex`, `lib/foyer/shifts/shift.ex`, `lib/foyer/house/{announcement,announcement_read,announcement_ack}.ex`, `lib/foyer/recognitions/recognition.ex`, `lib/foyer/chat/{conversation,participant,message,message_read}.ex`, `lib/foyer/today/briefing.ex`, `lib/foyer/profile/card.ex` | `mix compile --warnings-as-errors` |
| 7 | Create context behaviors (§6.1–§6.8). One file each. | `lib/foyer/{accounts,shifts,channels,house,recognitions,chat,profile,today}/behavior.ex` | `mix compile --warnings-as-errors` |
| 8 | Implement real context modules. Each `@behaviour Foyer.X.Behavior`. Reads are real Repo queries with preloads + membership auth on `get_*!/2`; writes for shift start/end and announcement ack/read are real; others raise the `"TODO: feature-group <X>"` runtime error. Every public function has `@spec`. | `lib/foyer/{accounts,shifts,channels,house,recognitions,chat,profile,today}.ex` | `mix compile --warnings-as-errors`, `mix credo --strict` |
| 9 | Wire `LiveDeps` accessors (§6.9), add `:foyer, :*_context` config to `config/dev.exs` (real contexts) and `config/test.exs` (Mox mocks). | `lib/foyer_web/live_deps.ex`, `config/dev.exs`, `config/test.exs` | `mix compile --warnings-as-errors`, `iex -S mix` → `FoyerWeb.LiveDeps.house()` returns `Foyer.House` in dev |
| 10 | Create `FoyerWeb.Scope` and `FoyerWeb.UserAuth` (the three `on_mount` clauses + `fetch_current_user/2` plug). | `lib/foyer_web/scope.ex`, `lib/foyer_web/user_auth.ex` | `mix compile --warnings-as-errors` |
| 11 | Create `FoyerWeb.SessionController` (pick/sign_out actions). | `lib/foyer_web/controllers/session_controller.ex` | `mix compile --warnings-as-errors` |
| 12 | Rewrite `router.ex` (§3.1) with the three live_sessions. Delete `PageController` route and any generated `page_controller_test.exs`. | `lib/foyer_web/router.ex`, `test/foyer_web/controllers/page_controller_test.exs` (delete) | `mix compile --warnings-as-errors`, `mix phx.routes` |
| 13 | Implement `FoyerWeb.FoyerComponents` shared components (§8) — bottom_nav with stable IDs, disabled state when off-shift. | `lib/foyer_web/components/foyer_components.ex` | `mix compile --warnings-as-errors` |
| 14 | Implement each LiveView (§7.1–§7.9), each with `~H` template, `mount/3`, `handle_params/3`, event handlers. All data loading in `handle_params/3`. | `lib/foyer_web/live/{user_picker,today,house,announcement,chat,chat_room,recognize,profile,people}_live.ex` | `mix compile --warnings-as-errors`, `mix format --check-formatted` |
| 15 | Delete `lib/foyer_web/controllers/page_controller.ex` and `lib/foyer_web/controllers/page_html.ex` (no longer referenced). | (deletes) | `mix compile --warnings-as-errors` |
| 16 | Rewrite `priv/repo/seeds.exs` (§9). | `priv/repo/seeds.exs` | `mix ecto.reset` succeeds (now that schemas + seeds align), `iex -S mix` → `Foyer.Repo.aggregate(Foyer.Accounts.User, :count)` returns 14 |
| 17 | Create `test/support/scaffold_fixtures.ex` (§11.5). Add `sign_in/2` to `test/support/conn_case.ex` `using` block. Update `test/test_helper.exs` per §11.1. | `test/support/scaffold_fixtures.ex`, `test/support/conn_case.ex`, `test/test_helper.exs` | `mix compile --warnings-as-errors` |
| 18 | Write `test/foyer_web/smoke_test.exs` (§10). | `test/foyer_web/smoke_test.exs` | `mix test test/foyer_web/smoke_test.exs` (all green) |
| 19 | Run Dialyzer. PLT build is ~1 min on first run; everything compiled-and-LiveView-wired by this point so type contracts are stable. | (none) | `mix dialyzer` (clean) |
| 20 | **Manual instruction (do NOT run from the agent's automated step list — long-running)**: `mix phx.server`, walk the bottom-nav as Maya, switch to Jamal (off-shift), confirm redirect. The implementer should run this themselves and shut it down before the next automated step. | (none) | manual smoke walk |
| 21 | Final: `mix precommit`. | (none) | `mix precommit` (all green) |

If a step's verification fails, the implementing agent must fix the issue in
place — no skipping forward. Per CLAUDE.md, `mix credo --strict` must pass.
Allow the agent to add `# credo:disable-for-this-file` on the seeds file if
the line-count heuristic trips it (seeds are long by nature); otherwise no
credo overrides.

---

## 14. Risks & decisions

| # | Decision | Why | Trade-off / risk |
| - | --- | --- | --- |
| 1 | **Rip daisyUI out** instead of theming around it | AGENTS.md mandate; Foyer's design clashes with daisyUI defaults; ~30 KB CSS saved | Forces rewrite of every `core_components.ex` component body. If a future Foyer feature needs a daisyUI primitive (a complex modal, say), we re-implement it manually. Mitigated by §8 components covering the common needs. |
| 2 | **Bundle fonts locally** instead of Google Fonts link | AGENTS.md restricts external `<link>` references; precommit must work offline; one fewer DNS round-trip | Repo size +~200 KB. Manual font upgrades. License compliance burden (both fonts are SIL OFL, fine to ship). |
| 3 | **Implement only shift start/end + ack/read writes**, stub the rest | These three are exercised by the smoke test; the rest need business rules (audience targeting, grace window, points ledger) that belong with the feature group. Implementing them here would either be wrong (no audience check) or duplicate work. | A real user clicking "Publish" on the compose screen gets a flash, not a created record. Mitigated by §7's `try/rescue` around stub calls — the form still renders. Users of the scaffold should know it's a scaffold. |
| 4 | **Off-shift gate is a hard redirect with flash**, not a soft "you need to start your shift" overlay | Matches FOYER.md ("only Today should be reachable"); simpler to test (assertion: `{:error, {:redirect, %{to: "/today"}}}`); no fight with deep-links | A bookmarked `/chat` always lands on `/today` for off-shift users. They lose context (which thread they wanted). Acceptable for v0. The flash message tells them why. |
| 5 | **Streams used for Chat messages, Chat inbox, House feed** | AGENTS.md mandates streams for collections; chat especially balloons memory without them; House feed is small now but grows | Streams forbid `Enum`/empty-state-with-counts. Empty-state HTML uses the `:only:block` Tailwind trick AGENTS.md documents. Filtering by tab in House re-fetches and re-streams with `reset: true`. |
| 6 | **`config/test.exs` points LiveDeps at Mox mocks; smoke test uses `Mox.stub_with/2` to bind real contexts** | Per TESTING_GUIDE.md: test config defaults to mocks, tests opt into real-or-scenario per `setup`. Forbidden alternatives: `Application.put_env/3` mutation; pointing test config at real modules and asking feature-group tests to swap. | Risk: a future test author forgets `stub_with`, gets `Mox.UnexpectedCallError`. That is the *desired* failure mode — clearer than silently hitting the real DB. |
| 7 | **Scenario placeholder modules NOT created yet** | Premature scenarios are dead code that pretends to be tested. Folder layout documented in `test_helper.exs` so the next agent knows where they go. | Risk: next agent invents a different folder convention. Mitigated by the explicit comment + reference to TESTING_GUIDE.md. |
| 8 | **Three `live_session` blocks** (`:public`, `:authenticated_today`, `:authenticated_on_shift`) instead of a single session with route introspection | `socket.view`-based gating is not a stable LiveView 1.1 contract per the review; three sessions cleanly separate "no auth", "auth + off-shift allowed", "auth + on-shift required". | New surfaces (a future "settings" page) must consciously pick the right live_session block. That's a feature, not a bug — the choice is explicit at route declaration. |
| 9 | **`current_shift_for` and `last_handoff_for` are real DB queries on every Today mount** | Mount/handle_params discipline says heavy work goes in `handle_params`; these queries hit indexes `(user_id, ended_at)` and `(handoff_channel_id, ended_at)` so they're sub-ms. No need for `assign_async`. | If Today gets called frequently and the DB roundtrip becomes a bottleneck, cache the briefing in an ETS table. Out of scope for v0. |
| 10 | **People Directory uses the desktop layout** (side-rail visible on `md:` up) but is reachable from mobile too | Designs show it as a desktop surface; on mobile the side-rail is hidden via `hidden md:block`. Reachable from `/people` regardless of device. | Mobile people view will look like a plain list, not the designed desktop experience. Acceptable — feature group will polish. |
| 11 | **`Foyer.Today` is its own context (read-only orchestrator) that calls Shifts/House/Recognitions** — this bends ARCHITECTURE.md's "no cousin calls" rule | Today is the user's morning briefing — by definition an aggregation across siblings. Putting the aggregation in TodayLive violates "fat contexts, slim LiveViews" worse. Keeping it read-only (no writes go through Today) bounds the god-object risk. | If a second orchestrator appears (e.g. a future "Dashboard"), we re-evaluate whether `Foyer.Today` should split into per-domain read-models composed in the LiveView. For now the trade-off is conscious and contained. |

---

## 15. Open questions — resolutions

The review enumerated open questions; this section records the resolved
answer for each, so the implementing agent doesn't have to re-derive them.

1. **Read authorization in scaffold (announcements + conversations)**:
   **Yes, baked in now.** See §6.4 and §6.6 — `get_announcement!/2` and
   `get_conversation!/2` join through memberships / participants. Smoke
   test in §10 exercises the unauthorized-access redirect.

2. **`FoyerWeb.Scope` uses `typed_struct`**: **Yes.** The dep also covers
   `Foyer.Today.Briefing` and `Foyer.Profile.Card` DTOs, so it pays for
   itself. See §13 step 1.

3. **Off-shift bottom-nav: disabled buttons or route-level redirect?**:
   **Both.** Disabled buttons in the UI (so off-shift users do not generate
   pointless click→redirect cycles); route-level `:ensure_on_shift` guard
   for typed URLs / bookmarks / deep links. See §3.3 and §8.

4. **Denormalised `member_count`**: **Removed.** Channel membership writes
   are deferred to the Channels feature group; until those exist, computing
   the count at query time avoids a stale-counter footgun. See §5.3 and
   §6.3.

5. **Direct conversation uniqueness**: **`direct_key` column + partial
   unique index.** `Conversation` carries a `direct_key :string` derived as
   `"#{min(uid_a, uid_b)}-#{max(uid_a, uid_b)}"` for DMs; a partial unique
   index on `direct_key WHERE kind = 'direct'` prevents duplicate DM pairs.
   See §5.9 and §5.13.

6. **Profile and Today return DTO structs**: **Yes.** `Foyer.Profile.Card`
   and `Foyer.Today.Briefing` are typed structs, not bare maps. See §6.7
   and §6.8.

7. **Non-ASCII punctuation in copy and tests**: **Use ASCII in code copy;
   assert on substrings + element IDs in tests.** The design extracts use
   em-dashes and middle-dots for typography, but the production templates
   render with ASCII equivalents (hyphen-minus, period). Tests never assert
   on exact unicode strings — see §10's substring-style assertions and
   stable `#bottom-nav-*` IDs.

### Still-deferred design questions (NOT blocking the scaffold)

Items below are confirmed-deferred to feature-group plans:

- **Property string** ("The Linden, Mayfair, London") stays hard-coded in
  templates until a `Property` schema is introduced (post-v1).
- **End-shift UI flow** — `/today/end-shift` as a `live_action` on
  `TodayLive` is fine for v0; a dedicated `ShiftLive` is a feature-group
  decision.
- **Search & notifications bell icons** — inert `<button aria-label="…">`
  is acceptable; feature groups will wire them.
- **Recognition values as `{:array, :string}`** validated against
  `@house_values` is fine for v0.
- **People Directory shift state** renders the real state per row;
  feature group may add filters / sort orders later.
- **`/me` for a manager** uses the same Profile surface as staff in v0;
  manager-specific profile is a future feature.
- **Compose audience picker** uses `<.input type="select">` for v0; the
  custom sheet is design-heavy and out of scope for the scaffold.
