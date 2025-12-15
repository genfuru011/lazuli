import { Hono } from "hono";
import { renderToString } from "solid-js/web";
import { parseArgs } from "@std/cli/parse-args";
import { join, toFileUrl, resolve, extname } from "@std/path";
import * as esbuild from "esbuild";

// Hack to force SolidJS into server mode?
// Or mock DOM for h?
// @ts-ignore
globalThis.window = {};
// @ts-ignore
globalThis.document = {};
// @ts-ignore
globalThis.Element = class {};

// Parse command line arguments
const args = parseArgs(Deno.args, {
  string: ["socket", "app-root"],
  default: {
    "app-root": Deno.cwd(),
  },
});

// Initialize esbuild
let esbuildInitialized = false;
async function initEsbuild() {
  if (esbuildInitialized) return;
  await esbuild.initialize({
    worker: false,
  });
  esbuildInitialized = true;
}

const app = new Hono();

// RPC Endpoint: Render a page
app.post("/render", async (c) => {
  try {
    const { page, props } = await c.req.json();
    const appRoot = resolve(args["app-root"]);

    // Construct absolute paths for dynamic imports
    const pagePath = join(appRoot, "app", "pages", `${page}.tsx`);
    const layoutPath = join(appRoot, "app", "layouts", "Application.tsx");

    // Import modules
    const PageModule = await import(toFileUrl(pagePath).href);
    const LayoutModule = await import(toFileUrl(layoutPath).href);

    const PageComponent = PageModule.default;
    const LayoutComponent = LayoutModule.default;

    if (!PageComponent) {
      throw new Error(`Page component not found at ${pagePath}`);
    }
    if (!LayoutComponent) {
      throw new Error(`Layout component not found at ${layoutPath}`);
    }

    // Render to string using SolidJS
    const body = renderToString(() => (
      <LayoutComponent>
        <PageComponent {...props} />
      </LayoutComponent>
    ));

    return c.html(`<!DOCTYPE html>${body}`);
  } catch (e) {
    console.error("Render error:", e);
    return c.text(e.toString(), 500);
  }
});

// Asset Server
app.get("/assets/*", async (c) => {
  await initEsbuild();
  const path = c.req.path.replace("/assets/", "");
  const appRoot = resolve(args["app-root"]);
  // Map /assets/components/Counter.tsx -> app/components/Counter.tsx
  // Map /assets/pages/users/index.tsx -> app/pages/users/index.tsx
  const filePath = join(appRoot, "app", path);

  try {
    // Simple plugin to resolve npm: imports to esm.sh for browser
    const npmResolverPlugin = {
      name: 'npm-resolver',
      setup(build: any) {
        build.onResolve({ filter: /^npm:/ }, (args: any) => {
          const pkg = args.path.replace(/^npm:/, "");
          return { path: `https://esm.sh/${pkg}`, external: true };
        });
        
        // Handle bare specifiers for SolidJS
        build.onResolve({ filter: /^solid-js/ }, (args: any) => {
          return { path: `https://esm.sh/${args.path}`, external: true };
        });
      },
    };

    const result = await esbuild.build({
      entryPoints: [filePath],
      bundle: true,
      write: false,
      format: "esm",
      platform: "browser",
      plugins: [npmResolverPlugin],
      jsx: "automatic",
      jsxImportSource: "solid-js", // Use standard solid-js for browser
    });

    return c.body(result.outputFiles[0].text, 200, {
      "Content-Type": "application/javascript",
    });
  } catch (e) {
    console.error("Build error:", e);
    return c.text(e.toString(), 500);
  }
});

// Start the server
if (args.socket) {
  // Unix Domain Socket
  Deno.serve({
    path: args.socket,
    handler: app.fetch,
    onListen: ({ path }) => {
      console.log(`Lazuli Adapter listening on unix socket: ${path}`);
    }
  });
} else {
  // TCP Fallback (for testing)
  Deno.serve({
    port: 3000,
    handler: app.fetch,
    onListen: ({ port }) => {
      console.log(`Lazuli Adapter listening on http://localhost:${port}`);
    }
  });
}
