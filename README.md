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
# Install Ruby dependencies
cd packages/example
bundle install
```

### Running the Application

You need to run both the Deno adapter and the Ruby server.

1.  **Start the Deno Adapter (SSR & Assets):**

    ```bash
    # From project root
    deno run -A --unstable-net --config packages/example/deno.json packages/lazuli/assets/adapter/server.tsx --app-root packages/example --socket packages/example/tmp/sockets/lazuli-renderer.sock
    ```

2.  **Start the Ruby Server:**

    ```bash
    # From packages/example
    bundle exec rackup -p 9292
    ```

3.  **Access the application:**
    Open `http://localhost:9292` in your browser.

## Lazuli CLI (開発用)

`cd packages/example` などアプリルートで以下を実行:

- サーバー起動（Ruby + Deno同時起動・簡易ホットリロード付き）  
  ```bash
  lazuli server --reload
  ```
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
