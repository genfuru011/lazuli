# Lazuli (Core)

Ruby for routing/thinking + Deno(Hono JSX) for rendering.

## Process model

- `lazuli dev`: starts **Rack + Deno** via `Lazuli::ServerRunner` (use `--reload` for development)
- `lazuli server`: starts **Rack only** (expects a separately-managed Deno renderer)
- `bundle exec rackup`: starts **Rack only** (the Deno renderer must be started separately)

### Starting the Deno renderer (rack-only mode)

```sh
deno run -A --unstable-net --config ./deno.json \
  "$(bundle show lazuli)/assets/adapter/server.tsx" \
  --app-root "$(pwd)" \
  --socket "$(pwd)/tmp/sockets/lazuli-renderer.sock"
```

## Turbo

Lazuli loads Turbo (`@hotwired/turbo`) so **Turbo Drive** works out of the box.

### Turbo Frames

Frames are intentionally **framework-light**: users can write `<turbo-frame id="...">` in their TSX and return normal HTML.

### Turbo Streams (HTML is rendered in Deno)

Ruby builds stream operations; Deno renders the `<template>` HTML via JSX fragments.

```rb
class UsersResource < Lazuli::Resource
  def create
    user = UserRepository.create(name: params[:name])

    stream_or(redirect_to("/users")) do |t|
      t.append "users_list", "components/UserRow", user: user
      t.update "flash", "components/FlashMessage", message: "Added"
    end
  end
end
```

Fragments live under your app root, e.g. `app/components/UserRow.tsx` and are referenced as `components/UserRow`.

`targets:` is supported for selector-based updates/removals.

Shorthand: if the first argument starts with a CSS selector prefix (`#`, `.`, `[`), Lazuli treats it as `targets:`.

```rb
stream do |t|
  t.remove "#users_list li"         # => targets: "#users_list li"
  t.update "#flash", "components/Flash", message: "hi"
end
```

## RPC (experimental)

Define an allowlisted JSON RPC method on a Resource:

```rb
class UsersResource < Lazuli::Resource
  rpc :rpc_index, returns: [User]

  def rpc_index
    UserRepository.all
  end
end
```

Run `lazuli types` to generate:
- `client.d.ts` (includes `RpcRequests`/`RpcResponses`)
- `client.rpc.ts` and `app/client.rpc.ts` (typed `fetch` helper)

In an Island/hydrated component:

```ts
import { rpc } from "/assets/client.rpc.ts";
const users = await rpc("UsersResource#rpc_index", undefined);
```

