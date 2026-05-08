#!/usr/bin/env node

import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, "..");
const appRoot = path.join(repoRoot, "assets", "app");
const libRoot = path.join(repoRoot, "lib");
const liveViewRoot = path.join(libRoot, "storyarn_web");

const sourceExtensions = new Set([".ex", ".heex", ".leex"]);
const componentAttributePattern = /v-component\s*=\s*(["'])([^"']+)\1/g;

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

function componentParts(componentPath) {
  return componentPath
    .replace(/\.vue$/, "")
    .split("/")
    .filter((part) => part !== "index" && part.length > 0);
}

function suffixMatches(componentPath, requestedName) {
  const availableParts = componentParts(componentPath);
  const requestedParts = componentParts(requestedName);

  if (requestedParts.length > availableParts.length) {
    return false;
  }

  return requestedParts.every((part, index) => {
    const availableIndex = availableParts.length - requestedParts.length + index;
    return part === availableParts[availableIndex];
  });
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
  const references = [];

  for (const filePath of sourceFiles) {
    const source = await readFile(filePath, "utf8");
    for (const match of source.matchAll(componentAttributePattern)) {
      references.push({
        name: match[2],
        filePath,
        line: lineNumberAt(source, match.index ?? 0),
      });
    }
  }

  return references;
}

function formatLocation(reference) {
  return `${normalizePath(path.relative(repoRoot, reference.filePath))}:${reference.line}`;
}

const components = await discoverComponents();
const references = await discoverReferences();
const failures = [];

for (const reference of references) {
  const matches = components.filter((component) =>
    suffixMatches(component.componentPath, reference.name),
  );

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

if (failures.length > 0) {
  console.error(`LiveVue component verification failed with ${failures.length} issue(s):\n`);
  console.error(failures.join("\n\n"));
  process.exitCode = 1;
} else {
  console.log(
    `Verified ${references.length} LiveVue component reference(s) against ${components.length} Vue component(s).`,
  );
}
