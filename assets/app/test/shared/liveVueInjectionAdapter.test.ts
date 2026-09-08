// @vitest-environment node
/// <reference types="node" />
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import stableLiveVueInjection from "../../../../scripts/vite-live-vue-injection.mjs";

// These hashes pin the reviewed LiveVue Hex 1.2.1 source and its corrected
// variant. A LiveVue upgrade must update them together with the adapter.
const originalHash = "d6342045737ebef60f5da91978f2a6b0a41080832323020902e0edb43d11609c";
const correctedHash = "a7026a00f38f9eccd6347795b7da2f92afe5ad5b4174b968762bcd21a47ab610";
const source = fileURLToPath(
  new URL("../../../../node_modules/live_vue/assets/inject.ts", import.meta.url),
);
const sha256 = (code: string) => createHash("sha256").update(code).digest("hex");
const plugin = stableLiveVueInjection();
const transform = (code: string, id = source) =>
  plugin.transform(code, id) as { code: string; map: null } | null;

describe("LiveVue injection adapter", () => {
  const upstream = readFileSync(source, "utf8").replaceAll("\r\n", "\n");
  it("rewrites only the verified upstream source into the reviewed variant", () => {
    expect(sha256(upstream)).toBe(originalHash);
    const corrected = transform(upstream);
    expect(corrected).not.toBeNull();
    expect(sha256(corrected!.code)).toBe(correctedHash);
    expect(corrected!.code).toContain("renderSlot: renderInjectionSlot(id, component)");
    expect(corrected!.code).not.toContain("renderInjectionSlot(injectorId, entry.component)");
    expect(transform(corrected!.code)).toBeNull();
  });
  it("leaves other modules alone and fails loudly when the upstream source drifts", () => {
    expect(transform(upstream, "/deps/live_vue/assets/hooks.ts")).toBeNull();
    expect(() => transform(`${upstream}\n// drift`)).toThrow(
      /Review or remove scripts\/vite-live-vue-injection\.mjs/,
    );
  });
});
