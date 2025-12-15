import { Hono } from "npm:hono@^4";
import { html } from "npm:hono@^4/html";
import { parseArgs } from "jsr:@std/cli@^0.224.0/parse-args";
import { join, toFileUrl, resolve, extname, dirname, fromFileUrl } from "jsr:@std/path@^0.224.0";
import { ensureDir } from "jsr:@std/fs@^0.224.0";
import * as esbuild from "https://deno.land/x/esbuild@v0.20.1/mod.js";

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

// Load user's deno.json
async function loadUserImports(appRoot: string) {
  try {
    const denoJsonPath = join(appRoot, "deno.json");
    const content = await Deno.readTextFile(denoJsonPath);
    const json = JSON.parse(content);
    return json.imports || {};
  } catch {
    return {};
  }
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

    // Render to string using Hono html helper
    const body = html`${
      <LayoutComponent>
        <PageComponent {...props} />
      </LayoutComponent>
    }`;

    // Generate Import Map from deno.json
    const userImports = await loadUserImports(appRoot);
    const importMap = {
      imports: {} as Record<string, string>
    };

    // Map each import to the vendor endpoint
    for (const [key, value] of Object.entries(userImports)) {
      if (key.startsWith("hono")) {
        // Map hono to esm.sh for browser
        if (key === "hono") {
          importMap.imports[key] = "https://esm.sh/hono@4?target=deno";
        } else if (key === "hono/") {
          importMap.imports[key] = "https://esm.sh/hono@4&target=deno/";
        } else {
          // e.g. hono/jsx -> https://esm.sh/hono@4/jsx?target=deno
          const subpath = key.replace("hono/", "");
          importMap.imports[key] = `https://esm.sh/hono@4/${subpath}?target=deno`;
        }
      } else if (key === "lazuli/island") {
        importMap.imports[key] = "/assets/components/Island.tsx";
      } else if (typeof value === "string" && value.startsWith("npm:")) {
        // Convert npm:package@version to https://esm.sh/package@version for browser
        const pkg = value.replace("npm:", "");
        importMap.imports[key] = `https://esm.sh/${pkg}`;
      } else {
        importMap.imports[key] = value as string;
      }
    }

    // Inject Import Map into HEAD
    const doc = `<!DOCTYPE html>${body}`;
    const importMapScript = `<script type="importmap">${JSON.stringify(importMap)}</script>`;
    
    // Simple injection: replace </head> with script + </head>
    // If no head, append to body (fallback)
    const injectedHtml = doc.replace("</head>", `${importMapScript}</head>`);

    return c.html(injectedHtml);
  } catch (e) {
    console.error("Render error:", e);
    return c.text(e.toString(), 500);
  }
});

// Vendor Asset Server
app.get("/assets/vendor/*", async (c) => {
  // With esm.sh, we don't need to serve vendor files manually.
  // The Import Map will point directly to esm.sh.
  return c.text("Not Found", 404);
});

// Asset Server
app.get("/assets/*", async (c) => {
  await initEsbuild();
  const path = c.req.path.replace("/assets/", "");
  const appRoot = resolve(args["app-root"]);
  let filePath = join(appRoot, "app", path);

  // Check if file exists in app root, otherwise fallback to Gem assets
  try {
    await Deno.stat(filePath);
  } catch {
    // Fallback to Gem assets
    // server.tsx is in packages/lazuli/assets/adapter/
    const adapterDir = dirname(fromFileUrl(import.meta.url));
    const gemAssetsDir = resolve(adapterDir, "..");
    filePath = join(gemAssetsDir, path);
  }

  try {
    const content = await Deno.readTextFile(filePath);
    
    // Transform TSX to JS, but DO NOT BUNDLE.
    // Leave imports as they are (bare specifiers).
    // The browser will resolve them using the Import Map.
    const result = await esbuild.transform(content, {
      loader: "tsx",
      format: "esm",
      target: "es2022",
      jsx: "automatic",
      jsxImportSource: "hono/jsx",
    });

    return c.body(result.code, 200, {
      "Content-Type": "application/javascript",
    });
  } catch (e) {
    console.error("Transform error:", e);
    return c.text(e.toString(), 500);
  }
});

// Start the server
if (args.socket) {
  // Unix Domain Socket
  try {
    await Deno.remove(args.socket);
  } catch (e) {
    if (!(e instanceof Deno.errors.NotFound)) {
      console.error(e);
    }
  }
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
