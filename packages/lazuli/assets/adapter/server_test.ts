import { assertEquals, assertStringIncludes } from "jsr:@std/assert@^0.224.0";

async function startServer() {
  const app = await import("./server.tsx");
  const server = Deno.serve({ hostname: "127.0.0.1", port: 0 }, app.default.fetch);
  const addr = server.addr as Deno.NetAddr;
  const baseUrl = `http://127.0.0.1:${addr.port}`;
  return { server, baseUrl };
}

Deno.test("render_turbo_stream rejects invalid fragment", async () => {
  const { server, baseUrl } = await startServer();
  try {
    const res = await fetch(`${baseUrl}/render_turbo_stream`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        streams: [{ action: "append", target: "x", fragment: "../secrets", props: {} }],
      }),
    });
    assertEquals(res.status, 400);
    await res.text();
  } finally {
    await server.shutdown();
  }
});

Deno.test("render_turbo_stream supports targets for remove", async () => {
  const { server, baseUrl } = await startServer();
  try {
    const res = await fetch(`${baseUrl}/render_turbo_stream`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        streams: [{ action: "remove", targets: "#users_list li" }],
      }),
    });

    assertEquals(res.status, 200);
    assertStringIncludes(await res.text(), 'targets="#users_list li"');
  } finally {
    await server.shutdown();
  }
});
