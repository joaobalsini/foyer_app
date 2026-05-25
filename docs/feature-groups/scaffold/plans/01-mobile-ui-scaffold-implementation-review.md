# Implementation Review — Plan 01 Mobile-first UI scaffold

## Verdict

**Approve with changes (now resolved).**

Codex's first pass returned **Revise** with two contained defects: dialyzer
contract violations on stubbed write functions, and zero-byte font placeholders.
Both were fixed in the same session before merge. The follow-up local gate run
is fully green, including `mix dialyzer`.

## Strengths

- Three `live_session` blocks (`:public`, `:authenticated_today`,
  `:authenticated_on_shift`) shipped exactly per plan §3 — off-shift gate is
  enforced at routing, not via `socket.view` introspection.
- Membership authorization baked into `Foyer.House.get_announcement!/2`
  (`lib/foyer/house.ex`) and `Foyer.Chat.get_conversation!/2`
  (`lib/foyer/chat.ex`); the unauthorized-access redirect path is covered by the
  smoke test.
- Smoke test stays `async: true` by owning its fixtures
  (`test/support/scaffold_fixtures.ex`) instead of relying on
  `priv/repo/seeds.exs`, and uses `set_mox_from_context` + `Mox.stub_with/2` to
  bind every port-mock to the real module.
- `Foyer.Today.Briefing` and `Foyer.Profile.Card` are real `defstruct` DTOs with
  `@type t` (typed_struct dependency was added at `mix.exs` and pulled in).
- daisyUI is fully ripped — `assets/vendor/daisyui*.js` deleted, `app.css`
  rewritten with the `.foyer-*` vocabulary on a warm-cream / forest-green / brass
  palette. `core_components.ex` keeps the `<.button>` / `<.input>` / `<.flash>`
  API per AGENTS.md.
- Every context exposes a `@behaviour Foyer.<Ctx>Port`; LiveViews call through
  `FoyerWeb.LiveDeps` (one accessor per context).

## Critical issues (resolved this session)

### 1. Dialyzer `invalid_contract` on three stubbed write functions

**Was:** `Foyer.Chat.send_message/3`, `Foyer.House.create_announcement/2`, and
`Foyer.Recognitions.give/2` each had `@spec ... :: {:ok, _} | {:error, _}` but
the body `raise`d, so dialyzer inferred `no_return()` and rejected the contract.
`docs/WORKFLOW.md` requires dialyzer to pass in the verify phase.

**Fix:** the three stubbed functions now return `{:error, :not_implemented}`;
the port `@callback`s widen the error union to
`Ecto.Changeset.t() | :not_implemented`; the LiveViews
(`chat_room_live.ex`, `house_live.ex`, `recognize_live.ex`) pattern-match on the
tuple instead of `rescue RuntimeError`. Dialyzer now reports 0 errors.

### 2. Zero-byte font placeholders at `priv/static/fonts/*.woff2`

**Was:** three empty `.woff2` files were committed under
`priv/static/fonts/` with a README explaining the placeholder. Empty woff2 files
are a footgun — they would silently fail font loading in production and the
fallback path is hidden inside the `@font-face src` chain.

**Fix:** the `@font-face` blocks have been removed from `assets/css/app.css`
along with the empty placeholder files. The `.foyer-serif` and `.foyer-mono`
classes now use their existing fallback stacks (`Georgia, serif` /
`ui-monospace, monospace`) directly. A comment in `app.css` documents that
bundling Instrument Serif + JetBrains Mono is owned by a follow-up branding
ticket.

## Plan-conformance audit

### A. Plan conformance

- ✓ Router three `live_session` blocks present — `lib/foyer_web/router.ex`
- ✓ `FoyerWeb.UserAuth` exposes `on_mount :mount_public`, `:ensure_authenticated`,
  `:ensure_on_shift`; no `socket.view` introspection —
  `lib/foyer_web/user_auth.ex`
- ✓ All 12 migrations present with named unique/check constraints (open-shift
  partial unique, channel-memberships unique, `bonus_points_non_negative`,
  `conversation_kind_channel_pair`, `direct_key` unique, pinned-feed partial
  index, etc.) — `priv/repo/migrations/`
- ✓ Membership authorization in reads — `lib/foyer/house.ex`,
  `lib/foyer/chat.ex`
- ✓ `Chat.inbox_for/1` uses `DISTINCT ON (conversation_id)` —
  `lib/foyer/chat.ex`
