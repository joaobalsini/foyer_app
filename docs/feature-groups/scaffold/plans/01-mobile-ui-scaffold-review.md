# Review — Plan 01 Mobile-first UI scaffold

Reviews: [`01-mobile-ui-scaffold.md`](./01-mobile-ui-scaffold.md). Implementation
outcome captured in
[`01-mobile-ui-scaffold-implementation-review.md`](./01-mobile-ui-scaffold-implementation-review.md).

## Verdict

Revise

The plan is strong enough to preserve the product direction, but it is not safe to execute as written. The biggest blockers are the off-shift gate implementation, contradictory LiveDeps/Mox policy, schema/index gaps, and smoke-test assertions that do not line up with the planned templates or LiveView redirect semantics.

## Strengths

- §1 correctly scopes the scaffold as cross-cutting infrastructure and explicitly defers most write paths. That keeps the scaffold from becoming the implementation plan for every feature group.
- §2.1 is aligned with AGENTS.md: remove daisyUI, keep the public CoreComponents API, and rewrite the component bodies with Tailwind/custom CSS.
- §4 makes `FoyerWeb.Scope` explicit and requires every LiveView template to pass `current_scope` into `<Layouts.app>`, which is the right Phoenix v1.8 shape.
- §5 includes the Ecto schemas up front with fields, relationships, and `@type t` declarations, matching the workflow requirement that plans expose data contracts before execution.
- §7 consistently puts database-backed loads in `handle_params/3` instead of `mount/3`, matching ARCHITECTURE.md's LiveView mount discipline.
- §10 correctly pivots away from relying on `priv/repo/seeds.exs` in tests and toward sandbox-owned fixtures.

## Critical Issues

### §3.3 Off-shift gate uses `socket.view`, which is not a stable LiveView 1.1 gate input

Bug: `today_path?/1` is specified as reading `socket.view`. That is not a supported public field on `Phoenix.LiveView.Socket.t()` for authorization decisions. In `on_mount/4`, you get params/session/socket, not the route path or live action. The plan's own note says it avoids `socket.assigns[:__phx_path__]`, but replacing that with `socket.view` is still brittle.

Fix: split the authenticated routes into two `live_session`s with different hooks. Today is authenticated but off-shift allowed; the rest are authenticated and on-shift required.

```elixir
scope "/", FoyerWeb do
  pipe_through :browser

  live_session :public,
    on_mount: [{FoyerWeb.UserAuth, :mount_public}] do
    live "/", UserPickerLive, :index
  end

  live_session :authenticated_today,
    on_mount: [{FoyerWeb.UserAuth, :ensure_authenticated}] do
    live "/today", TodayLive, :index
    live "/today/end-shift", TodayLive, :end_shift
  end

  live_session :authenticated_on_shift,
    on_mount: [{FoyerWeb.UserAuth, :ensure_on_shift}] do
    live "/house", HouseLive, :index
    live "/house/new", HouseLive, :compose
    live "/house/:id", AnnouncementLive, :show
    live "/chat", ChatLive, :inbox
    live "/chat/new", ChatLive, :new_message
    live "/chat/:conversation_id", ChatRoomLive, :show
    live "/recognize", RecognizeLive, :new
    live "/me", ProfileLive, :me
    live "/people", PeopleLive, :index
    live "/people/:id", ProfileLive, :show
  end
end
```

```elixir
def on_mount(:ensure_authenticated, _params, session, socket) do
  with %Scope{} = scope <- load_scope(session) do
    {:cont, assign(socket, :current_scope, scope)}
  else
    nil -> {:halt, socket |> put_flash(:error, "Please pick a user.") |> redirect(to: ~p"/")}
  end
end

def on_mount(:ensure_on_shift, _params, session, socket) do
  case load_scope(session) do
    nil ->
      {:halt, socket |> put_flash(:error, "Please pick a user.") |> redirect(to: ~p"/")}

    %Scope{on_shift?: false} ->
      {:halt,
       socket
       |> put_flash(:info, "Start your shift to enter the rest of Foyer.")
       |> redirect(to: ~p"/today")}

    %Scope{} = scope ->
      {:cont, assign(socket, :current_scope, scope)}
  end
end
```

