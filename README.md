# Foyer

Foyer is a Phoenix LiveView application for staff communication in luxury hotels.

The product brings back-of-house coordination into one place:

- **Today** - a phone-first briefing for the start of a shift: handoff notes, required acknowledgements, and overnight recognition.
- **The House** - the property-wide feed for manager announcements, pinned notices, receipts, and colleague recognition.
- **Chat** - direct and department conversations with membership-scoped access, unread state, read receipts, and clear off-shift markers.
- **Profile and people** - staff profiles, recognition history, language/role context, and the visible-but-not-yet-redeemable points program.

The POC uses a simple user picker instead of production authentication, so the app can demonstrate manager/staff permissions, shift boundaries, channel membership, announcements, acknowledgements, chat, recognition, and profile flows without a full identity provider.

## Quick Start

Recommended local setup uses Nix plus direnv:

```bash
direnv allow
bin/db start
mix setup
mix phx.server
```

Open <http://localhost:4000> and use the landing-page user picker to enter as a manager or staff member.

When you are done:

```bash
bin/db stop
```

## Screenshots

| Surface              | Mobile                                                                        | Desktop                                                                        |
| -------------------- | ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| Today briefing       | [Mobile](docs/screenshots/mobile/today.png)                                   | [Desktop](docs/screenshots/desktop/today.png)                                  |
| House feed           | [Mobile](docs/screenshots/mobile/house.png)                                   | [Desktop](docs/screenshots/desktop/house.png)                                  |
| Announcement compose | [Mobile](docs/screenshots/mobile/announcement-compose.png)                    | [Desktop](docs/screenshots/desktop/announcement-compose.png)                   |
| Announcement detail  | [Mobile](docs/screenshots/mobile/announcement-detail.png)                     | [Desktop](docs/screenshots/desktop/announcement-detail.png)                    |
| Recognition compose  | [Mobile](docs/screenshots/mobile/recognition-compose.png)                     | [Desktop](docs/screenshots/desktop/recognition-compose.png)                    |
| Recognition detail   | [Mobile](docs/screenshots/mobile/recognition-detail.png)                      | [Desktop](docs/screenshots/desktop/recognition-detail.png)                     |
| Chat index           | [Mobile](docs/screenshots/mobile/chat-index.png)                              | [Desktop](docs/screenshots/desktop/chat-index.png)                             |
| Chat                 | [Mobile](docs/screenshots/mobile/chat.png)                                    | [Desktop](docs/screenshots/desktop/chat.png)                                   |
| Profile              | [Mobile](docs/screenshots/mobile/profile.png)                                 | [Desktop](docs/screenshots/desktop/profile.png)                                |
| Shift handoff        | [Mobile](docs/screenshots/mobile/shift-handoff.png)                           | [Desktop](docs/screenshots/desktop/shift-handoff.png)                          |
| Off shift            | [Mobile](docs/screenshots/mobile/off-shift.png)                               | [Desktop](docs/screenshots/desktop/off-shift.png)                              |

## Documentation

Product and process:

- [docs/FOYER.md](docs/FOYER.md) - product north star, surfaces, v1 boundary, and operating model.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) - Phoenix/LiveView architecture, context boundaries, runtime config, and typing rules.
- [docs/WORKFLOW.md](docs/WORKFLOW.md) - spec -> plan -> execute -> verify workflow and feature-group documentation model.
- [docs/TESTING_GUIDE.md](docs/TESTING_GUIDE.md) - ExUnit, LiveView, Mox, scenario-module, and spec-clause testing conventions.
- [docs/CASE_STUDY.md](docs/CASE_STUDY.md) - case study narrative and how I worked with AI.

Contributor and agent rules:

- [CLAUDE.md](CLAUDE.md) - short project brief for AI agents and contributors.
- [AGENTS.md](AGENTS.md) - Phoenix, LiveView, Elixir, Ecto, Tailwind, and repository rules used by coding agents.

Feature specs live under [docs/feature-groups](docs/feature-groups):

