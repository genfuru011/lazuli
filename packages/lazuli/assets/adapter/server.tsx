import { Hono } from "hono";
import { renderToString } from "solid-js/web";
import { parseArgs } from "@std/cli/parse-args";
import { join, toFileUrl, resolve, extname, dirname } from "@std/path";
import { ensureDir } from "@std/fs";
import * as esbuild from "esbuild";
import { denoPlugins } from "esbuild-deno-loader";

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

    // Render to string using SolidJS
    const body = renderToString(() => (
      <LayoutComponent>
        <PageComponent {...props} />
      </LayoutComponent>
    ));

    // Generate Import Map from deno.json
    const userImports = await loadUserImports(appRoot);
    const importMap = {
      imports: {} as Record<string, string>
    };

    // Map each import to the vendor endpoint
    for (const key of Object.keys(userImports)) {
      importMap.imports[key] = `/assets/vendor/${key}`;
    }

    // Inject Import Map into HEAD
    const html = `<!DOCTYPE html>${body}`;
    const importMapScript = `<script type="importmap">${JSON.stringify(importMap)}</script>`;
    
    // Simple injection: replace </head> with script + </head>
    // If no head, append to body (fallback)
    const injectedHtml = html.replace("</head>", `${importMapScript}</head>`);

    return c.html(injectedHtml);
  } catch (e) {
    console.error("Render error:", e);
    return c.text(e.toString(), 500);
  }
});

// Vendor Asset Server
app.get("/assets/vendor/*", async (c) => {
  await initEsbuild();
  const pkgName = c.req.path.replace("/assets/vendor/", "");
  const appRoot = resolve(args["app-root"]);
  const userImports = await loadUserImports(appRoot);
  
  // Resolve package specifier from deno.json
  // e.g. "solid-js" -> "npm:solid-js@^1.8"
  const specifier = userImports[pkgName];

  if (!specifier) {
    return c.text(`Package not found in deno.json: ${pkgName}`, 404);
  }

  try {
    // Check if the module has a default export
    const mod = await import(specifier);
    const hasDefault = !!mod.default;

    // Create a virtual entry point that exports everything from the package
    // Use pkgName directly so esbuild resolves it via import map
    let entryPointContent = `export * from "${pkgName}";`;
    if (hasDefault) {
      entryPointContent += ` export { default } from "${pkgName}";`;
    }
    
    // Write entry point to a temporary file to avoid esbuild-deno-loader stdin issues
    const tmpDir = join(appRoot, "tmp", "vendor_build");
    await ensureDir(tmpDir);
    // Sanitize pkgName for filename
    const safeName = pkgName.replace(/\//g, "_");
    const entryPointPath = join(tmpDir, `${safeName}.ts`);
    await Deno.writeTextFile(entryPointPath, entryPointContent);

    // Custom plugin to handle exact match externals
    const externalPlugin = {
      name: 'external-plugin',
      setup(build: esbuild.PluginBuild) {
        const externals = Object.keys(userImports).filter(k => k !== pkgName);
        build.onResolve({ filter: /.*/ }, args => {
          if (externals.includes(args.path)) {
            return { path: args.path, external: true };
          }
        });
      },
    };

    const result = await esbuild.build({
      plugins: [
        externalPlugin,
        ...denoPlugins({
        loader: "native",
        importMapURL: toFileUrl(resolve(appRoot, "deno.json")).href,
      })],
      entryPoints: [entryPointPath],
      bundle: true,
      write: false,
      format: "esm",
      platform: "browser",
      // Externalize other vendor libs defined in deno.json
      // This ensures solid-js/web imports solid-js from /assets/vendor/solid-js
      external: [], // Handled by plugin
      jsx: "automatic",
    });

    return c.body(result.outputFiles[0].text, 200, {
      "Content-Type": "application/javascript",
    });
  } catch (e) {
    console.error("Vendor build error:", e);
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
    const result = await esbuild.build({
      plugins: [...denoPlugins({
        loader: "native",
        importMapURL: toFileUrl(resolve(appRoot, "deno.json")).href,
      })],
      entryPoints: [filePath],
      bundle: true,
      write: false,
      format: "esm",
      platform: "browser",
      // Externalize everything defined in user's deno.json
      // They will be resolved via Import Map to /assets/vendor/...
      external: Object.keys(await loadUserImports(appRoot)),
      jsx: "automatic",
      jsxImportSource: "solid-js",
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