### §10 Smoke test expects `{:live_redirect, ...}` for an `on_mount` redirect

Bug: `live(conn, ~p"/house")` where the mount hook redirects usually returns `{:error, {:redirect, %{to: "/today"}}}`, not `{:error, {:live_redirect, ...}}`. `live_redirect` is deprecated and should not appear in new tests.

Fix:

```elixir
assert {:error, {:redirect, %{to: "/today"}}} = live(conn, ~p"/house")
assert {:error, {:redirect, %{to: "/today"}}} = live(conn, ~p"/chat")
```

### §11.3 contradicts TESTING_GUIDE.md and itself on Mox configuration

Bug: §11.3 says `config/test.exs` points LiveDeps at real contexts, then says isolated tests will use `Application.put_env/3` or a "LiveDeps test helper." TESTING_GUIDE.md explicitly says test config should point at Mox mocks and forbids per-test `Application.put_env/3` mutation.

Fix: keep route smoke tests on real modules by bypassing LiveDeps only for the smoke path is the wrong direction. The cleaner fix is: test config points to mocks, smoke tests use `Mox.stub_with/2` against real scenario modules or run under a small smoke-only `setup` that stubs mocks to real contexts. Do not mutate app env per test.

```elixir
# config/test.exs
config :foyer,
  accounts_context: Foyer.AccountsMock,
  shifts_context: Foyer.ShiftsMock,
  channels_context: Foyer.ChannelsMock,
  house_context: Foyer.HouseMock,
  recognitions_context: Foyer.RecognitionsMock,
  chat_context: Foyer.ChatMock,
  profile_context: Foyer.ProfileMock,
  today_context: Foyer.TodayMock
```

```elixir
setup :verify_on_exit!

setup do
  Mox.stub_with(Foyer.AccountsMock, Foyer.Accounts)
  Mox.stub_with(Foyer.ShiftsMock, Foyer.Shifts)
  Mox.stub_with(Foyer.ChannelsMock, Foyer.Channels)
  Mox.stub_with(Foyer.HouseMock, Foyer.House)
  Mox.stub_with(Foyer.RecognitionsMock, Foyer.Recognitions)
  Mox.stub_with(Foyer.ChatMock, Foyer.Chat)
  Mox.stub_with(Foyer.ProfileMock, Foyer.Profile)
  Mox.stub_with(Foyer.TodayMock, Foyer.Today)

  fixtures = seed_scaffold!()
  {:ok, fixtures}
end
```

### §6.4 and §6.6 intentionally omit membership authorization

Bug: `House.get_announcement!/2` and `Chat.get_conversation!/2` are marked real but intentionally skip membership authorization. That violates FOYER.md's access rules and makes route smoke tests bless an insecure scaffold.

Fix: authorization is not a deferred write-path rule. It belongs in the read queries now.

```elixir
def get_announcement!(id, %User{id: user_id}) do
  Announcement
  |> join(:inner, [a], m in Membership,
    on: m.channel_id == a.channel_id and m.user_id == ^user_id
  )
  |> where([a, _m], a.id == ^id)
  |> preload([:author, :channel, :reads, :acks])
  |> Repo.one!()
end
```

```elixir
def get_conversation!(id, %User{id: user_id}) do
  Conversation
  |> join(:left, [c], p in Participant,
    on: p.conversation_id == c.id and p.user_id == ^user_id
  )
  |> join(:left, [c, _p], m in Membership,
    on: m.channel_id == c.channel_id and m.user_id == ^user_id
  )
  |> where([c, p, m], c.id == ^id and (not is_nil(p.id) or not is_nil(m.id)))
  |> Repo.one!()
  |> Repo.preload([:channel, participants: :user])
end
```