- [Announcements](docs/feature-groups/announcements/spec.md)
- [Channels](docs/feature-groups/channels/spec.md)
- [Chat](docs/feature-groups/chat/spec.md)
- [Profile](docs/feature-groups/profile/spec.md)
- [Recognitions](docs/feature-groups/recognitions/spec.md)
- [Scaffold](docs/feature-groups/scaffold/spec.md)
- [Today](docs/feature-groups/today/spec.md)

Static visual references live in [designs](designs).

## Setup With Nix

Use the quick-start commands above for the happy path. To enter the Nix shell manually:

```bash
nix develop
```

The Nix shell provides Elixir, Erlang/OTP, Hex, Rebar, Node.js, PostgreSQL, and Git. It also keeps Mix, Hex, Rebar, and project Postgres state inside the repository so local development stays isolated.

Start the project-local database:

```bash
bin/db start
bin/db status
```

Then install dependencies, create/migrate/seed the database, build assets, and start Phoenix:

```bash
mix setup
mix phx.server
```

Open <http://localhost:4000> and pick a demo user.

Stop the local database when you are done:

```bash
bin/db stop
```

## Setup Without Nix

Install the versions from [.tool-versions](.tool-versions):

```text
elixir 1.19.0-otp-28
erlang 28.0
nodejs 22.11.0
postgres 17.0
```

You need PostgreSQL running locally or reachable through `DATABASE_URL` and `TEST_DATABASE_URL`.

Create local env overrides if needed:

```bash
cp .envrc.local.sample .envrc.local
```

If you use direnv without Nix, adjust `.envrc` or your shell so it does not call `use flake`, then export the values documented in [.envrc.local.sample](.envrc.local.sample). At minimum:

```bash
export DATABASE_URL="ecto://postgres:postgres@localhost:5432/foyer_dev"
export TEST_DATABASE_URL="ecto://postgres:postgres@localhost:5432/foyer_test"
export SECRET_KEY_BASE="$(mix phx.gen.secret)"
export PHX_HOST="localhost"
export PORT="4000"
```

Then run:

```bash
mix setup
mix phx.server
```

Open <http://localhost:4000> and pick a demo user.

## Environment

Runtime configuration is environment-variable driven:

- `DATABASE_URL` - development database.
- `TEST_DATABASE_URL` - test database; keep it separate from development.
- `SECRET_KEY_BASE` - Phoenix signing secret.
- `PHX_HOST` - host used by endpoint URL generation.
- `PORT` - HTTP port, defaulting to `4000`.

[.envrc](.envrc) provides safe development defaults. [.envrc.local.sample](.envrc.local.sample) documents per-developer overrides. `.envrc.local` is gitignored and is the right place for real local secrets.

## Daily Commands

```bash
mix phx.server                  # run the app
mix test                        # run tests, creating/migrating test DB first
mix test test/path/to_test.exs  # run one test file
mix format                      # format Elixir code
mix credo --strict              # static analysis
mix dialyzer                    # type analysis
mix precommit                   # compile, unused deps check, format, test
```

Use `mix precommit` before considering a change complete.

## Stack

| Tool             | Version        |
| ---------------- | -------------- |
| Elixir           | 1.19.0, OTP 28 |
| Erlang/OTP       | 28.0           |
| Phoenix          | 1.8.x          |
| Phoenix LiveView | 1.1.x          |
| PostgreSQL       | 17.0           |
| Node.js          | 22.11.0        |

The Nix toolchain is pinned in [flake.nix](flake.nix). The non-Nix toolchain is listed in [.tool-versions](.tool-versions) for `asdf`, `mise`, or equivalent version managers.

## Project Layout

```text
.
|-- assets/                  # Phoenix JS/CSS bundles
|-- bin/db                   # project-local PostgreSQL helper
|-- config/                  # compile-time and runtime config
|-- designs/                 # static visual references
|-- docs/                    # product, architecture, workflow, testing, specs
|-- lib/foyer/               # domain contexts and schemas
|-- lib/foyer_web/           # router, LiveViews, components, web concerns
|-- priv/repo/               # migrations and seeds
`-- test/                    # ExUnit, LiveView, and support modules
```
