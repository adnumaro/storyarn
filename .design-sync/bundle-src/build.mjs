/**
 * Builds ds-bundle/ (repo root, untracked) for the Claude Design "Storyarn"
 * project. Off-script /design-sync shape: Vue components wrapped as React.
 *
 *   pnpm install --ignore-workspace   (once, in this directory)
 *   node build.mjs
 *
 * Steps: esbuild entry.ts (unplugin-vue, root node_modules for vue/reka-ui)
 * → @ds-bundle header from registry.json → Tailwind CLI for component
 * utilities → concat into _ds_bundle.css → per-component preview cards with
 * the compiled <Name>.jsx demo inlined → static styles/tokens/fonts/vendor.
 */
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { build, transform } from "esbuild";
import VuePlugin from "unplugin-vue/esbuild";
import { docs } from "./docs-data.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, "..", "..");
const outDir = path.join(repoRoot, "ds-bundle");
const tmpDir = path.join(here, ".build-tmp");

const registry = JSON.parse(fs.readFileSync(path.join(here, "registry.json"), "utf8"));
const NAMESPACE = registry.namespace;

fs.rmSync(tmpDir, { recursive: true, force: true });
fs.mkdirSync(tmpDir, { recursive: true });
// Clean rebuild: a removed or renamed component must not leave a stale
// card behind that the next upload would ship as current.
fs.rmSync(outDir, { recursive: true, force: true });
fs.mkdirSync(outDir, { recursive: true });