### §5.13 misses database constraints needed by the changesets

Bug: several changesets declare `unique_constraint/2`, but the migration section does not name the unique indexes in a way Ecto can reliably infer for list constraints, and some invariants only exist in Elixir. The scaffold should not allow duplicate open shifts, duplicate direct conversations, or invalid conversation/channel pairs at the DB layer.

Fix: add explicit names and checks.

```elixir
create unique_index(:shifts, [:user_id],
         where: "ended_at IS NULL",
         name: :shifts_one_open_shift_per_user
       )

create unique_index(:channel_memberships, [:user_id, :channel_id],
         name: :channel_memberships_user_id_channel_id_index
       )

create constraint(:recognitions, :bonus_points_non_negative,
         check: "bonus_points >= 0"
       )

create constraint(:conversations, :conversation_kind_channel_pair,
         check: """
         (kind = 'channel' AND channel_id IS NOT NULL)
         OR (kind = 'direct' AND channel_id IS NULL)
         """
       )
```

## Targeted Answers to the Three Author-flagged Risks

1. Off-shift gate in a single `live_session` vs LiveView 1.1 idioms: use two authenticated `live_session`s. A single session with an allowlist hidden in `on_mount` is possible only if the hook receives a stable route marker. The plan's `socket.view` approach is not a good contract. Separate sessions are clearer, easier to test, and fit Phoenix's authenticated-route guidance.

2. `config/test.exs` real contexts vs Mox mocks per the testing guide: use Mox mocks in `config/test.exs`. Route smoke tests can `stub_with` real modules so the real DB path is still exercised without violating the global LiveDeps contract. The current plan makes future isolated tests surprising and encourages forbidden `Application.put_env/3`.

3. `Foyer.Today` orchestrator calling cousin contexts vs composing in the LiveView: keep `Foyer.Today`, but treat it as an explicit read-model/orchestrator port. TodayLive should not call Shifts, House, Recognitions, and Chat directly. However, Today must not become the write API; `start_shift`, `end_shift`, and `acknowledge` should remain on their owning contexts.

## Phoenix v1.8 and LiveView 1.1 Conformance Issues

- §7.1 does data loading in `mount/3` for `UserPickerLive`. ARCHITECTURE.md says expensive setup belongs in `handle_params/3`. Even if the seed list is small, keep the rule consistent:

```elixir
def mount(_params, _session, socket), do: {:ok, assign(socket, users: [])}

def handle_params(_params, _uri, socket) do
  {:noreply, assign(socket, :users, LiveDeps.accounts().list_pickable_users())}
end
```

- §7.5 says ChatLive subscribes in `mount/3` using `scope.user.id`, but the listed convention says mount only assigns defaults. This is safe only after the auth hook assigns `current_scope`; call it out and bind the socket result correctly.
- §7.2 uses a literal pilcrow in the compose CTA. AGENTS.md requires `<.icon>` for hero icons. Use an actual icon component or plain text, not typographic symbol decoration.
- §7.3 uses `Enum.map(@channels, &{&1.name, &1.id})` inside HEEx. This is valid, but it mixes view shaping into the template. Prefer assign `channel_options` from `handle_params/3`.
- §2.4 sets `.foyer-serif` letter spacing to `-0.01em`, which conflicts with the frontend guidance requiring letter spacing to be 0, not negative. Set `letter-spacing: 0`.
- §7.1 uses `<button>` inside `<.form>` with no explicit `type`. It will submit by default, but AGENTS.md asks for unique IDs on key elements and tests reference them. Add `type="submit"` and keep the button ID.

## Spec and Test Drift Risks

