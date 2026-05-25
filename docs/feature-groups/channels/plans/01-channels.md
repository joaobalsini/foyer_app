# Plan 01 — Channels feature group

Status: revised after Codex review (v2)
Scope: `Foyer.Channels` context, `ChannelsPort` behaviour, `PeopleLive` finishing, seeds,
tests for all `F.Channels.*` clauses
Spec: [`../spec.md`](../spec.md)
Review: [`01-channels-review.md`](./01-channels-review.md)

---

## Revision log

**v2 — addressed Codex review of 2026-05-25.** Key changes (see review doc for
full rationale):

- **§7 / spec F.Channels.12**: Resolved the manager-membership contradiction. The invariant
  "manager role alone grants no access" (FOYER.md, F.Channels.19) is preserved. F.Channels.12
  is narrowed: managers are seeded into Leadership, Linden · All staff, and their own managed
  department, NOT every channel. F.Channels.19's Engineering non-membership example remains
  valid. Spec, seed audit table, and seed-fix guidance updated accordingly.
- **§5.1 PeopleLive streams**: Replaced the plain `@people` list + `filtered_people/2`
  template helper with LiveView streams + server-side re-query on filter click, per AGENTS.md's
  "always use streams for collections" rule. `apply_index/1` now calls `stream(:people, ...)`;
  `handle_event("filter_channel", ...)` re-fetches and resets the stream. `Accounts.list_people/1`
  filter semantics are required; documented as a cross-group dependency.
- **§8.3 F.Channels.20 query-count test**: Elevated from "nice-to-have" to mandatory.
  The test must use a telemetry-based query-count helper attached to Ecto repo events.
- **§8.1 F.Channels.1 slug duplicate**: Moved from pure unit test to integration test.
  The unit test covers only required-fields and enum-casting.
- **§4 `member?/2` signature**: Narrowed to `Channel.t()` only; integer overload deferred
  until a concrete caller requires it.
- **§4 `member?/2` implementation**: Explicitly requires `Repo.exists?/1` (not `count > 0`).
- **§5.1 / §10 Profile.Card**: Resolved open question — channel memberships must NOT be
  added to `Profile.Card`. `PeopleLive :show` loads them via `Channels.list_for_user/1` into
  a separate `:target_channels` assign. Added cross-group dependencies section.
- **§8.4 Seed test**: Now uses an in-test fixture (not globally pre-seeded DB) to avoid
  external state coupling.
- **§8.5 F.Channels.15**: Row assertions updated to use stable DOM IDs (`#people-row-#{id}`).
- **Spec additions**: Added F.Channels.21 (filter clause) and F.Channels.22 (Profile.Card
  boundary clause) to spec. F.Channels.12 narrowed. No clauses renumbered.

---

## 1. Goal & non-goals

### Goal

Solidify `Foyer.Channels` from the scaffold-era stub into a fully tested, spec-compliant module
that all other feature groups can depend on without surprises. Concretely:

- Complete the context API with `member?/2` and `member_count/1` (both missing from the scaffold).
- Add those two callbacks to `ChannelsPort`.
- Confirm `list_for_user/1`, `list_all_with_member_counts/0`, and `get!/1` match their spec clauses
  with real integration tests.
- Write isolated unit tests for `Channel.changeset/2` and `Membership.changeset/2` covering all
  validation clauses.
- Finish `PeopleLive` so that it renders channel membership pills per `F.Channels.17`, not just
  names and on-shift dots. The scaffold renders a bare name list; the Channels group owns the
  membership pill surface.
- Ensure seeds satisfy `F.Channels.12–14` (manager-in-all, staff-in-department, all-in-general).
  Seeds are already close; this plan audits and adjusts rather than rewrites.
- Write the full test suite (isolated, integration, e2e smoke) per `docs/TESTING_GUIDE.md`.

### Non-goals

- Channel administration (create/edit/archive) — v2, per FOYER.md.
- Any write path on `Foyer.Channels` beyond what seeds call — no `create_channel/1` or
  `add_member/2` in v1.
