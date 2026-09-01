/**
 * Headless verification of every generated preview card in ds-bundle/.
 * Serves nothing itself — expects the bundle at http://localhost:8123
 * (python3 -m http.server 8123 -d ds-bundle). For each components/<g>/<Name>/
 * card: loads it, collects console errors and pageerrors, screenshots to
 * .verify/<Name>.png, and fails loudly on any error or on an empty #root.
 *
 * Usage: node verify.mjs [NameFilter]
 */
import { createRequire } from "node:module";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, "..", "..");
const require = createRequire(path.join(repoRoot, "package.json"));
const { chromium } = require("playwright");

const filter = process.argv[2];
const outDir = path.join(here, ".verify");
fs.mkdirSync(outDir, { recursive: true });

const cardsRoot = path.join(repoRoot, "ds-bundle", "components");
const cards = [];
for (const group of fs.readdirSync(cardsRoot)) {
  for (const name of fs.readdirSync(path.join(cardsRoot, group))) {
    if (filter && name !== filter) continue;
    cards.push({ group, name, url: `http://localhost:8123/components/${group}/${name}/${name}.html` });
  }
}

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 720, height: 480 } });
let failures = 0;

for (const card of cards) {
  const errors = [];
  const onConsole = (msg) => {
    if (msg.type() === "error") errors.push(`console: ${msg.text()}`);
  };
  const onPageError = (err) => errors.push(`pageerror: ${err.message}`);
  page.on("console", onConsole);
  page.on("pageerror", onPageError);

  await page.goto(card.url, { waitUntil: "networkidle" });
  await page.waitForTimeout(400);

  const rootInfo = await page.evaluate(() => {
    const root = document.getElementById("root");
    if (!root) return { kind: "foundations" };
    const rect = root.getBoundingClientRect();
    return {
      kind: "component",
      children: root.children.length,
      height: Math.round(rect.height),
      html: root.innerHTML.length,
    };
  });
  if (rootInfo.kind === "component" && (rootInfo.children === 0 || rootInfo.html < 40)) {
    errors.push(`empty render: #root has ${rootInfo.children} children, ${rootInfo.html} chars`);
  }

  await page.screenshot({ path: path.join(outDir, `${card.name}.png`) });
  page.off("console", onConsole);
  page.off("pageerror", onPageError);

  if (errors.length) {
    failures++;
    console.log(`FAIL ${card.group}/${card.name}`);
    for (const e of errors) console.log(`   ${e}`);
  } else {
    const extent = rootInfo.kind === "component" ? ` (${rootInfo.height}px)` : "";
    console.log(`ok   ${card.group}/${card.name}${extent}`);
  }
}

await browser.close();
console.log(failures ? `\n${failures} card(s) failed` : "\nall cards clean");
process.exit(failures ? 1 : 0);
