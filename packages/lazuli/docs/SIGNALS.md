# Signals (proposed)

This document describes a proposed small, dependency-light “Signals + JSX” client-side pattern that fits Lazuli’s goals:

- **HTML First / Server is source of truth** (DB is truth, server HTML is canonical)
- **Islands are small** (client interactivity is scoped, not SPA)
- **Minimal DX overhead** (no user-authored hooks required)
- **Web-standards friendly** (Hono `hono/jsx/dom` is the JSX runtime)

The intent is to enable **instant UI feedback** (optimistic UI) while keeping correctness by **syncing back to server-rendered HTML** and rolling back on failure.

---

## 1. Motivation: “Signals-like” in Lazuli

The mental model:

1. User interacts → UI should update immediately (optimistic).
2. Client sends a request (POST/fetch).
3. If the request succeeds → UI converges to the **server’s canonical HTML** (Turbo Stream/HTML fragment).
4. If it fails → UI rolls back to the previous state, and an error is shown.

Signals-style state helps because:

- State reads implicitly track dependencies (no manual subscriptions).
- Updates are immediate and predictable.
- A tiny API surface is enough for small islands.

---

## 2. Non-goals

- Building a full SPA framework.
- Replacing Turbo Drive/Streams.
- Global app-wide state shared across requests.

This is specifically for **small islands**.

---

## 3. Proposed API surface

### 3.1 Core

Solid-like syntax (familiar and hook-free):

```ts
const [count, setCount] = createSignal(0);
count();        // read
setCount(1);    // write
setCount(c => c + 1); // functional update
```

Minimum primitives:

- `createSignal<T>(initial: T): [() => T, (next: T | ((prev: T) => T)) => void]`
- `createEffect(fn: () => void): () => void` (returns `dispose`)
- `createMemo<T>(fn: () => T): () => T`
- `batch(fn: () => void): void` (coalesce multiple updates)
- `untrack<T>(fn: () => T): T` (optional, avoid dependency tracking)

### 3.2 DOM / JSX integration

To keep user code hook-free, we provide a single entrypoint that re-runs a view function when its dependencies change.

```ts
render(root, View, { strategy: "replace" | "morph" });
```

- `strategy: "replace"` → simplest: `root.replaceChildren(view())`
- `strategy: "morph"` → optional: morphdom-style diffing to preserve existing nodes/listeners

The view function returns **Hono JSX DOM nodes** (`hono/jsx/dom`).

---

## 4. Usage examples (user-facing)

### 4.1 Minimal counter

```ts
import { createSignal } from "tiny-signals";
import { render } from "tiny-signals/dom";
import { jsx } from "hono/jsx/dom";

const [count, setCount] = createSignal(0);

const App = () => (
  <div>
    <button onclick={() => setCount(c => c + 1)}>+</button>
    <span>{count()}</span>
  </div>
);

render(document.querySelector("#app")!, App);
```

### 4.2 Choosing rendering strategy

Same JSX, switch strategy:

```ts
render(root, App, { strategy: "replace" }); // smallest
render(root, App, { strategy: "morph" });   // better for larger DOM
```

### 4.3 Optimistic UI (rollback on failure)

We want the simplest user mental model:

- `apply()` mutates local UI state immediately
- `commit()` performs the request
- `rollback()` reverts local state if `commit()` fails

```ts
import { createSignal } from "tiny-signals";
import { render, optimistic } from "tiny-signals/dom";
import { jsx } from "hono/jsx/dom";

const [done, setDone] = createSignal(false);
const [error, setError] = createSignal<string | null>(null);

async function toggle() {
  setError(null);

  await optimistic({
    apply: () => setDone(d => !d),
    rollback: () => setDone(d => !d),
    commit: async () => {
      const res = await fetch("/todos/1/toggle", { method: "POST" });
      if (!res.ok) throw new Error(await res.text());
    },
    onError: (e) => setError(String(e))
  });
}

const App = () => (
  <div>
    <button onclick={toggle}>{done() ? "done" : "todo"}</button>
    {error() && <p class="error">{error()}</p>}
  </div>
);

render(document.querySelector("#app")!, App, { strategy: "morph" });
```

---

## 5. “Server is truth”: syncing back to canonical HTML

Optimistic UI is only half the story.

To preserve Lazuli’s **DB/Server as truth**, on success we should converge to server HTML, not just trust the client mutation.

### 5.1 With Turbo Streams (recommended)

- Client performs `fetch` with `Accept: text/vnd.turbo-stream.html`.
- Server responds with Turbo Stream operations.
- Turbo applies DOM updates, making the UI canonical.

Client responsibilities:

- Optimistically update (optional).
- On success, do **nothing** (Turbo’s response updates DOM).
- On failure, rollback.

### 5.2 Without Turbo Streams: HTML fragment + morph

If the server returns an HTML fragment for a slot/partial, we can morph it in:

```ts
await optimistic({
  apply: ...,
  rollback: ...,
  commit: async () => {
    const res = await fetch("/todos/1/toggle", {
      method: "POST",
      headers: { Accept: "text/html" }
    });
    if (!res.ok) throw new Error(await res.text());

    const html = await res.text();
    morph(slotEl, html); // implementation detail: HTML -> Node -> morph
  }
});
```

---

## 6. Island scoping rules (to avoid common bugs)

1. **Never create signals in module top-level for server-rendered apps.**
   - Create signals inside the island `mount()` so they are per-instance.
2. Prefer **slot-level rendering**.
   - Re-render/morph only the minimal subtree.
3. Provide `dispose()`.
   - Effects/listeners must be cleaned up when islands are replaced.
4. Decide how to handle concurrency.
   - For small apps: disable re-entry while `commit()` pending.
   - For complex apps: add a `tx` id (Action queue / reducer approach).

---

## 7. Implementation sketch (internal)

This is a sketch to clarify expected behavior.

- `createSignal` holds:
  - `value`
  - `subscribers: Set<Effect>`
- Dependency tracking:
  - A global `currentEffect` pointer while executing `createEffect`.
  - `signal.read()` registers `currentEffect` as subscriber.
  - `signal.write()` schedules subscribers.
- Scheduling:
  - `batch(fn)` queues notifications and flushes once.

DOM integration:

- `render(root, view)` registers an effect that re-evaluates `view()`.
- Strategy:
  - `replace`: `root.replaceChildren(node)`
  - `morph`: `morphdom(root, node)`

---

## 8. When to choose what

- **Smallest islands** → `render(..., { strategy: "replace" })`
- **Bigger DOM / preserve focus** → `render(..., { strategy: "morph" })`
- **Server-canonical updates** → Turbo Streams first, morph as fallback

---

## 9. Open questions

- Naming: `createSignal/createEffect` (Solid-like) vs `signal/effect` (Preact-like).
- Should `render()` return `{ dispose }`?
- How much to standardize around Turbo Streams vs generic HTML fragments?
