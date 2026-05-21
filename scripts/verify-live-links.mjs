#!/usr/bin/env node

import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, "..");
const appRoot = path.join(repoRoot, "assets", "app");

const scanRoots = [
  path.join(appRoot, "components"),
  path.join(appRoot, "live"),
  path.join(appRoot, "modules"),
  path.join(appRoot, "shell"),
];

const allowedExternalSchemes = ["http://", "https://", "mailto:", "tel:", "blob:", "data:"];

async function listVueFiles(root) {
  const entries = await readdir(root, { withFileTypes: true });
  const files = [];

  for (const entry of entries) {
    const fullPath = path.join(root, entry.name);

    if (entry.isDirectory()) {
      files.push(...(await listVueFiles(fullPath)));
    } else if (entry.isFile() && entry.name.endsWith(".vue")) {
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

function attributeValue(tag, attributeName) {
  const pattern = new RegExp(`(?:^|\\s)${attributeName}\\s*=\\s*("[^"]*"|'[^']*'|[^\\s>]+)`);
  const match = tag.match(pattern);
  if (!match) return null;

  const rawValue = match[1];
  if (
    (rawValue.startsWith('"') && rawValue.endsWith('"')) ||
    (rawValue.startsWith("'") && rawValue.endsWith("'"))
  ) {
    return rawValue.slice(1, -1);
  }

  return rawValue;
}

function hasAttribute(tag, attributeName) {
  const pattern = new RegExp(`(?:^|\\s)${attributeName}(?:\\s|=|>|$)`);
  return pattern.test(tag);
}

function staticHref(tag) {
  return attributeValue(tag, "href");
}

function dynamicHref(tag) {
  return attributeValue(tag, ":href") ?? attributeValue(tag, "v-bind:href");
}

function isExternalOrAnchorHref(href) {
  return href.startsWith("#") || allowedExternalSchemes.some((scheme) => href.startsWith(scheme));
}

function isLiveLink(tag) {
  const hasPhxLink = hasAttribute(tag, "data-phx-link") || hasAttribute(tag, ":data-phx-link");
  const hasPhxLinkState =
    hasAttribute(tag, "data-phx-link-state") || hasAttribute(tag, ":data-phx-link-state");

  return hasPhxLink && hasPhxLinkState;
}

function isExempt(tag) {
  const reason = attributeValue(tag, "data-live-link-exempt");
  return typeof reason === "string" && reason.trim().length > 0;
}

function exemptionValue(tag) {
  return attributeValue(tag, "data-live-link-exempt") ?? "unspecified";
}

function anchorReason(tag) {
  if (isLiveLink(tag)) return null;
  if (isExempt(tag)) return null;

  const href = staticHref(tag);
  if (href && isExternalOrAnchorHref(href)) return null;

  const boundHref = dynamicHref(tag);
  if (boundHref) {
    return `dynamic href "${boundHref}" needs data-phx-link or data-live-link-exempt`;
  }

  if (href) {
    return `internal href "${href}" needs data-phx-link or data-live-link-exempt`;
  }

  return "anchor without href should be a button, LiveLink, or explicit exemption";
}

function formatLocation(filePath, line) {
  return `${normalizePath(path.relative(repoRoot, filePath))}:${line}`;
}

function findAnchors(source) {
  const anchors = [];
  const pattern = /<a\b[^>]*>/gs;

  for (const match of source.matchAll(pattern)) {
    anchors.push({
      tag: match[0],
      index: match.index ?? 0,
    });
  }

  return anchors;
}

const vueFiles = (await Promise.all(scanRoots.map((root) => listVueFiles(root)))).flat();
const failures = [];
const exemptions = [];

for (const filePath of vueFiles) {
  const source = await readFile(filePath, "utf8");

  for (const anchor of findAnchors(source)) {
    const line = lineNumberAt(source, anchor.index);
    const reason = anchorReason(anchor.tag);

    if (reason) {
      failures.push(`${formatLocation(filePath, line)} ${reason}`);
    } else if (isExempt(anchor.tag)) {
      exemptions.push(`${formatLocation(filePath, line)} ${exemptionValue(anchor.tag)}`);
    }
  }
}

if (failures.length > 0) {
  console.error(`Live link verification failed with ${failures.length} issue(s):\n`);
  console.error(failures.join("\n"));
  console.error(
    "\nInternal Vue links must use LiveLink, data-phx-link, or an explicit data-live-link-exempt reason.",
  );
  process.exitCode = 1;
} else {
  console.log(
    `Verified Vue live links in ${vueFiles.length} file(s). Explicit exemptions: ${exemptions.length}.`,
  );
}