- The scaffold spec says no `F.Scaffold.N` clauses, so §10 must avoid feature-spec assertions that will later be owned by Today/House/Chat specs. Tag these as infrastructure/smoke and add comments that exact copy assertions exist only to protect this scaffold's design contract.
- §1 says real write paths are deferred except shift start/end and acknowledgement, but §10 only opens the ack detail and does not click the ack button. If ack is implemented now, the smoke test should exercise it.

```elixir
view |> element("button", "I've read & understood") |> render_click()
assert render(view) =~ "Acknowledged"
```

- §7.2 includes `"start_shift"` and `"end_shift_submit"` handlers, but §10 only asserts the Start shift button exists. Add one smoke test for `render_click("#start-shift-btn")` and one for the end-shift form, or remove the claim that these writes are smoke-tested.
- §7.3 catches a stub RuntimeError on compose submit, but §10 never submits compose. Either test the stub flash or remove the handler until the feature plan implements it.

## Data Model Concerns

- N+1 risks: §6.1 says `list_people/1` preloads memberships and joins open shifts, but the `User` schema has `has_many :channels, through: [:memberships, :channel]`. If templates read `p.channels`, preloading `:memberships` alone is not enough. Preload `memberships: :channel` or return a typed directory DTO.
- N+1 risks: §6.6 `inbox_for/1` says "fallback to in-memory tag after Repo.all" for latest message. That can become one query per conversation if implemented casually. Require a subquery for latest message or preload a bounded message list with a documented query.
- Missing indexes: add `index(:announcements, [:channel_id, :pinned_at, :published_at])` for the feed ordering, `index(:shifts, [:handoff_channel_id, :ended_at])` for `last_handoff_for/1`, and `index(:conversation_participants, [:user_id, :conversation_id])` for inbox lookup.
- Missing unique constraints: add one open shift per user, one channel conversation per channel, and explicit unique names for read/ack/message read constraints. Consider a direct-conversation identity model before v1; two participants with only a participant unique index does not prevent duplicate Maya/Charlotte direct conversations.
- `bonus_points` defaults: §5.8 schema defaults to 0, but §5.13 migration says `default:0` without `null:false`. Make it `null: false` and add a check constraint. If manager-only points are deferred, still prevent null and negative values.
- `Conversation.kind` enum: `Ecto.Enum` stores strings by default, so the partial unique index `where: "kind = 'channel'"` is fine. Add a DB check constraint limiting `kind IN ('direct', 'channel')` so ad hoc inserts cannot bypass the enum.
- `pinned_at` pattern: using a nullable timestamp is good. The plan should use a partial index now, not punt it to v2, because the feed query explicitly sorts/filter-pins on this field:

```elixir
create index(:announcements, [:pinned_at, :published_at],
         where: "pinned_at IS NOT NULL",
         name: :announcements_pinned_feed_index
       )
```

## Off-Shift Gate Proposal

Use three hooks: public mount, authenticated mount, and on-shift mount. This keeps Today reachable when off shift and blocks the rest without route introspection.

