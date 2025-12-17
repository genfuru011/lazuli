# Lazuli Example (e2e)

This app is the acceptance (e2e-ish) sample for Lazuli.

## Prerequisites

- Ruby + Bundler
- Deno

## Setup

```bash
cd packages/example
bundle install

# Create + migrate SQLite DB (db/development.sqlite3)
lazuli db create
```

## Run (dev)

```bash
cd packages/example
lazuli dev --reload
```

Open http://localhost:9292

## What to verify

### Turbo Drive

- Click `Home` / `Users` / `Todos`
- "Boot time" should stay the same across navigations
- `turbo:load count` should increase

### Turbo Streams

Go to `/users`:

- Create user: form submit should update the list without full reload
- Delete user: the row disappears via stream
- Delete all (DELETE /users): list clears via `targets` selector demo

### Islands hydration

Go to `/todos`:

- Add / toggle / delete should work client-side (component has `"use hydration"`)

### DB migrate

- `db/development.sqlite3` should exist
- `schema_migrations` table should include version `001`
- `users` table should exist
