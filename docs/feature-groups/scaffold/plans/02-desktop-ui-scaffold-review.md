# Review — Plan 02 Desktop UI scaffold

## Verdict

Revise

The side-rail direction and `md:` breakpoint are defensible, but the plan is not safe to execute as written. The largest problems are scope expansion into new House feature routes without any desktop design artifacts present, route ordering that would make those routes unreachable, chat desktop state that only works after navigating through `/chat`, and smoke tests that claim redirect coverage while asserting the opposite.

## Strengths

- §2 lines 73-93 makes the `md:` breakpoint explicit and aligns it with the existing People Directory responsive breakpoint in `lib/foyer_web/live/people_live.ex` lines 78-79.
- §4.1 lines 351-362 keeps `desktop_rail/1` pure: channels are passed as assigns, not loaded inside the component.
- §6 lines 773-783 correctly identifies that `Layouts.app/1` needs no signature or flash changes; `lib/foyer_web/components/layouts.ex` lines 22-31 already renders only the slot plus `<.flash_group>`.
- §9.1 lines 987-1007 is honest that `Phoenix.LiveViewTest` cannot evaluate viewport media queries, so DOM-shape assertions are not visual breakpoint assertions.
- §10.1 lines 1127-1138 adds the right basic navigation semantics: a `<nav>` landmark, `aria-current="page"`, disabled off-shift controls, and a keyboard-focusable sign-out button.

## Critical Issues

### §5.5/§5.6 new announcement routes are specified after the catch-all show route

Bug: §5.5 says to add `live "/announcements/digest"` "after the existing `/announcements/:id` route" and §5.6 adds `live "/announcements/mine"` without correcting that order (lines 565-591). The current router has `live "/announcements/:id", AnnouncementLive, :show` before more specific announcement routes (lib/foyer_web/router.ex lines 41-43). If `/announcements/digest` or `/announcements/mine` are added after `/:id`, Phoenix will match them as `id = "digest"` or `id = "mine"` and route to `:show`, so the new LiveView actions will be unreachable.

Fix: if these routes remain in scope, insert all static announcement routes before `/:id`, and put `/:id/edit` after `/:id` only because it has an extra path segment.

```elixir
live "/announcements/new", AnnouncementLive, :new
live "/announcements/digest", AnnouncementLive, :weekly_digest
live "/announcements/mine", AnnouncementLive, :mine
live "/announcements/:id", AnnouncementLive, :show
live "/announcements/:id/edit", AnnouncementLive, :edit
```

### §5.5/§5.6 turn a desktop scaffold into new House feature work

Bug: §1 promises desktop-responsive layouts "without changing any mobile layout, routing, LiveView modules, schemas, or context functions" (lines 25-27), and §7.1 says all data required is already loaded by existing context functions (lines 789-792). But §5.5, §5.6, §7.2, and step 6 add two new routes, two new LiveView actions, two new House port callbacks, two context implementations, manager guards, render clauses, and tests (lines 558-599, 794-852, 1211-1222). That is not layout work. The justification also depends on desktop mocks, but `docs/feature-groups/scaffold/designs/` is empty in this workspace, so there is no file-backed evidence that these pages must be implemented in this scaffold pass.

Fix: remove `/announcements/digest`, `/announcements/mine`, `weekly_digest/1`, and `list_by_author/1` from this plan. Keep this plan to wrapping existing surfaces and components. If those pages are needed, create a separate House manager-surface plan with actual design artifacts, route ordering, authorization, query contracts, and tests.

```elixir
# Desktop scaffold: no new announcement routes.
live "/announcements/new", AnnouncementLive, :new
live "/announcements/:id", AnnouncementLive, :show
live "/announcements/:id/edit", AnnouncementLive, :edit
```

### §5.7/§8.4 chat master-detail does not load the inbox for direct room visits

Bug: §5.7 says the desktop inbox panel re-renders from a conversations stream "already loaded on `:inbox`" and says there are no `handle_params/3` changes (lines 650-656). That only works if the user first visits `/chat` and then navigates to `/chat/:id` in the same LiveView instance. A direct load, refresh, or shared link to `/chat/:conversation_id` starts with the current `ChatLive.mount/3` empty conversations stream and the current `:show` path only loads the conversation and messages (lib/foyer_web/live/chat_live.ex lines 20-28 and 43-45). §8.4 adds channels/on-shift IDs for `:show`, but still does not require loading `inbox_for/1` there (lines 929-940). The desktop layout would show an empty left panel on direct room loads.

Fix: make `:show` load the inbox stream as well as the room data. Keep it in `handle_params/3`, not `mount/3`.

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

### §9.2 staff redirect test contradicts the manager guard contract

Bug: §5.5 and §5.6 specify that non-managers redirect to `/house` with a flash (lines 572-577 and 594-599), and §9.1 says the desktop smoke test should assert those redirects (lines 1001-1002). The test skeleton instead expects `live/2` to return `{:ok, view, _html}` for staff and asserts rendered "Manager" text (lines 1092-1096). That test would either fail after the planned redirect is implemented, or push the executor toward rendering an in-page gate instead of the planned redirect.

Fix: if the new routes remain, make the test match the redirect contract and add equivalent coverage for `/announcements/mine`.

```elixir
test "weekly digest redirects staff to /house", ctx do
  conn = sign_in(ctx.conn, ctx.maya)

  assert {:error, {:live_redirect, %{to: "/house"}}} =
           live(conn, ~p"/announcements/digest")
end

test "my announcements redirects staff to /house", ctx do
  conn = sign_in(ctx.conn, ctx.maya)

  assert {:error, {:live_redirect, %{to: "/house"}}} =
           live(conn, ~p"/announcements/mine")
end
```

## Nits

- §4.1 lines 321-330 says channel links navigate to `/chat/:conversation_id` in the non-goals, but the HEEx skeleton uses `navigate={~p"/chat"}`. Either remove the claim or pass channel conversation IDs.
- §12.5 lines 1340-1352 overstates the CSRF uncertainty. `FoyerWeb.FoyerComponents` already uses `Phoenix.Component`, and `<.form action=... method="delete">` should generate the hidden method and CSRF fields; make this a compile/render check, not a planned manual token insertion unless the rendered form proves it is missing.
- §12.3 lines 1321-1323 says a collapsed rail variant exists in some Foyer mocks, but `docs/feature-groups/scaffold/designs/` contains no files in this workspace. Reword as an unvalidated risk unless those mocks are added.
- §8 lines 880-883 says changes are confined to render templates, then lists `mount/3` and `handle_params/3` changes. Tighten the summary so executors do not treat state changes as incidental.
- §11 step 14 lines 1289-1294 should include a 768 px or 820 px manual pass, not only 1280 px desktop and 375 px mobile, because the plan's highest-risk breakpoint is tablet-width `md:`.