- PubSub broadcasts on membership change — there are no membership writes, so nothing to broadcast.
- Announcement targeting, chat access, handoff channel gating — owned by House, Chat, and Shifts
  respectively. Those groups consume `list_for_user/1` and `get!/1`; their own spec clauses cover
  the access semantics.
- Desktop layout polish for `PeopleLive` — the scaffold renders a sidebar filter stub. This plan
  wires the filter stub to real data for the channel dimension; full desktop layout polish is
  deferred to a future UI pass.

---

## 2. Schemas

Both schemas were created in the scaffold. This section restates the contract the Channels group
needs and calls out the one delta: `member?/2` and `member_count/1` are context-level functions
(not schema fields), so no migration change is needed.

### 2.1 `Foyer.Channels.Channel` — `lib/foyer/channels/channel.ex`

```elixir
defmodule Foyer.Channels.Channel do
  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          slug: String.t() | nil,
          kind: :department | :general | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
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

**Validations**: `:name`, `:slug`, `:kind` are all required (covers `F.Channels.2`). The
`unique_constraint(:slug)` maps to the DB-level `unique_index(:channels, [:slug])` (covers
`F.Channels.1`). `:kind` is backed by `Ecto.Enum`; any value outside `[:department, :general]`
produces a cast error (covers `F.Channels.3`).

**No schema delta needed.** Member counts remain computed at query time (no `member_count` column),
as decided in the scaffold plan §5.3.

### 2.2 `Foyer.Channels.Membership` — `lib/foyer/channels/membership.ex`

```elixir
defmodule Foyer.Channels.Membership do
  @type t :: %__MODULE__{
          id: integer() | nil,
          user_id: integer() | nil,
          channel_id: integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "channel_memberships" do
    belongs_to :user, Foyer.Accounts.User
    belongs_to :channel, Foyer.Channels.Channel

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:user_id, :channel_id])
    |> validate_required([:user_id, :channel_id])
    |> unique_constraint([:user_id, :channel_id],
        name: :channel_memberships_user_id_channel_id_index)
  end
end
```

**Validations**: both `:user_id` and `:channel_id` are required (covers `F.Channels.5`). The named
unique constraint maps to the named index from the migration (covers `F.Channels.4`).

**No schema delta needed.**

---

## 3. Migrations

No new migrations are required. Both tables (`channels` and `channel_memberships`) were created in
the scaffold with the correct columns, indexes, and foreign-key constraints.

For reference, the existing indexes that back the Channels API:

| Index | Purpose |
|---|---|
| `unique_index(:channels, [:slug])` | `F.Channels.1` slug uniqueness |
| `unique_index(:channel_memberships, [:user_id, :channel_id], name: :channel_memberships_user_id_channel_id_index)` | `F.Channels.4` membership uniqueness |
| `index(:channel_memberships, [:channel_id])` | `list_all_with_member_counts/0` count join |

If this plan introduces a `member?/2` function backed by a point-lookup query
`WHERE user_id = ? AND channel_id = ?`, both the `(user_id, channel_id)` unique index and the
`(channel_id)` index cover this without any new index. No `CREATE INDEX CONCURRENTLY` step is
needed.

---

## 4. Context API

### 4.1 Port behaviour — `lib/foyer/channels_port.ex`

Delta: add two new callbacks (`member?/2` and `member_count/1`) to the existing port. The three
scaffold callbacks (`list_for_user/1`, `list_all_with_member_counts/0`, `get!/1`) are unchanged.

```elixir
defmodule Foyer.ChannelsPort do
  @moduledoc """
  Behaviour for `Foyer.Channels`. All LiveViews that need channel data resolve
  this via `FoyerWeb.LiveDeps.channels()`.
  """

  alias Foyer.Accounts.User
  alias Foyer.Channels.Channel

  @callback list_for_user(User.t()) :: [Channel.t()]
  @callback list_all_with_member_counts() :: [{Channel.t(), non_neg_integer()}]
  @callback get!(integer() | String.t()) :: Channel.t()
  @callback member?(User.t(), Channel.t()) :: boolean()
  @callback member_count(Channel.t()) :: non_neg_integer()
