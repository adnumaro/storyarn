#!/usr/bin/env node

import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, "..");
const libRoot = path.join(repoRoot, "lib", "storyarn_web");

const sourceExtensions = new Set([".ex", ".exs", ".heex"]);

async function listFiles(root) {
  const entries = await readdir(root, { withFileTypes: true });
  const files = [];

  for (const entry of entries) {
    const fullPath = path.join(root, entry.name);

    if (entry.isDirectory()) {
      files.push(...(await listFiles(fullPath)));
    } else if (sourceExtensions.has(path.extname(fullPath))) {
      files.push(fullPath);
    }
  }

  return files;
}

function normalizePath(filePath) {
  return filePath.split(path.sep).join("/");
}

function relativePath(filePath) {
  return normalizePath(path.relative(repoRoot, filePath));
}

function lineNumberAt(source, index) {
  return source.slice(0, index).split("\n").length;
}

const files = await listFiles(libRoot);
const failures = [];
const movedLayoutTargets = {
  auth: "AuthLayout",
  compare: "CompareLayout",
  docs: "DocsLayout",
  project: "ProjectLayout",
  public: "PublicLayout",
  settings: "SettingsLayout",
  workspace: "WorkspaceLayout",
};

for (const filePath of files) {
  const source = await readFile(filePath, "utf8");
  const rel = relativePath(filePath);

  for (const match of source.matchAll(/ProjectShell|project_shell/g)) {
    failures.push(
      `${rel}:${lineNumberAt(source, match.index ?? 0)} ProjectShell is deprecated; use ProjectLayout`,
    );
  }

  for (const match of source.matchAll(/<Layouts\.app\b/g)) {
    const location = `${rel}:${lineNumberAt(source, match.index ?? 0)}`;
    failures.push(`${location} Layouts.app has been removed; use a concrete layout boundary`);
  }

  for (const match of source.matchAll(/\bAppLayout\b/g)) {
    const location = `${rel}:${lineNumberAt(source, match.index ?? 0)}`;
    failures.push(`${location} AppLayout has been removed; use a concrete layout boundary`);
  }

  for (const match of source.matchAll(
    /\bLayouts\.(auth|compare|docs|project|public|settings|workspace)\b/g,
  )) {
    const layoutName = match[1];
    const location = `${rel}:${lineNumberAt(source, match.index ?? 0)}`;
    const targetLayout = movedLayoutTargets[layoutName];

    failures.push(`${location} Layouts.${layoutName} has moved to ${targetLayout}`);
  }

  if (rel === "lib/storyarn_web/components/layouts.ex") {
    for (const match of source.matchAll(
      /\bdefdelegate\s+(auth|compare|docs|project|public|settings|workspace)\s*\(/g,
    )) {
      const layoutName = match[1];
      const location = `${rel}:${lineNumberAt(source, match.index ?? 0)}`;
      const targetLayout = movedLayoutTargets[layoutName];

      failures.push(`${location} Layouts.${layoutName} delegate has moved to ${targetLayout}`);
    }
  }
}

if (failures.length > 0) {
  console.error(`Live layout verification failed with ${failures.length} issue(s):\n`);
  console.error(failures.join("\n"));
  process.exitCode = 1;
} else {
  console.log("Verified LiveView layout boundaries.");
}