```elixir
defmodule FoyerWeb.UserAuth do
  use FoyerWeb, :verified_routes

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3, redirect: 2]

  alias FoyerWeb.Scope

  def on_mount(:mount_public, _params, session, socket) do
    {:cont, assign(socket, :current_scope, load_scope(session))}
  end

  def on_mount(:ensure_authenticated, _params, session, socket) do
    case load_scope(session) do
      nil -> {:halt, socket |> put_flash(:error, "Please pick a user.") |> redirect(to: ~p"/")}
      %Scope{} = scope -> {:cont, assign(socket, :current_scope, scope)}
    end
  end

  def on_mount(:ensure_on_shift, _params, session, socket) do
    case load_scope(session) do
      nil ->
        {:halt, socket |> put_flash(:error, "Please pick a user.") |> redirect(to: ~p"/")}

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

## Execution Order Issues

- §13 step 1 adds `typed_struct`, but approval policy/network may block `mix deps.get`. Consider avoiding the dependency for a single `Scope` struct, or explicitly note this step requires network in execution environments.
- §13 step 5 runs `mix ecto.reset` before schemas and contexts exist. Migrations can run before schemas, but seeds are currently still the generated seed file until step 16; `ecto.reset` will run seeds and may fail after tables change. Use `mix ecto.migrate` for step 5, then reserve `mix ecto.reset` for after seeds are rewritten.
- §13 step 8 runs Dialyzer before LiveViews, LiveDeps config, and mocks are finished. Dialyzer is useful later, but this placement is likely noisy. Move it to after step 18 and keep compile/credo earlier.
- §13 step 12 deletes the PageController route, while step 15 deletes the controller files. That is fine, but update or remove any generated controller tests at the same time if present.
- §13 step 19 starts `mix phx.server`; execution instructions elsewhere require ending the turn without long-running sessions. Make this a manual command for the implementer or require shutting it down after the check.

## Smoke Test Review

- Asserted strings that do exist in design extracts: `Pick a user`, `Good morning, Maya.`, `On shift · Housekeeping · Floor 4`, `Handoff from your last shift`, `Suite 412 — Allergy protocol in effect`, `Pinned`, `Good morning, Charlotte.`, `You're off the clock.`, `Start shift`, `The House`, `New announcement`, `Requires acknowledgement`, `I've read & understood`, `Messages`, `Charlotte Voss`, `Housekeeping · Floor 4`, `New message`, `Hugo Brandt`, `Give recognition`, `Bonus points`, `+50`, `Maya Okafor`, `Quietly handled a 02:14 guest issue`, `Foyer points`, `People`, `Sébastien Roy`.
- Asserted strings that may not exist in the planned templates as written: `Morning Maya` is in `mobile-1to1-typing-receipts.html` and seeds, but §7.6 only says "Template uses the streams pattern"; require it in the ChatRoom template/fixtures. `Good morning, Maya.` may fail if `greeting/1` uses a non-breaking or thin space like the extract (`Good morning, Maya.`). Use normalized text or test a stable element instead.
- The bottom-nav assertion `has_element?(view, "a, button", label)` is too broad and may pass on unrelated buttons. Give bottom-nav links IDs such as `#bottom-nav-today`, `#bottom-nav-house`, `#bottom-nav-chat`, `#bottom-nav-me`.
- `async: true` is acceptable if every fixture is inserted inside the sandbox and no test depends on global seeds. If Mox is used, each test must use `setup :verify_on_exit!`; mount-time Mox calls are fine with `stub_with`, but event-time expectations may need `Mox.allow/3` for the LiveView pid.
- Because the test is `:integration`, keep the file small. The current skeleton is closer to a broad end-to-end suite. Consider one route smoke per surface plus one off-shift redirect and move detailed branches to isolated tests in later feature groups.

## Open Questions for the Implementer

- Should the scaffold enforce read authorization for announcements and conversations now? This review says yes; deferring it creates an insecure route contract.
- Should `FoyerWeb.Scope` use `typed_struct`, or is a plain defstruct better to avoid adding a dependency only for one web-layer struct?
- Should the off-shift bottom nav render disabled buttons for House/Chat/Me, or links that redirect with flash? The plan has disabled buttons plus hard route redirects; tests only cover direct navigation.
- Should `member_count` be denormalized in v0 if writes that maintain it are deferred? A query-time count may be safer until channel membership writes exist.
- What is the direct conversation uniqueness rule? If the app can create DMs later, the schema needs a canonical direct conversation key or a transaction that prevents duplicate participant sets.
- Should Profile and Today receive DTO structs instead of maps? ARCHITECTURE.md asks for typed boundaries and no bare maps; §6.7 and §6.8 currently define map types.
- Are the design strings with non-ASCII punctuation intentional implementation copy? If yes, normalize tests carefully; if no, use ASCII in code and avoid brittle exact-copy assertions.