end
```

`member?/2` accepts `Channel.t()` only. An integer overload is NOT added at this stage; add it
only when a concrete caller requires a bare `channel_id` (per review: "start with `Channel.t()`;
add integer overload only when a concrete caller needs it").

### 4.2 Real context — `lib/foyer/channels.ex`

All five functions are `:real` (Repo-backed). Full signatures:

```elixir
defmodule Foyer.Channels do
  @behaviour Foyer.ChannelsPort

  @spec list_for_user(User.t()) :: [Channel.t()]
  # Existing implementation — unchanged.
  # Joins channel_memberships, orders by name asc.
  # Backed by unique_index(:channel_memberships, [:user_id, :channel_id]) and
  # index(:channel_memberships, [:channel_id]).

  @spec list_all_with_member_counts() :: [{Channel.t(), non_neg_integer()}]
  # Existing implementation — unchanged.
  # Two queries: one grouped count over channel_memberships keyed by channel_id,
  # one select all channels. Zipped in Elixir. Total: 2 queries, no N+1
  # (covers F.Channels.20).

  @spec get!(integer() | String.t()) :: Channel.t()
  # Existing implementation — unchanged.
  # Repo.get!(Channel, id) — raises Ecto.NoResultsError on miss.

  @spec member?(User.t(), Channel.t()) :: boolean()
  # NEW. Point-lookup using Repo.exists?/1 — do NOT use count > 0.
  # query = from(m in Membership,
  #   where: m.user_id == ^user.id and m.channel_id == ^channel.id)
  # Repo.exists?(query)
  # Backed by unique_index(:channel_memberships, [:user_id, :channel_id]).

  @spec member_count(Channel.t()) :: non_neg_integer()
  # NEW. Aggregate query.
  # from(m in Membership,
  #   where: m.channel_id == ^channel.id,
  #   select: count(m.id)
  # ) |> Repo.one()
  # Backed by index(:channel_memberships, [:channel_id]).
end
```

**Implementation notes:**

- `member?/2` MUST use `Repo.exists?/1`, not `count > 0`. This is a single indexed point-lookup.
- `member_count/1` uses `Repo.aggregate(query, :count)` or `Repo.one(count_query)`. Either form
  is fine; pick the one that reads more clearly to the implementing agent.
- `list_all_with_member_counts/0` already issues exactly 2 queries (verified against the scaffold
  implementation). No change needed, but the test for `F.Channels.20` MUST confirm this with a
  telemetry-based query-count helper (see §8.3).

### 4.3 Mox mock — `test/test_helper.exs` addition

The scaffold already registers the mock:

```elixir
Mox.defmock(Foyer.ChannelsMock, for: Foyer.ChannelsPort)
```

With the two new callbacks added to `ChannelsPort`, the mock automatically requires them to be
stubbed or expected. No change to `test_helper.exs` beyond confirming it is already present.
**If it is absent, add it.**

---

## 5. LiveViews touched

### 5.1 `FoyerWeb.PeopleLive` — `lib/foyer_web/live/people_live.ex`

This is the only LiveView the Channels group owns. The scaffold version renders a people list with
name, title, and on-shift pulse but does NOT render channel membership pills. This plan finishes it.

**Changes:**

1. The `:index` action calls `FoyerWeb.LiveDeps.accounts().list_people([])`, which preloads
   `memberships: :channel`. The template renders channel names as `foyer-tag outline` pills per each
   person's memberships. Add a pill line under the title in each row.

2. **People list must use LiveView streams** (per AGENTS.md: "always use streams for collections").
   Do NOT assign `@people` as a plain list — this would balloon memory for large properties.
   `apply_index/1` must stream the people collection; filter events must re-fetch from the DB and
   reset the stream.

3. Add a desktop filter sidebar (the scaffold renders stub text "All / On shift / Off shift /
   Managers"). Wire the "Channel" filter dimension: show a list of all channels with member counts
   (from `FoyerWeb.LiveDeps.channels().list_all_with_member_counts/0`) and allow clicking a channel
   to filter the people list to members only.

4. The `:show` action: load the target user's channel memberships via
   `FoyerWeb.LiveDeps.channels().list_for_user(target_user)` into a separate `:target_channels`
   assign. Do NOT source memberships from `card.user.memberships` or from `Profile.Card`.
   See §10 and the cross-group dependencies section.

**`apply_index/1` (called from `handle_params/3`):**

```elixir
defp apply_index(socket) do
  people = FoyerWeb.LiveDeps.accounts().list_people([])

  {:noreply,
   socket
   |> assign(:people_empty?, people == [])
   |> assign(:on_shift_ids, FoyerWeb.LiveDeps.shifts().users_on_shift_ids())
   |> assign(:channel_filter_options, FoyerWeb.LiveDeps.channels().list_all_with_member_counts())
   |> assign(:active_channel_filter, nil)
   |> stream(:people, people, reset: true)}
