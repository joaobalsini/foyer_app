# Review — Plan 01 Channels feature group

## Verdict

Revise

The plan is directionally useful, but it cannot be executed safely until the manager-membership seed contradiction, PeopleLive collection strategy, and required query-count test are resolved.

## Strengths

- The plan correctly keeps channel administration out of v1 and limits writes to seed data.
- The proposed `member?/2` and `member_count/1` APIs fill real gaps in the current `Foyer.ChannelsPort`.
- It verifies the actual scaffold state for `Accounts.list_people/1`: the current implementation preloads `memberships: :channel`, which is the right data shape for membership pills.
- The plan keeps data loading in `handle_params/3`, matching the existing PeopleLive pattern and ARCHITECTURE.md.

## Critical Issues

### §7 Manager Membership Contradicts The Spec And Itself

Contradiction: `F.Channels.12` says managers are seeded into all default property channels, while `F.Channels.19` says manager role alone grants no access and uses a manager not in "Engineering" as the example. The current seed data includes `engineering` as a default channel, and the plan simultaneously says Rafael must be in all channels and that Charlotte/Rafael must not be in Engineering.

Fix: resolve the product/spec rule before execution. Recommended: keep "manager role alone grants no access" as the invariant and narrow the seed clause to "managers are seeded into all operational channels they are expected to manage, not every default channel." Update the spec and plan together, then test the actual intended rule:

```text
F.Channels.12 should assert manager membership in Leadership, Linden · All staff,
and their managed departments.

F.Channels.19 should assert a manager missing Engineering membership does not see Engineering.
```

If product truly wants every manager in every default channel, delete the Engineering non-membership example from `F.Channels.19`; both cannot be true against the current seeded channel set.

### §5.1 People Directory Adds List Filtering While Ignoring LiveView Stream Policy

Risk: The plan keeps `@people` as a plain list and filters it in a template helper. AGENTS.md says collections should use LiveView streams to avoid memory ballooning, and the plan is explicitly touching the People Directory collection surface. If executed as written, this feature group will entrench the scaffold shortcut instead of correcting it.

Fix: either explicitly justify why People Directory is a bounded non-stream list in v1, or convert the index to streams now. Preferred implementation:

```elixir
defp apply_index(socket) do
  people = FoyerWeb.LiveDeps.accounts().list_people([])

  {:noreply,
   socket
   |> assign(:people_empty?, people == [])
   |> assign(:on_shift_ids, FoyerWeb.LiveDeps.shifts().users_on_shift_ids())
   |> assign(:active_channel_filter, nil)
   |> stream(:people, people, reset: true)}
end

def handle_event("filter_channel", %{"channel_id" => channel_id}, socket) do
  people = FoyerWeb.LiveDeps.accounts().list_people(channel_id: channel_id)

  {:noreply,
   socket
   |> assign(:active_channel_filter, channel_id)
   |> stream(:people, people, reset: true)}
end
```

That requires adding `list_people/1` filter semantics to `AccountsPort` or introducing a Channels-owned directory DTO/query. Do not filter `@streams.people` with `Enum`.

### §8.3 Downgrades `F.Channels.20` From Required To Nice-To-Have

Bug: The spec requires `list_all_with_member_counts/0` to issue at most 2 queries. The plan says a telemetry/query-count assertion is "nice-to-have, not blocking." That means the execute phase can pass without proving the clause.

Fix: make the query-count assertion mandatory. Use a test helper that attaches to `[:foyer, :repo, :query]` or the configured Ecto repo telemetry event and counts non-cache queries around the function call. The test name should include `F.Channels.20`.

### §8.1 Duplicate Slug Is Listed As A Pure Unit Test

Bug: `unique_constraint(:slug)` only becomes a changeset error after a Repo insert/update hits the unique index. A no-DB changeset unit test cannot prove `F.Channels.1`.

Fix: move duplicate slug coverage entirely to an integration test. Keep the pure unit test for required fields and enum casting only.

## Spec drift / missing clauses

- The Channels spec is missing an explicit clause for People Directory channel filtering, even though the plan adds it. Add a clause that tests selecting a channel shows only users with a real membership in that channel and clearing the filter restores all rows.
- The spec should clarify whether manager seed membership is "all default channels" or "all manager-relevant channels." Current `F.Channels.12` and `F.Channels.19` are not jointly satisfiable with the current seeds.
- `F.Channels.17` mentions "row or profile card" but the Channels spec does not define the `Profile.Card` contract. If profile-card memberships remain a Channels requirement, add a clause that the colleague detail surface receives memberships from an owned API, not from accidental preloads.

## Cross-plan concerns

- Channels says `Foyer.Profile.Card` needs memberships or PeopleLive must load memberships separately. The Profile plan does not add memberships to `Card` and does not acknowledge channel pills on colleague profile cards. Recommended: keep memberships out of `Profile.Card` and have `PeopleLive :show` assign a separate `channels` list from `LiveDeps.channels().list_for_user(target)` to a Channels-owned rendering area.
- Channels and Profile both plan to edit `PeopleLive :show`. Sequence these plans or one will overwrite the other's assumptions about `profile_card` attrs, public-recognition filtering, and membership pills.
- The proposed stream fix may require `Accounts.list_people/1` filter semantics. Channels does not own Accounts, so either document this as a scaffold/account dependency or keep the filter as an in-memory bounded-list exception with a clear reason.

## Nits

- Prefer `member?(User.t(), Channel.t() | integer())` only if there is a real caller with just an id. Otherwise keep the narrower `Channel.t()` callback and avoid expanding the port prematurely.
- `member?/2` should use `Repo.exists?/1`, not `count > 0`.
- The seed test should not depend on a globally pre-seeded database. Recreate the relevant seed shape inside the sandbox or call a test fixture helper.
- `F.Channels.15` tests should assert stable row IDs like `#people-row-#{id}` rather than names alone.

## Open questions raised by the original plan

- `Foyer.Profile.Card` memberships: resolve as "do not add to Profile.Card." Channels can render channel memberships in PeopleLive from `Channels.list_for_user/1`, keeping Profile focused on recognition/points.
- Should `member?/2` accept `channel_id` or `Channel.t()`? Recommended: start with `Channel.t()` per spec; add an integer overload only when a concrete caller needs it.
- `list_all_with_member_counts/0` query-count assertion strategy: do not defer. Add a mandatory telemetry-based query-count helper for `F.Channels.20`.
