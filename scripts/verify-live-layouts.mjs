#!/usr/bin/env node

import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, "..");
const libRoot = path.join(repoRoot, "lib", "storyarn_web");

const sourceExtensions = new Set([".ex", ".exs", ".heex"]);
const allowedLayoutsAppFiles = new Set([
  "lib/storyarn_web/live/project_live/trash.ex",
  "lib/storyarn_web/live/workspace_live/new.ex",
]);

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
const allowedLegacyLayoutsApp = [];

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

    if (allowedLayoutsAppFiles.has(rel)) {
      allowedLegacyLayoutsApp.push(location);
    } else {
      failures.push(`${location} Layouts.app is deprecated for LiveView pages`);
    }
  }

  for (const match of source.matchAll(/\bLayouts\.(auth|docs|settings|public)\b/g)) {
    const layoutName = match[1];
    const location = `${rel}:${lineNumberAt(source, match.index ?? 0)}`;
    const targetLayout =
      layoutName === "auth"
        ? "AuthLayout"
        : layoutName === "docs"
          ? "DocsLayout"
          : layoutName === "settings"
            ? "SettingsLayout"
            : "PublicLayout";

    failures.push(`${location} Layouts.${layoutName} has moved to ${targetLayout}`);
  }
}

if (failures.length > 0) {
  console.error(`Live layout verification failed with ${failures.length} issue(s):\n`);
  console.error(failures.join("\n"));
  process.exitCode = 1;
} else {
  const suffix =
    allowedLegacyLayoutsApp.length > 0
      ? ` Legacy Layouts.app allowlist: ${allowedLegacyLayoutsApp.length}.`
      : "";

  console.log(`Verified LiveView layout boundaries.${suffix}`);
}