end
```

**Event handler — filter by channel (re-fetches from DB, resets stream):**

```elixir
def handle_event("filter_channel", %{"channel_id" => channel_id}, socket) do
  people = FoyerWeb.LiveDeps.accounts().list_people(channel_id: channel_id)

  {:noreply,
   socket
   |> assign(:people_empty?, people == [])
   |> assign(:active_channel_filter, channel_id)
   |> stream(:people, people, reset: true)}
end

def handle_event("clear_filter", _params, socket) do
  apply_index(socket)
end
```

**Template — stream-aware people list:**

```heex
<div id="people" phx-update="stream">
  <div :for={{dom_id, person} <- @streams.people} id={dom_id}>
    <%# render person row with pills %>
  </div>
</div>
```

Do NOT use `Enum.filter/2` on `@streams.people` — streams are not enumerable. All filtering
happens server-side by re-fetching with the appropriate filter and calling `stream/4` with
`reset: true`.

**`Accounts.list_people/1` filter semantics dependency:**

The `filter_channel` event handler calls `list_people(channel_id: channel_id)`. This requires
`Accounts.list_people/1` (and `AccountsPort`) to support a `channel_id:` keyword option that
joins `channel_memberships` and filters by `channel_id`. This is a cross-group dependency on
the Accounts context — see the "Cross-group dependencies" section below.

**`apply_show/2` — target user channel memberships:**

```elixir
defp apply_show(socket, target_id) do
  target_user = FoyerWeb.LiveDeps.accounts().get_user!(target_id)
  card = FoyerWeb.LiveDeps.profile().profile_for(target_user)
  target_channels = FoyerWeb.LiveDeps.channels().list_for_user(target_user)

  {:noreply,
   socket
   |> assign(:card, card)
   |> assign(:target_channels, target_channels)}
