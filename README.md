# Lazuli

**Ruby for Thinking, Hono for Rendering.**

Lazuli is a Super Modern Monolith framework that fuses Ruby's expressiveness with Modern Web Standards (Deno/Hono) in a single architecture.

## Architecture

*   **Ruby (The Brain):** Handles application logic, data access (SQLite3), and routing.
*   **Deno (The View):** Handles SSR (Server-Side Rendering) using Hono JSX and asset serving.
*   **Communication:** Ruby and Deno communicate via Unix Domain Sockets (or TCP).
*   **Frontend:** "Zero Node Modules" architecture using Hono JSX and esm.sh. No complex bundlers required.

## Directory Structure

The project adopts a monorepo structure:

*   `packages/lazuli`: Core framework code (Ruby & Deno adapter).
*   `packages/example`: Example application using Lazuli.

## Getting Started

### Prerequisites

*   Ruby 3.2+
*   Deno 1.40+
*   Bundler

### Installation

```bash
cd packages/example
bundle install

# Create + migrate SQLite DB (db/development.sqlite3)
lazuli db create
```

### Running the Application (Development)

```bash
cd packages/example
lazuli dev --reload
```

Open `http://localhost:9292` in your browser.

See `packages/example/README.md` for the full e2e checklist (Turbo Drive / Streams / Islands hydration / DB migrate).

## Lazuli CLI (開発用)

`cd packages/example` などアプリルートで以下を実行:

- サーバー起動（Ruby + Deno同時起動・簡易ホットリロード付き）  
  ```bash
  lazuli dev --reload
  ```
- サーバー起動（Rackのみ。Deno renderer は別プロセスで起動）  
  ```bash
  lazuli server
  ```
- `bundle exec rackup` / `lazuli server` は Rack のみ起動します（Deno spawn はしない）。開発時は `lazuli dev --reload` が推奨です。
- リソース雛形生成  
  ```bash
  lazuli generate resource users
  ```
- プロジェクト作成  
  ```bash
  lazuli new my_app
  ```
- StructからTypeScript型生成  
  ```bash
  lazuli types
  ```

## Commit Strategy

We follow **Conventional Commits** to maintain a clean and readable history.

- **Format:** `<type>(<scope>): <subject>`
- **Types:**
  - `feat`: New features
  - `fix`: Bug fixes
  - `refactor`: Code changes that neither fix a bug nor add a feature
  - `docs`: Documentation changes
  - `chore`: Build process or auxiliary tool changes
  - `test`: Adding or correcting tests