// ---- 1. Validate entry.ts registers exactly the registry.json components ----
const entrySource = fs.readFileSync(path.join(here, "entry.ts"), "utf8");
const registered = [...entrySource.matchAll(/register\(\s*"([^"]+)"/g)].map((m) => m[1]);
const declared = registry.components.map((c) => c.name);
const missing = declared.filter((n) => !registered.includes(n));
const extra = registered.filter((n) => !declared.includes(n));
if (missing.length || extra.length) {
  throw new Error(
    `registry.json/entry.ts mismatch. Missing in entry: [${missing}] — not in registry: [${extra}]`,
  );
}

// ---- 2. Bundle the components ----
const alias = Object.fromEntries(
  Object.entries({
    "@": "assets",
    "@app": "assets/app",
    "@components": "assets/app/components",
    "@shared": "assets/app/shared",
    "@modules": "assets/app/modules",
    "@shell": "assets/app/shell",
    "@plugins": "assets/app/plugins",
  }).map(([k, v]) => [k, path.join(repoRoot, v)]),
);

await build({
  entryPoints: [path.join(here, "entry.ts")],
  bundle: true,
  outfile: path.join(tmpDir, "bundle.js"),
  format: "iife",
  platform: "browser",
  target: "es2020",
  minify: true,
  alias,
  define: {
    "process.env.NODE_ENV": '"production"',
    __VUE_OPTIONS_API__: "true",
    __VUE_PROD_DEVTOOLS__: "false",
    __VUE_PROD_HYDRATION_MISMATCH_DETAILS__: "false",
  },
  plugins: [
    VuePlugin({
      template: {
        compilerOptions: { isCustomElement: (tag) => tag.startsWith("hex-") },
      },
    }),
  ],
  logLevel: "warning",
});

// ---- 3. @ds-bundle header ----
const sourceHashes = {};
for (const c of registry.components) {
  const src = fs.readFileSync(path.join(repoRoot, c.src));
  sourceHashes[c.name] = createHash("sha256").update(src).digest("hex").slice(0, 12);
}
const header = `/* @ds-bundle: ${JSON.stringify({
  format: 4,
  namespace: NAMESPACE,
  components: declared,
  sourceHashes,
  inlinedExternals: ["vue", "reka-ui", "vue-i18n", "@lucide/vue", "@vueuse/core"],
  unexposedExports: [],
})} */\n`;
const bundleJs = header + fs.readFileSync(path.join(tmpDir, "bundle.js"), "utf8");
fs.writeFileSync(path.join(outDir, "_ds_bundle.js"), bundleJs);

// ---- 4. Component CSS: Tailwind utilities + SFC styles ----
execFileSync(
  path.join(here, "node_modules", ".bin", "tailwindcss"),
  ["-i", "tailwind.css", "-o", path.join(tmpDir, "tw.css"), "--minify"],
  { cwd: here, stdio: "inherit" },
);
const sfcCssPath = path.join(tmpDir, "bundle.css");
const sfcCss = fs.existsSync(sfcCssPath) ? fs.readFileSync(sfcCssPath, "utf8") : "";
fs.writeFileSync(
  path.join(outDir, "_ds_bundle.css"),
  "/* Storyarn component CSS — Tailwind utilities scanned from the bundled\n" +
    "   components (theme mirrors assets/css/app.css) + SFC style blocks. */\n" +
    fs.readFileSync(path.join(tmpDir, "tw.css"), "utf8") +
    "\n" +
    sfcCss,
);

// ---- 5. Static files: styles.css, tokens, fonts, vendor React ----
for (const f of ["styles.css", "tokens/colors.css", "fonts/fonts.css"]) {
  const dest = path.join(outDir, f);
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.copyFileSync(path.join(here, "static", f), dest);
}
for (const f of fs.readdirSync(path.join(repoRoot, "assets", "fonts"))) {
  if (f.endsWith(".woff2")) {
    fs.copyFileSync(path.join(repoRoot, "assets", "fonts", f), path.join(outDir, "fonts", f));
  }
}
fs.mkdirSync(path.join(outDir, "_vendor"), { recursive: true });
for (const [pkg, file] of [
  ["react", "react.production.min.js"],
  ["react-dom", "react-dom.production.min.js"],
]) {
  fs.copyFileSync(
    path.join(here, "node_modules", pkg, "umd", file),
    path.join(outDir, "_vendor", file),
  );
}

// ---- 6. Foundations cards (hand-authored, kept verbatim) ----
for (const name of ["Chrome", "Colors", "Typography"]) {
  const dest = path.join(outDir, "components", "foundations", name);
  fs.mkdirSync(dest, { recursive: true });
  fs.copyFileSync(path.join(here, "cards", `${name}.html`), path.join(dest, `${name}.html`));
}

// ---- 7. Per-component cards: compile <Name>.jsx demo, inline into HTML ----
for (const c of registry.components) {
  const demoPath = path.join(here, "demos", `${c.name}.jsx`);
  if (!fs.existsSync(demoPath)) {
    throw new Error(
      `no demo for ${c.name} (demos/${c.name}.jsx) — every registry component ships a card`,
    );
  }
  const demoSrc = fs.readFileSync(demoPath, "utf8");
  const compiled = await transform(demoSrc, {
    loader: "jsx",
    jsxFactory: "React.createElement",
    jsxFragment: "React.Fragment",
    minify: false,
    target: "es2020",
  });
  const group = c.group.toLowerCase();
  const dest = path.join(outDir, "components", group, c.name);
  fs.mkdirSync(dest, { recursive: true });
  fs.copyFileSync(demoPath, path.join(dest, `${c.name}.jsx`));
  const doc = docs[c.name];
  if (!doc) throw new Error(`docs-data.mjs has no entry for ${c.name}`);
  fs.writeFileSync(path.join(dest, `${c.name}.d.ts`), doc.dts + "\n");
  fs.writeFileSync(path.join(dest, `${c.name}.prompt.md`), doc.prompt + "\n");
  const card = `<!-- @dsCard group="${c.group}" -->
<!doctype html><html class="dark"><head><meta charset="utf-8"><title>${c.name}</title>
<link rel="stylesheet" href="../../../styles.css">
<style>html,body{margin:0;min-height:100%}body{padding:20px}</style>
</head><body>
<div id="root"></div>
<script src="../../../_vendor/react.production.min.js"></script>
<script src="../../../_vendor/react-dom.production.min.js"></script>
<script src="../../../_ds_bundle.js"></script>
<script>
${compiled.code}
ReactDOM.createRoot(document.getElementById("root")).render(React.createElement(window.__dsDemo));
</script>
</body></html>
`;
  fs.writeFileSync(path.join(dest, `${c.name}.html`), card);
}

// ---- 8. README: conventions header + generated inventory ----
const conventions = fs.readFileSync(path.join(here, "..", "conventions.md"), "utf8");
const byGroup = new Map();
for (const c of registry.components) {
  if (!byGroup.has(c.group)) byGroup.set(c.group, []);
  byGroup.get(c.group).push(c.name);
}
let inventory = "\n---\n\n## Component index\n\n";
for (const [group, names] of byGroup) {
  inventory += `- **${group}**: ${names.join(", ")}\n`;
}
inventory += `\nAll components render from \`window.${NAMESPACE}.*\`. Per-component API and usage: \`components/<group>/<Name>/<Name>.d.ts\` and \`.prompt.md\`.\n`;
fs.writeFileSync(path.join(outDir, "README.md"), conventions + inventory);

fs.rmSync(tmpDir, { recursive: true, force: true });
const kb = (f) => Math.round(fs.statSync(path.join(outDir, f)).size / 1024);
console.log(
  `done: _ds_bundle.js ${kb("_ds_bundle.js")}KB, _ds_bundle.css ${kb("_ds_bundle.css")}KB, ${declared.length} components`,
);
