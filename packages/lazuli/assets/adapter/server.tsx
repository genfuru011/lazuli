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

export const app = new Hono();
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

function escapeAttr(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll('"', "&quot;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

function hasUseHydrationDirective(src: string): boolean {
  const s = src.replace(/^\uFEFF/, "");
  return /^\s*(?:\/\*[\s\S]*?\*\/\s*)*(?:(?:\/\/[^\n]*\n)\s*)*(["'])use hydration\1\s*;?/.test(s);
}

async function renderFragment(appRoot: string, fragment: string, props: Record<string, unknown>) {
  const fragmentPath = join(appRoot, "app", `${fragment}.tsx`);

  let stat;
  try {
    stat = await Deno.stat(fragmentPath);
  } catch (e) {
    if (e instanceof Deno.errors.NotFound) {
      throw new LazuliHttpError(404, `Fragment not found: ${fragment}`);
    }
    throw e;
  }

  const mtime = stat.mtime?.getTime() ?? Date.now();
  const mod = await import(`${toFileUrl(fragmentPath).href}?t=${mtime}`);
  const Component = mod.default;
  if (!Component) {
    throw new LazuliHttpError(500, `Fragment component not found: ${fragment}`);
  }
  const rendered = html`${<Component {...props} />}`;
  return String(rendered);
}

const FRAGMENT_PATTERN = /^[a-zA-Z0-9_\-/]+$/;

class LazuliHttpError extends Error {
  status: number;

  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

function validateFragment(fragment: string): boolean {
  if (!fragment) return false;
  if (!FRAGMENT_PATTERN.test(fragment)) return false;
  if (fragment.includes("..")) return false;
  if (fragment.startsWith("/")) return false;
  return true;
}

function respondError(c: any, context: string, err: unknown) {
  const debug = Deno.env.get("LAZULI_DEBUG") === "1";
  const status = err instanceof LazuliHttpError ? err.status : 500;

  const message = err instanceof Error ? err.message : String(err);
  const body = status >= 500 && !debug ? "Internal Server Error" : message;

  const stack = debug && err instanceof Error && err.stack ? `\n\n${err.stack}` : "";
  return c.text(`${context} failed (${status}): ${body}${stack}`, status);
}

// RPC Endpoint: Render Turbo Streams (fragments)
app.post("/render_turbo_stream", async (c) => {
  const t0 = performance.now();
  try {
    const { streams } = await c.req.json();
    const appRoot = resolve(args["app-root"]);

    const parts: string[] = [];
    for (const s of (streams || []) as Array<any>) {
      const action = String(s.action || "");
      const target = s.target != null ? String(s.target) : "";
      const targets = s.targets != null ? String(s.targets) : "";

      if (!action) continue;
      if (!target && !targets) continue;

      const actionAttr = escapeAttr(action);
      const targetAttr = target ? escapeAttr(target) : "";
      const targetsAttr = targets ? escapeAttr(targets) : "";
      const selectorAttr = targetsAttr ? `targets="${targetsAttr}"` : `target="${targetAttr}"`;

      if (action === "remove") {
        parts.push(`<turbo-stream action="remove" ${selectorAttr}></turbo-stream>`);
        continue;
      }

      const fragment = String(s.fragment || "");
      if (!validateFragment(fragment)) {
        throw new LazuliHttpError(400, "Invalid fragment for turbo stream operation");
      }

      const props = (s.props || {}) as Record<string, unknown>;
      const inner = await renderFragment(appRoot, fragment, props);
      parts.push(`<turbo-stream action="${actionAttr}" ${selectorAttr}><template>${inner}</template></turbo-stream>`);
    }

    const dt = performance.now() - t0;
    return c.body(parts.join(""), 200, {
      "Content-Type": "text/vnd.turbo-stream.html; charset=utf-8",
      "Server-Timing": `deno_stream;dur=${dt.toFixed(1)}`
    });
  } catch (e) {
    console.error("Turbo Stream render error:", e);
    return respondError(c, "Turbo Stream render", e);
  }
});

// RPC Endpoint: Render a page
app.post("/render", async (c) => {
  const t0 = performance.now();
  try {
    const { page, props } = await c.req.json();
    const appRoot = resolve(args["app-root"]);

    // Construct absolute paths for dynamic imports
    const pagePath = join(appRoot, "app", "pages", `${page}.tsx`);
    const layoutPath = join(appRoot, "app", "layouts", "Application.tsx");

    let pageStat;
    let layoutStat;
    try {
      pageStat = await Deno.stat(pagePath);
    } catch (e) {
      if (e instanceof Deno.errors.NotFound) throw new LazuliHttpError(404, `Page not found: ${page}`);
      throw e;
    }
    try {
      layoutStat = await Deno.stat(layoutPath);
    } catch (e) {
      if (e instanceof Deno.errors.NotFound) throw new LazuliHttpError(500, "Layout not found: Application");
      throw e;
    }

    // Import modules (cache-busted for hot reload)
    const pageMtime = pageStat.mtime?.getTime() ?? Date.now();
    const layoutMtime = layoutStat.mtime?.getTime() ?? Date.now();
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

    const autoHydrate = hasUseHydrationDirective(await Deno.readTextFile(pagePath));

    const pageNode = autoHydrate
      ? (() => {
        const id = "page-island-" + Math.random().toString(36).slice(2);
        const propsScriptId = `${id}-props`;
        const jsonProps = JSON.stringify(props ?? {}).replace(/</g, "\\u003c");
        return (
          <>
            <div
              id={id}
              data-lazuli-island={`/assets/pages/${page}.tsx`}
              data-lazuli-props={propsScriptId}
            >
              <PageComponent {...props} />
            </div>
            <script
              id={propsScriptId}
              type="application/json"
              dangerouslySetInnerHTML={{ __html: jsonProps }}
            />
          </>
        );
      })()
      : <PageComponent {...props} />;

    // Render to string using Hono html helper
    const body = html`${
      <LayoutComponent>
        {pageNode}
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
    const islandsRuntimeScript = doc.includes("data-lazuli-island")
      ? `<script type="module">/* Lazuli Islands Hydration */
import { render } from "hono/jsx/dom";
import { jsx } from "hono/jsx";

async function hydrateOne(el){
  try {
    const path = el.getAttribute("data-lazuli-island") || "";
    const propsId = el.getAttribute("data-lazuli-props") || "";
    if (!path) return;

    const propsEl = propsId ? document.getElementById(propsId) : null;
    const raw = propsEl?.textContent || "{}";
    const props = JSON.parse(raw);

    const mod = await import(path);
    const Component = mod.default;
    if (!Component) return;
    render(jsx(Component, props), el);
  } catch (e) {
    console.error("Lazuli hydrate failed", e);
  }
}

for (const el of document.querySelectorAll("[data-lazuli-island]")) {
  hydrateOne(el);
}
</script>`
      : "";
    let injectedHtml = doc;

    if (doc.includes("</head>")) {
      injectedHtml = doc.replace("</head>", `${importMapScript}${turboScript}${islandsRuntimeScript}${reloadScript}</head>`);
    } else if (doc.includes("<head>")) {
      injectedHtml = doc.replace("<head>", `<head>${importMapScript}${turboScript}${islandsRuntimeScript}${reloadScript}`);
    } else {
      injectedHtml = `${importMapScript}${turboScript}${islandsRuntimeScript}${reloadScript}${doc}`;
    }

    const dt = performance.now() - t0;
    return c.body(injectedHtml, 200, {
      "Content-Type": "text/html; charset=utf-8",
      "Server-Timing": `deno_page;dur=${dt.toFixed(1)}`
    });
  } catch (e) {
    console.error("Render error:", e);
    return respondError(c, "Render", e);
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

export default app;

// Start the server
if (import.meta.main) {
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
}
