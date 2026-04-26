import { describe, it, expect } from "vitest";
import { mount } from "@vue/test-utils";
import AssetPicker from "@components/assets/AssetPicker.vue";

interface AssetItem {
  id: number | string;
  filename: string;
  url?: string | null;
}

const ASSETS: AssetItem[] = [
  { id: 1, filename: "alpha.png", url: "/a.png" },
  { id: 2, filename: "beta.mp3", url: "/b.mp3" },
  { id: 3, filename: "gamma.png", url: "/g.png" },
];

// reka-ui's Popover/PopoverTrigger/PopoverContent rely on Teleport + portal-
// like rendering that doesn't survive a default stub. We override with
// passthrough stubs so the inner Command tree still renders inline and the
// CommandItem v-for is observable. We don't pass `shallow: true` because we
// want the Command primitives to render normally (they're plain Vue
// templates with default-slot rendering).
const passthrough = { template: "<div><slot /></div>" };

function mountIt(props: Record<string, unknown> = {}) {
  return mount(AssetPicker, {
    props: { kind: "image", assets: ASSETS, ...props },
    global: {
      stubs: {
        Popover: passthrough,
        PopoverTrigger: passthrough,
        PopoverContent: passthrough,
      },
    },
  });
}

describe("AssetPicker", () => {
  it("renders one CommandItem per asset with the asset filename as `value`", () => {
    const w = mountIt();
    const items = w.findAllComponents({ name: "CommandItem" });
    expect(items).toHaveLength(ASSETS.length);
    expect(items.map((i) => i.props("value"))).toEqual(ASSETS.map((a) => a.filename));
  });

  it("renders zero CommandItems when assets is []", () => {
    const w = mountIt({ assets: [] });
    expect(w.findAllComponents({ name: "CommandItem" })).toHaveLength(0);
  });

  it("emits select with the asset payload when a CommandItem fires @select", () => {
    const w = mountIt({ kind: "audio" });
    const items = w.findAllComponents({ name: "CommandItem" });
    items[1].vm.$emit("select");
    expect(w.emitted("select")).toBeDefined();
    expect(w.emitted("select")![0]).toEqual([ASSETS[1]]);
  });

  it("emits select even when selectedId is a string while asset.id is numeric", () => {
    const w = mountIt({ selectedId: "2" });
    const items = w.findAllComponents({ name: "CommandItem" });
    items[1].vm.$emit("select");
    expect(w.emitted("select")![0]).toEqual([ASSETS[1]]);
  });
});
