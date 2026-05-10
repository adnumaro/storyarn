#!/usr/bin/env node

import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, "..");
const appRoot = path.join(repoRoot, "assets", "app");
const libRoot = path.join(repoRoot, "lib");
const liveViewRoot = path.join(libRoot, "storyarn_web");
const testRoot = path.join(repoRoot, "test");

const sourceExtensions = new Set([".ex", ".exs", ".heex", ".leex"]);
const componentAttributePattern = /v-component\s*=\s*(["'])([^"']+)\1/g;
const liveVueTestPattern = /LiveVue\.Test\.get_vue\s*\([^)]*\bname:\s*(["'])([^"']+)\1/g;
const rootLiveBoundaryModules = new Set([
  "assets",
  "auth",
  "docs",
  "flows",
  "localization",
  "public",
  "scenes",
  "sheets",
]);
const privateModuleSegments = new Set([
  "canvas",
  "chrome",
  "collab",
  "components",
  "composables",
  "entities",
  "lib",
  "panels",
  "services",
  "toolbar",
]);
const publicGlobalComponentPatterns = [
  /^components\/LucideIcon$/,
  /^components\/versioning\/compare\/[^/]+$/,
];

async function listFiles(root, predicate) {
  const entries = await readdir(root, { withFileTypes: true });
  const files = [];

  for (const entry of entries) {
    const fullPath = path.join(root, entry.name);
    if (entry.isDirectory()) {
      if (entry.name === "node_modules" || entry.name === "_build") {
        continue;
      }
      files.push(...(await listFiles(fullPath, predicate)));
    } else if (predicate(fullPath)) {
      files.push(fullPath);
    }
  }

  return files;
}

function normalizePath(filePath) {
  return filePath.split(path.sep).join("/");
}

function lineNumberAt(source, index) {
  return source.slice(0, index).split("\n").length;
}

function rawComponentParts(componentPath) {
  return componentPath
    .replace(/\.vue$/, "")
    .split("/")
    .filter((part) => part.length > 0);
}

function requestedComponentParts(componentPath) {
  return rawComponentParts(componentPath).filter((part) => part !== "index");
}

function availableComponentParts(componentPath) {
  const parts = rawComponentParts(componentPath);

  if (parts.at(-1) === "index") {
    return parts.slice(0, -1);
  }

  return parts;
}

function suffixMatches(componentPath, requestedName) {
  const availableParts = availableComponentParts(componentPath);
  const requestedParts = requestedComponentParts(requestedName);

  if (requestedParts.length > availableParts.length) {
    return false;
  }

  return requestedParts.every((part, index) => {
    const availableIndex = availableParts.length - requestedParts.length + index;
    return part === availableParts[availableIndex];
  });
}

function publicBoundaryWarning(componentPath) {
  const parts = availableComponentParts(componentPath);
  const [root] = parts;

  if (root === "shell") {
    return null;
  }

  if (root === "live") {
    return null;
  }

  if (root === "modules") {
    const [, moduleName] = parts;

    if (rootLiveBoundaryModules.has(moduleName)) {
      return `module "${moduleName}" public boundaries must live under "assets/app/live/"`;
    }

    const privateSegment = parts.find(
      (part, index) => index > 1 && privateModuleSegments.has(part),
    );

    if (!privateSegment) {
      return null;
    }

    return `module private segment "${privateSegment}"`;
  }

  if (root === "components") {
    if (publicGlobalComponentPatterns.some((pattern) => pattern.test(componentPath))) {
      return null;
    }

    return "shared component rendered directly";
  }

  return `unsupported LiveVue root "${root ?? componentPath}"`;
}

async function discoverComponents() {
  const appComponents = await listFiles(appRoot, (filePath) => filePath.endsWith(".vue"));
  const libComponents = await listFiles(libRoot, (filePath) => filePath.endsWith(".vue"));

  return [...appComponents, ...libComponents].map((filePath) => {
    const root = filePath.startsWith(appRoot) ? appRoot : libRoot;
    return {
      filePath,
      componentPath: normalizePath(path.relative(root, filePath)).replace(/\.vue$/, ""),
    };
  });
}

async function discoverReferences() {
  const sourceFiles = await listFiles(liveViewRoot, (filePath) =>
    sourceExtensions.has(path.extname(filePath)),
  );
  const testFiles = await listFiles(testRoot, (filePath) =>
    sourceExtensions.has(path.extname(filePath)),
  );
  const references = [];

  for (const filePath of sourceFiles) {
    const source = await readFile(filePath, "utf8");
    for (const match of source.matchAll(componentAttributePattern)) {
      references.push({
        kind: "v-component",
        name: match[2],
        filePath,
        line: lineNumberAt(source, match.index ?? 0),
      });
    }
  }

  for (const filePath of testFiles) {
    const source = await readFile(filePath, "utf8");
    for (const match of source.matchAll(liveVueTestPattern)) {
      references.push({
        kind: "LiveVue.Test.get_vue",
        name: match[2],
        filePath,
        line: lineNumberAt(source, match.index ?? 0),
      });
    }
  }

  return references;
}

function formatLocation(reference) {
  return `${normalizePath(path.relative(repoRoot, reference.filePath))}:${reference.line} ${reference.kind}`;
}

const components = await discoverComponents();
const references = await discoverReferences();
const failures = [];
const warnings = [];

for (const reference of references) {
  const matches = components.filter((component) =>
    suffixMatches(component.componentPath, reference.name),
  );

  if (matches.length === 1) {
    if (reference.kind === "v-component") {
      const warning = publicBoundaryWarning(matches[0].componentPath);

      if (warning) {
        warnings.push(
          `${formatLocation(reference)} "${reference.name}" is not a public LiveVue boundary (${warning})`,
        );
      }
    }
    if (matches[0].componentPath !== reference.name) {
      failures.push(
        `${formatLocation(reference)} non-canonical component "${reference.name}" (use "${matches[0].componentPath}")`,
      );
    }
    continue;
  }

  if (matches.length === 0) {
    failures.push(`${formatLocation(reference)} missing component "${reference.name}"`);
  } else if (matches.length > 1) {
    failures.push(
      [
        `${formatLocation(reference)} ambiguous component "${reference.name}"`,
        ...matches.map((match) => `  - ${match.componentPath}`),
      ].join("\n"),
    );
  }
}

if (warnings.length > 0) {
  console.warn(`LiveVue public boundary warning(s) (${warnings.length}):\n`);
  console.warn(warnings.join("\n"));
  console.warn(
    "\nElixir should render shell/*, live/<domain>/<live-view>/<Boundary>, or an explicit global public boundary. Private Vue internals should be composed inside those boundaries.\n",
  );
}

if (failures.length > 0) {
  console.error(`LiveVue component verification failed with ${failures.length} issue(s):\n`);
  console.error(failures.join("\n\n"));
  process.exitCode = 1;
} else {
  console.log(
    `Verified ${references.length} LiveVue component reference(s) against ${components.length} Vue component(s).`,
  );
}