end
```

The template renders `@target_channels` for the membership pills section in `:show`.

**Discipline:** all data loads remain in `handle_params/3` (via `apply_index/1` and
`apply_show/2`). The channel filter options are loaded once per `handle_params/3` call; they
do not refresh on filter click events.

**Cross-reference:** `PeopleLive` consumes `FoyerWeb.LiveDeps.accounts()` (for `list_people`,
`get_user!`), `FoyerWeb.LiveDeps.channels()` (for `list_all_with_member_counts`, `list_for_user`),
and `FoyerWeb.LiveDeps.profile()` (for `profile_for`). All three are already wired in `LiveDeps`.

### 5.2 Cross-references only (no changes in this group)

- `FoyerWeb.AnnouncementLive` calls `channels().list_for_user/1` for the audience picker. Tested
  in the House group's spec. The Channels group's tests confirm `list_for_user/1` returns the
  correct set; AnnouncementLive's tests mock it via `ChannelsMock`.
- `FoyerWeb.ChatLive` calls `channels().list_for_user/1` for the "New message" channel tab.
  Same pattern — Chat group tests mock it.

---

## 6. Routes

No new routes. `PeopleLive` is already mounted at `/people` (`:index`) and `/people/:id`
(`:show`) under `:authenticated_on_shift`. The route guard at `:ensure_on_shift` enforces
`F.Channels.18` (off-shift users are redirected to `/today`).

For reference:

```elixir
live "/people",     PeopleLive, :index
live "/people/:id", PeopleLive, :show
```

Both are in the `:authenticated_on_shift` `live_session`, which runs `FoyerWeb.UserAuth.ensure_on_shift/4`.

---

## 7. Seeds

The existing `priv/repo/seeds.exs` satisfies most spec clauses. The audit below reflects the
narrowed `F.Channels.12` rule: managers are seeded into their operational channels, not every
channel.

### 7.1 Audit against spec

| Spec clause | Seed requirement | Current state |
|---|---|---|
| `F.Channels.12` — managers in operational channels | Charlotte (Housekeeping Dir.), Rafael (Night Manager), Sebastien (Chef) must be in "Leadership" + "Linden · All staff" + their managed department | Charlotte: in `housekeeping-floor-4`, `all-housekeeping`, `leadership`, `linden-all`. Satisfied. Rafael: in `leadership`, `linden-all`. He manages Front Office, not in `concierge-front-office`. **Gap: Rafael should be added to `concierge-front-office` as his managed dept.** Sebastien: in `f-and-b`, `leadership`, `linden-all`. Satisfied. |
| `F.Channels.13` — staff in their department | Maya, Aisha in Housekeeping channels; Tomás, Leila in Front Office; etc. | Satisfied. |
| `F.Channels.14` — all staff in `linden-all` | Every seeded user in `"linden-all"` | Satisfied: seed uses `Map.keys(users)`. |
| `F.Channels.19` — manager access is membership-based | Hugo Brandt (staff, Engineering) is the only Engineering member. Charlotte and Rafael have NO Engineering membership. | Charlotte is not in Engineering; Rafael is not in Engineering. Satisfied. F.Channels.19 is valid: a manager NOT in Engineering cannot access Engineering. |

### 7.2 Required seed fix

The only gap is Rafael Mendes. He is the Night Manager responsible for Front Office, but is not in
the `concierge-front-office` channel. The fix is narrow: add `"Rafael Mendes"` to the
`"concierge-front-office"` member list in `channel_specs`.

**No other manager memberships require changes.** Managers are NOT expected to be in Engineering
or every other department channel — this aligns with FOYER.md: "managers do not get a hidden
override into non-member channels."

**Concrete change**: add `"Rafael Mendes"` to the `"concierge-front-office"` member list:

```elixir
{"concierge-front-office", "Concierge & Front Office", :department,
 ["Tomás Ruiz", "Leila Haddad", "Rafael Mendes"]},
```

### 7.3 Seed verification

After seeds run, a sanity check in `iex -S mix`:

```elixir
# Rafael should be in: linden-all, leadership, concierge-front-office (3 channels).
Foyer.Channels.list_for_user(Foyer.Repo.get_by!(Foyer.Accounts.User, name: "Rafael Mendes"))
|> Enum.map(& &1.name)
# => ["Concierge & Front Office", "Leadership", "Linden · All staff"]

