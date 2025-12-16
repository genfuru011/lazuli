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
const reloadEnabled = Deno.env.get("LAZULI_RELOAD_ENABLED") === "1";
const reloadToken = Deno.env.get("LAZULI_RELOAD_TOKEN") ?? crypto.randomUUID?.() ?? `${Date.now()}`;

async function loadReloadToken(appRoot: string): Promise<string> {
  const tokenPath = Deno.env.get("LAZULI_RELOAD_TOKEN_PATH") ?? join(appRoot, "tmp", "lazuli_reload_token");
  try {
    return (await Deno.readTextFile(tokenPath)).trim();
  } catch {
    return reloadToken;
  }
}

function contentTypeFor(ext: string): string {
  switch (ext) {
    case ".js":
    case ".mjs":
    case ".ts":
    case ".tsx":
      return "application/javascript";
    case ".css":
      return "text/css";
    case ".json":
      return "application/json";
    case ".svg":
      return "image/svg+xml";
    case ".png":
      return "image/png";
    case ".jpg":
    case ".jpeg":
      return "image/jpeg";
    default:
      return "application/octet-stream";
  }
}

// RPC Endpoint: Render a page
app.post("/render", async (c) => {
  try {
    const { page, props } = await c.req.json();
    const appRoot = resolve(args["app-root"]);

    // Construct absolute paths for dynamic imports
    const pagePath = join(appRoot, "app", "pages", `${page}.tsx`);
    const layoutPath = join(appRoot, "app", "layouts", "Application.tsx");

    // Import modules (cache-busted for hot reload)
    const pageMtime = (await Deno.stat(pagePath)).mtime?.getTime() ?? Date.now();
    const layoutMtime = (await Deno.stat(layoutPath)).mtime?.getTime() ?? Date.now();
    const PageModule = await import(`${toFileUrl(pagePath).href}?t=${pageMtime}`);
    const LayoutModule = await import(`${toFileUrl(layoutPath).href}?t=${layoutMtime}`);

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
          importMap.imports[key] = "https://esm.sh/hono@4";
        } else if (key === "hono/") {
          importMap.imports[key] = "https://esm.sh/hono@4/";
        } else {
          // e.g. hono/jsx -> https://esm.sh/hono@4/jsx
          const subpath = key.replace("hono/", "");
          importMap.imports[key] = `https://esm.sh/hono@4/${subpath}`;
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
    importMap.imports["lazuli/island"] ||= "/assets/components/Island.tsx";

    // Inject Import Map into HEAD
    const doc = `<!DOCTYPE html>${body}`;
    const importMapScript = `<script type="importmap">${JSON.stringify(importMap)}</script>`;
    const currentToken = await loadReloadToken(appRoot);
    const reloadScript = reloadEnabled ? `<script type="module">(function(){const initial="${currentToken}";const es=new EventSource("/__lazuli/events");es.onmessage=(ev)=>{const token=String(ev.data||"");if(token&&token!==initial){location.reload();}};es.onerror=()=>{/* rely on EventSource auto-reconnect */};})();</script>` : "";
    const turboScript = `<script type="module">import "https://esm.sh/@hotwired/turbo@8";</script>`;
    let injectedHtml = doc;

    if (doc.includes("</head>")) {
      injectedHtml = doc.replace("</head>", `${importMapScript}${turboScript}${reloadScript}</head>`);
    } else if (doc.includes("<head>")) {
      injectedHtml = doc.replace("<head>", `<head>${importMapScript}${turboScript}${reloadScript}`);
    } else {
      injectedHtml = `${importMapScript}${turboScript}${reloadScript}${doc}`;
    }

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

// Reload endpoint (compat)
app.get("/__lazuli/reload", async (c) => {
  const appRoot = resolve(args["app-root"]);
  const token = await loadReloadToken(appRoot);
  return c.json({ token });
});

// Asset Server
app.get("/assets/*", async (c) => {
  const path = c.req.path.replace("/assets/", "");
  const appRoot = resolve(args["app-root"]);
  const primaryPath = join(appRoot, "app", path);
  let filePath = primaryPath;

  try {
    await Deno.stat(primaryPath);
  } catch {
    // Fallback to Gem assets
    const adapterDir = dirname(fromFileUrl(import.meta.url));
    const gemAssetsDir = resolve(adapterDir, "..");
    const fallbackPath = join(gemAssetsDir, path);
    try {
      await Deno.stat(fallbackPath);
      filePath = fallbackPath;
    } catch {
      return c.text("Not Found", 404);
    }
  }

  try {
    const ext = extname(filePath).toLowerCase();
    if (ext === ".ts" || ext === ".tsx") {
      await initEsbuild();
      const content = await Deno.readTextFile(filePath);

      // Transform TS/TSX to JS, but DO NOT BUNDLE.
      const result = await esbuild.transform(content, {
        loader: ext === ".tsx" ? "tsx" : "ts",
        format: "esm",
        target: "es2022",
        jsx: "automatic",
        jsxImportSource: "hono/jsx",
      });

      return c.body(result.code, 200, {
        "Content-Type": "application/javascript",
      });
    }

    const content = await Deno.readFile(filePath);
    return c.body(content, 200, {
      "Content-Type": contentTypeFor(ext),
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
    await ensureDir(dirname(args.socket));
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
