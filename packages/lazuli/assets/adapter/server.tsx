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
    // Create a virtual entry point that exports everything from the package
    const entryPoint = `export * from "${specifier}"; export { default } from "${specifier}";`;
    
    // Simple plugin to resolve npm: imports to esm.sh for browser
    const npmResolverPlugin = {
      name: 'npm-resolver',
      setup(build: any) {
        build.onResolve({ filter: /^npm:/ }, (args: any) => {
          const pkg = args.path.replace(/^npm:/, "");
          return { path: `https://esm.sh/${pkg}`, external: true };
        });
      },
    };

    const result = await esbuild.build({
      stdin: {
        contents: entryPoint,
        resolveDir: appRoot,
        loader: "ts",
      },
      bundle: true,
      write: false,
      format: "esm",
      platform: "browser",
      plugins: [npmResolverPlugin],
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