# Engineering still has only Hugo Brandt (proves F.Channels.19).
Foyer.Channels.member_count(Foyer.Repo.get_by!(Foyer.Channels.Channel, slug: "engineering"))
# => 1
```

---

## 8. Test strategy

Following `docs/TESTING_GUIDE.md`: isolated tests by default (`async: true`); integration
(`@tag :integration`) for Repo-backed tests; route smoke tests for wiring confidence.

### 8.1 Changeset unit tests — `test/foyer/channels/channel_test.exs`

`async: true`. No DB, no Mox. Cover:

- `F.Channels.2` — missing `:name`, `:slug`, `:kind` individually and together.
- `F.Channels.3` — invalid `:kind` value.

**Note on F.Channels.1:** `unique_constraint(:slug)` only becomes a changeset error after a Repo
insert hits the unique index. A no-DB changeset unit test cannot prove `F.Channels.1`. Coverage
for `F.Channels.1` lives entirely in the integration tests (§8.3).

### 8.2 Changeset unit tests — `test/foyer/channels/membership_test.exs`

`async: true`. No DB.

- `F.Channels.4` — duplicate `(user_id, channel_id)` → changeset error (uses the named constraint
  name). This requires an integration test since the unique constraint is DB-enforced; see 8.3.
- `F.Channels.5` — missing `:user_id` or `:channel_id` → changeset error. Pure changeset unit.

### 8.3 Context integration tests — `test/foyer/channels_test.exs`

`@tag :integration`, `async: false` (Ecto sandbox). Cover all API spec clauses:

- `F.Channels.1` — insert duplicate slug via `Repo.insert/1` → `{:error, %Ecto.Changeset{errors: [{:slug, _}]}}`.
  (Pure unit test cannot prove this — unique constraint is DB-enforced.)
- `F.Channels.4` — insert duplicate membership → `{:error, %Ecto.Changeset{}}`.
- `F.Channels.6` — `list_for_user/1` correct set and order.
- `F.Channels.7` — `list_for_user/1` empty for memberless user.
- `F.Channels.8` — `get!/1` raises for unknown id.
- `F.Channels.9` — `list_all_with_member_counts/0` correct tuples and order.
- `F.Channels.10` — `member?/2` true and false cases.
- `F.Channels.11` — `member_count/1` exact count.
- `F.Channels.19` — manager with no Engineering membership returns false from `member?/2` for
  Engineering channel.
- `F.Channels.20` — **mandatory** query-count assertion: `list_all_with_member_counts/0` issues at
  most 2 DB queries. Use a telemetry handler attached to the Ecto repo's `[:foyer, :repo, :query]`
  event (or the configured Ecto telemetry event) that increments a counter, then assert
  `counter <= 2` after the call. Do NOT defer or mark this as nice-to-have; the test name must
  include `F.Channels.20`.

  ```elixir
  test "F.Channels.20 — list_all_with_member_counts/0 issues at most 2 queries" do
    ref = :counters.new(1, [])
    handler = fn _event, _measurements, _metadata, _config ->
      :counters.add(ref, 1, 1)
    end
    :telemetry.attach("query-counter", [:foyer, :repo, :query], handler, nil)
    on_exit(fn -> :telemetry.detach("query-counter") end)

    _result = Foyer.Channels.list_all_with_member_counts()

    assert :counters.get(ref, 1) <= 2
  end
  ```

Each test name must include the `F.Channels.<N>` reference, e.g.:

```elixir
test "F.Channels.6 — list_for_user/1 returns only the caller's channels" do
  ...
end
```

### 8.4 Seed integration test — `test/foyer/channels_seed_test.exs`

`@tag :integration`, `async: false`. Do NOT depend on a globally pre-seeded database. Instead,
recreate the relevant seed shape inside the Ecto sandbox `setup` block using direct `Repo.insert!`
calls (or a `ScaffoldFixtures` helper). This keeps the test hermetic and repeatable in CI without
a separate seed step.

Cover:

- `F.Channels.12` — each manager user has `list_for_user(manager)` containing at least
  "Leadership" and "Linden · All staff" plus their managed department channel. Assert the specific
  channels (not a total count), since managers are NOT expected to be in every channel.
- `F.Channels.13` — a Housekeeping staff user has at least one channel whose slug includes
  "housekeeping". Does NOT include "Leadership".
- `F.Channels.14` — every seeded user (recreated in `setup`) has the `linden-all` channel in
  their list.

Example `setup` pattern:

```elixir
setup do
  manager = Repo.insert!(%User{name: "Test Manager", role: :manager, ...})
  staff   = Repo.insert!(%User{name: "Test Staff", role: :staff, ...})
  linden_all = Repo.insert!(%Channel{name: "Linden · All staff", slug: "linden-all", kind: :general})
  leadership = Repo.insert!(%Channel{name: "Leadership", slug: "leadership", kind: :department})
  hk = Repo.insert!(%Channel{name: "All Housekeeping", slug: "all-housekeeping", kind: :department})

  for {u, c} <- [{manager, linden_all}, {manager, leadership}, {staff, linden_all}, {staff, hk}] do
    Repo.insert!(%Membership{user_id: u.id, channel_id: c.id})
  end

  %{manager: manager, staff: staff, linden_all: linden_all}
