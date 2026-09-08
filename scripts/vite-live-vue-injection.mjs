import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import path from "node:path";

// LiveVue Hex 1.2.1 ships npm metadata 1.0.0. Its injected wrapper is recreated
// on shell updates, destroying canvas selection and unsaved synthesis. Keep one
// renderer per registration; unregistering still releases the editor normally.
// Transform only the verified upstream source because pnpm does not apply
// patchedDependencies to this local file:deps/live_vue directory dependency.
const originalHash = "d6342045737ebef60f5da91978f2a6b0a41080832323020902e0edb43d11609c";
const correctedHash = "a7026a00f38f9eccd6347795b7da2f92afe5ad5b4174b968762bcd21a47ab610";

const replacements = [
  [
    "type InjectorEntry = { targetId: string; slotName: string; component: any }",
    "type InjectorEntry = { targetId: string; slotName: string; renderSlot: SlotMap[string] }",
  ],
  [
    "if (entry) hookSlots[slotName] = renderInjectionSlot(injectorId, entry.component)",
    "if (entry) hookSlots[slotName] = entry.renderSlot",
  ],
  [
    "injectors.set(id, { targetId, slotName, component })",
    "injectors.set(id, { targetId, slotName, renderSlot: renderInjectionSlot(id, component) })",
  ],
];

export default function stableLiveVueInjection() {
  return {
    name: "storyarn-stable-live-vue-injection",
    enforce: "pre",
    transform(code, id) {
      const file = id.split("?")[0].replaceAll("\\", "/");
      if (!file.endsWith("/live_vue/assets/inject.ts")) return null;

      const manifest = JSON.parse(
        readFileSync(path.resolve(path.dirname(file), "../package.json"), "utf8"),
      );
      const normalized = code.replaceAll("\r\n", "\n");
      const hash = createHash("sha256").update(normalized).digest("hex");
      if (manifest.version !== "1.0.0" || ![originalHash, correctedHash].includes(hash)) {
        throw new Error(
          "LiveVue injection source changed. Review or remove scripts/vite-live-vue-injection.mjs " +
            "before upgrading LiveVue; this adapter only supports the verified Hex 1.2.1 source.",
        );
      }
      if (hash === correctedHash) return null;

      const corrected = replacements.reduce(
        (source, [before, after]) => source.replace(before, after),
        normalized,
      );
      return { code: corrected, map: null };
    },
  };
}
