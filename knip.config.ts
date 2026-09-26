import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import type { KnipConfig } from "knip";

const repoRoot = process.cwd();
const appRoot = path.join(repoRoot, "assets", "app");

function listFiles(root: string, extensions: RegExp): string[] {
  return readdirSync(root, { withFileTypes: true }).flatMap((entry) => {
    const fullPath = path.join(root, entry.name);
    if (entry.isDirectory())
      return entry.name === "node_modules" ? [] : listFiles(fullPath, extensions);
    return extensions.test(entry.name) ? [fullPath] : [];
  });
}

// LiveVue mounts every page boundary from HEEx by string (`v-component="live/..."`), an edge no
// bundler graph can see. Resolve each string with LiveVue's own suffix rule (see
// scripts/verify-live-vue-components.mjs) and hand the files to Knip as production entries.
function liveVueEntries(): string[] {
  const components = listFiles(appRoot, /\.vue$/).map((file) =>
    path
      .relative(appRoot, file)
      .split(path.sep)
      .join("/")
      .replace(/\.vue$/, ""),
  );
  const names = listFiles(path.join(repoRoot, "lib"), /\.(ex|exs|heex)$/).flatMap((file) =>
    [...readFileSync(file, "utf8").matchAll(/v-component\s*=\s*(["'])([^"']+)\1/g)].map(
      (m) => m[2],
    ),
  );

  return [...new Set(names)].map((name) => {
    const requested = name.split("/").filter((part) => part !== "index");
    const matches = components.filter((component) => {
      const available = component.split("/");
      if (available.at(-1) === "index") available.pop();
      const offset = available.length - requested.length;
      return offset >= 0 && requested.every((part, i) => part === available[offset + i]);
    });
    if (matches.length !== 1) throw new Error(`knip: cannot resolve v-component "${name}"`);
    return `assets/app/${matches[0]}.vue!`;
  });
}

export default (): KnipConfig => ({
  entry: ["assets/js/app.js!", ...liveVueEntries()],
  project: ["assets/**/*.{vue,ts,js,mjs}!", "!assets/app/test/**!"],
  // A used-in-file export is an unnecessary keyword, not dead code.
  ignoreExportsUsedInFile: true,
  // Vendored shadcn-vue barrels re-export the full primitive surface.
  ignoreIssues: { "assets/app/components/ui/**": ["exports", "types"] },
  ignore: [
    // lezer-generator writes these next to parser-generated.js; nothing imports them.
    "assets/app/**/parser-generated.terms.js",
    // Vendored primitives kept for the settings and docs sidebars (ENG-264), which use them.
    "assets/app/components/ui/sheet/**",
    "assets/app/components/ui/scroll-area/**",
  ],
  // Loaded from assets/css/*.css (@import, @plugin, url()) or run as a CLI, which Knip does not trace.
  ignoreDependencies: [
    "tailwindcss",
    "@tailwindcss/typography",
    "tw-animate-css",
    "flag-icons",
    "shadcn-vue",
  ],
  tags: ["-lintignore"],
});