- ✓ DTOs `Foyer.Today.Briefing` and `Foyer.Profile.Card` exist with `@type t` —
  `lib/foyer/today/briefing.ex`, `lib/foyer/profile/card.ex`

### B. Phoenix v1.8 / LiveView 1.1 conformance

- ✓ Every LiveView template begins with `<Layouts.app flash={@flash}
  current_scope={@current_scope}>`
- ✓ `<.form for={@form}>` + `<.input>` used in compose, recognize, user picker
- ✓ `<.icon name="hero-...">` used for all icons; pilcrow placeholder replaced
- ✓ `<.link navigate={...}>` / `<.link patch={...}>` only; no
  `live_redirect`/`live_patch`
- ✓ DB loads in `handle_params/3`; `mount/3` only assigns defaults and subscribes
- ✓ Tailwind v4 `@source` imports preserved in `app.css`
- ✓ Chat room template uses `phx-update="stream"` on the message list

### C. Architecture rules

- ✓ All 8 contexts have port behaviours and `@behaviour` declarations
- ✓ `config/test.exs` points LiveDeps at mocks (`Foyer.AccountsMock`, etc.)
- ✓ LiveViews call through `FoyerWeb.LiveDeps`, never the concrete context
- ✓ No `Application.put_env/3` anywhere in `test/`
- ✓ `@spec` annotations on all public functions
- ✓ Off-shift gate enforced at routing (the three `live_session` blocks)

### D. Testing

- ✓ Smoke test runs `async: true` —
  `test/foyer_web/scaffold_smoke_test.exs`
- ✓ `setup :verify_on_exit!` and `set_mox_from_context` present in setup
- ✓ Exercises `start_shift`, `end_shift`, `acknowledge_announcement`
- ✓ Unauthorized-read assertion present (`leadership_only_announcement` from
  Maya's session)
- ✓ Bottom-nav assertions use stable IDs (`#bottom-nav-today`, etc.)
- ✓ Fixtures live in `test/support/scaffold_fixtures.ex`

### E. Verification gates (final state)

```
$ mix format --check-formatted    # pass (no output)
$ mix credo --strict              # 241 mods/funs, found no issues.
$ mix test                        # 23 tests, 0 failures
$ mix test test/foyer_web/scaffold_smoke_test.exs
                                  # 19 tests, 0 failures
$ mix dialyzer                    # Total errors: 0, Skipped: 0
$ mix precommit                   # 23 tests, 0 failures
```

## Assessment of implementer-flagged deviations

1. **Dialyzer warnings on stubbed writes** — original framing was "precommit
   passes, dialyzer is separate". Reviewer rejected per `docs/WORKFLOW.md`; fix
   applied in this session (return `{:error, :not_implemented}` instead of
   raising; port callbacks widened; LiveViews pattern-match). ✓ Accepted.
2. **Zero-byte font placeholders** — reviewer rejected. Fix applied in this
   session (removed `@font-face` block + empty files; system fallback stack is
   now the active path). ✓ Accepted.
3. **`{:error, {:live_redirect, _}}` vs `{:error, {:redirect, _}}` test assertion**
   — implementer is correct: `push_navigate/2` from inside `handle_params/3`
   produces `:live_redirect`, while on-mount redirects produce `:redirect`. The
   smoke test uses both correctly. ✓ Accepted.
4. **`"off the clock"` substring vs `"You're off the clock."`** — Phoenix HTML-
   escapes the apostrophe to `&#39;`; matching the un-apostrophe'd substring
   is the standard idiom for LiveView tests. ✓ Accepted.

## Loose ends for follow-up feature groups

- **Stubbed writes** — `Chat.send_message/3`, `House.create_announcement/2`,
  and `Recognitions.give/2` return `{:error, :not_implemented}` and the
  LiveViews surface a flash. The Chat, House, and Recognitions feature groups
  own implementing these. When implemented, drop `:not_implemented` from the
  port `@callback` union.
- **Fonts** — Instrument Serif + JetBrains Mono bundling is deferred. Add the
  woff2 files under `priv/static/fonts/` and reinstate the `@font-face` blocks
  in `app.css` as a follow-up branding ticket.
- **PubSub** — the scaffold subscribes to a per-conversation topic in
  `ChatRoomLive` but never broadcasts (writes are stubbed). The Chat feature
  group owns the broadcast wiring.
- **`mix phx.server` manual walk** (plan §13 step 20) — was not exercised in
  this session. Recommended before tagging the scaffold complete; verify each
  surface renders against the designs at `/tmp/foyer_design_extracts/`.