end
```

### 8.5 Isolated LiveView tests — `test/foyer_web/live/people_live_test.exs`

`async: true`. Mount with `live_isolated/3`, inject `ChannelsMock` and `AccountsMock` via
`FoyerWeb.LiveDeps`. Cover:

- `F.Channels.15` — people list renders a row for each user. Assertions must use stable DOM IDs
  (`#people-row-#{user.id}`), not names alone, to avoid false positives when names share substrings.
- `F.Channels.16` — on-shift pulse renders for on-shift user, absent for off-shift.
- `F.Channels.17` — channel pills render for a user with two memberships; absent channel does not
  appear.
- `F.Channels.21` — selecting a channel filter emits `"filter_channel"`, re-streams only members
  of that channel; clearing the filter restores all rows.

Use scenario modules under `test/support/scenarios/`:

```elixir
defmodule Foyer.ChannelsScenarios.TwoChannels do
  @behaviour Foyer.ChannelsPort

  def list_for_user(_user), do: [build_channel("Floor 4"), build_channel("All Housekeeping")]
  def list_all_with_member_counts(), do: [{build_channel("Floor 4"), 4}, {build_channel("All Housekeeping"), 7}]
  def get!(id), do: build_channel("Floor 4", id: id)
  def member?(_user, _channel), do: true
  def member_count(_channel), do: 4
end
```

After `live_isolated/3`, call `Mox.allow(Foyer.ChannelsMock, self(), view.pid)` before events.

**Row ID convention:** each person row in the template must carry `id={"people-row-#{person.id}"}`.
The test asserts `assert has_element?(view, "#people-row-#{user.id}")`. This is required — tests
that rely on display names alone are fragile.

### 8.6 Route smoke test — addition to `test/foyer_web/scaffold_smoke_test.exs`

Or a dedicated `test/foyer_web/live/people_live_route_test.exs`. `@tag :integration`, `async: false`.
Tests:

- `F.Channels.18` — off-shift user navigating to `/people` is redirected to `/today`.
- Happy path: on-shift user sees `/people` with at least one person row.

---

## 9. Step-by-step execution order

1. **Audit and adjust seeds** (`priv/repo/seeds.exs`). Add `"Rafael Mendes"` to the
   `"concierge-front-office"` member list per §7.2. Verify via iex sanity check in §7.3.
   No Elixir module changes.

2. **Extend `ChannelsPort`** (`lib/foyer/channels_port.ex`). Add
   `@callback member?(User.t(), Channel.t()) :: boolean()` and
   `@callback member_count(Channel.t()) :: non_neg_integer()`.

3. **Implement `member?/2` and `member_count/1`** in `lib/foyer/channels.ex`. Use
   `Repo.exists?/1` for `member?/2`. Add `@impl true` and `@spec` for both. Run
   `mix dialyzer` after this step — the port behaviour will fail if signatures don't match.

4. **Confirm `Accounts.list_people/1` filter semantics** are available (cross-group dependency).
   If the `channel_id:` keyword filter is not yet implemented in the Accounts context, coordinate
   with the Accounts group or implement a bounded in-memory fallback with a TODO.

5. **Write changeset unit tests** (`test/foyer/channels/channel_test.exs` and
   `test/foyer/channels/membership_test.exs`). Pure unit tests (no DB). Run `mix test` to
   confirm they pass.

6. **Write context integration tests** (`test/foyer/channels_test.exs`). Run with
   `MIX_ENV=test mix test test/foyer/channels_test.exs`. All `F.Channels.1–11`, `F.Channels.19–20`
   clauses should be green, including the mandatory telemetry query-count test for `F.Channels.20`.

7. **Write seed integration tests** (`test/foyer/channels_seed_test.exs`). Use in-test fixtures
   (not global seeds). Confirm `F.Channels.12–14` pass.

8. **Add scenario modules** (`test/support/scenarios/channels_scenarios.ex`). Define at minimum:
   `ChannelsScenarios.Empty`, `ChannelsScenarios.TwoChannels`. Implement the full `ChannelsPort`
   behaviour in each.

9. **Update `PeopleLive`** (`lib/foyer_web/live/people_live.ex`):
   - `:index` — stream people via `stream(:people, ...)`, add channel membership pills, wire the
     channel filter sidebar (`channel_filter_options`, `active_channel_filter`). Filter events
     re-fetch and reset the stream.
   - `:show` — add `apply_show/2` that loads `@target_channels` via `Channels.list_for_user/1`.
   - Keep all data loads in `handle_params/3`. Confirm `mount/3` stays cheap.

