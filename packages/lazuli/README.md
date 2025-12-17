# Lazuli (Core)

Ruby for routing/thinking + Deno(Hono JSX) for rendering.

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

    return turbo_stream do |t|
      t.append "users_list", fragment: "components/UserRow", props: { user: user }
      t.update "flash", fragment: "components/FlashMessage", props: { message: "Added" }
    end if turbo_stream?

    redirect_to "/users" # defaults to 303 for non-GET
  end
end
```

Fragments live under your app root, e.g. `app/components/UserRow.tsx` and are referenced as `components/UserRow`.

`targets:` is supported for selector-based updates/removals.

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

