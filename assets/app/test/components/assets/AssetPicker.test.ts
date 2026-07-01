import { afterEach, describe, it, expect, vi } from "vitest";
import { mount } from "@vue/test-utils";
import AssetPicker from "../../../components/forms/assets/AssetPicker.vue";

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
const MANY_ASSETS: AssetItem[] = Array.from({ length: 120 }, (_, index) => ({
  id: index + 1,
  filename: `asset-${String(index + 1).padStart(3, "0")}.png`,
  url: `/asset-${index + 1}.png`,
}));
const MANY_ASSETS_WITH_ACCENTED_NAME: AssetItem[] = [
  ...MANY_ASSETS,
  { id: 121, filename: "café-scene.png", url: "/cafe-scene.png" },
];
const VERY_MANY_ASSETS: AssetItem[] = Array.from({ length: 1200 }, (_, index) => ({
  id: index + 1,
  filename: `asset-${String(index + 1).padStart(4, "0")}.png`,
  url: `/asset-${index + 1}.png`,
}));

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
  afterEach(() => {
    vi.useRealTimers();
  });

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

  it("truncates long filenames inside the command item row", () => {
    const longFilename =
      "sora_image_generation_remix_01km0deh04ei89912a1evvcrdz_with_extra_suffix.webp";
    const w = mountIt({
      assets: [{ id: "long", filename: longFilename, url: "/long.webp" }],
    });

    const item = w.findComponent({ name: "CommandItem" });
    expect(item.classes()).toContain("min-w-0");

    const filename = w.find("span.truncate");
    expect(filename.text()).toBe(longFilename);
    expect(filename.classes()).toEqual(expect.arrayContaining(["min-w-0", "flex-1", "truncate"]));
  });

  it("limits initial rendering for large asset lists", () => {
    const w = mountIt({ assets: MANY_ASSETS });

    const items = w.findAllComponents({ name: "CommandItem" });
    expect(items).toHaveLength(80);
    expect(items.map((i) => i.props("value"))).toEqual(
      MANY_ASSETS.slice(0, 80).map((asset) => asset.filename),
    );
    expect(w.text()).toContain("Showing 80 of 120 results");
  });

  it("keeps the initial page visible before the first remote response", async () => {
    const w = mountIt({ searchEvent: "picker_search" });

    await w.find("[data-slot='command-input']").setValue("shortcut-only");

    const items = w.findAllComponents({ name: "CommandItem" });
    expect(items).toHaveLength(ASSETS.length);
  });

  it("searches the full asset list before applying the render limit", async () => {
    const w = mountIt({ assets: MANY_ASSETS });

    await w.find("[data-slot='command-input']").setValue("asset-120");

    const items = w.findAllComponents({ name: "CommandItem" });
    expect(items.map((i) => i.props("value"))).toEqual(["asset-120.png"]);
    expect(w.text()).not.toContain("No results");
  });

  it("keeps accent-insensitive search when filtering before the render limit", async () => {
    const w = mountIt({ assets: MANY_ASSETS_WITH_ACCENTED_NAME });

    await w.find("[data-slot='command-input']").setValue("cafe");

    const items = w.findAllComponents({ name: "CommandItem" });
    expect(items.map((i) => i.props("value"))).toEqual(["café-scene.png"]);
    expect(w.text()).not.toContain("No results");
  });

  it("continues long searches asynchronously instead of blocking on the full list", async () => {
    vi.useFakeTimers();
    const w = mountIt({ assets: VERY_MANY_ASSETS });

    await w.find("[data-slot='command-input']").setValue("asset-1200");

    expect(w.findAllComponents({ name: "CommandItem" })).toHaveLength(0);
    expect(w.text()).toContain("Searching...");

    await vi.runAllTimersAsync();
    await w.vm.$nextTick();

    const items = w.findAllComponents({ name: "CommandItem" });
    expect(items.map((i) => i.props("value"))).toEqual(["asset-1200.png"]);
    expect(w.text()).not.toContain("Searching...");
  });
});