10. **Write isolated LiveView tests** (`test/foyer_web/live/people_live_test.exs`). Cover
    `F.Channels.15–17` and `F.Channels.21` with `live_isolated/3` and scenario modules. Assert
    on stable DOM IDs (`#people-row-#{id}`).

11. **Write route smoke tests** for `PeopleLive` (`F.Channels.18`). Confirm off-shift redirect
    and on-shift render against real seeds.

12. **Run full static checks**: `mix format`, `mix credo --strict`, `mix dialyzer`. Fix any
    issues before marking the group done.

13. **Run full test suite**: `mix test`. Confirm no regressions in scaffold smoke tests.

---

## 10. Risks and trade-offs

### Risk: N+1 in `PeopleLive` channel pills

`list_people/1` already preloads `memberships: :channel` (per scaffold plan §6.1). If the
implementing agent changes this preload, the channel pills will trigger N+1 queries. The test for
`F.Channels.17` should assert on rendered HTML, not on query counts, but the implementing agent
must not remove the `memberships: :channel` preload from `Accounts.list_people/1`.

### Risk: Seed change for `F.Channels.12` affects downstream snapshot tests

Adding Rafael to `concierge-front-office` changes the seed data shape. Any smoke test that asserts
on the exact members-per-channel count will need updating. The scaffold smoke test does not make
such assertions, but if the implementing agent finds any, they should update them.

### Trade-off: Channel filter is server-side re-query

The `filter_channel` event re-fetches from the DB and resets the stream, rather than filtering an
in-memory list. This is required by AGENTS.md (streams are not enumerable; use `reset: true` with a
new fetch). The people list is small in v1 (< 100 staff), so re-fetch latency is negligible.

### Resolved: `Foyer.Profile.Card` does not and should not expose channel memberships

**Decision (from Codex review):** do NOT add a `memberships` field to `Profile.Card`. Channel
memberships are loaded separately in `PeopleLive.apply_show/2` via
`FoyerWeb.LiveDeps.channels().list_for_user(target_user)` and assigned to `:target_channels`.
Profile context remains focused on recognition/points. This is covered by new spec clause
`F.Channels.22`.

### Resolved: `member?/2` signature

**Decision:** `Channel.t()` only. No integer overload until a concrete caller requires it.

### Resolved: `list_all_with_member_counts/0` query-count assertion

**Decision:** mandatory telemetry-based query-count helper per §8.3. Not optional.

---

## 11. Cross-group dependencies

### Channels → Accounts: `list_people/1` channel filter

`PeopleLive`'s channel filter calls `FoyerWeb.LiveDeps.accounts().list_people(channel_id: channel_id)`.
This requires `Accounts.list_people/1` (and `AccountsPort`) to accept a `channel_id:` keyword
option and join `channel_memberships` when it is present. **The Accounts group must add this filter
semantics before or alongside this plan's execution.** If blocked, the filter can temporarily
fall back to an in-memory `Enum.filter/2` on a plain-list assign (explicitly justified as a
bounded V1 exception with a TODO comment), but this must be replaced before the plan is marked done.

### Channels → Profile: `PeopleLive :show` sequencing

Both the Channels plan and the Profile plan touch `PeopleLive :show`. They must not overwrite each
other's assigns. Agreed split:

- **Profile** owns: `@card` (from `Profile.profile_for/1`), recognition/points rendering.
- **Channels** owns: `@target_channels` (from `Channels.list_for_user/1`), membership pills section.

The implementing agents must coordinate the order of `apply_show/2` changes or use a shared PR
to avoid conflicts on `people_live.ex`.

### Channels → Profile: `Profile.Card` must NOT grow `memberships`

The Profile agent's concurrent revision must NOT add a `memberships` field to `Foyer.Profile.Card`.
Channels owns the membership-rendering surface in `PeopleLive` and loads channel data directly.
This is formalised in spec clause `F.Channels.22`.
