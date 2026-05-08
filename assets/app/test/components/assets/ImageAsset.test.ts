import { describe, it, expect } from "vitest";
import { mount } from "@vue/test-utils";
import ImageAsset from "../../../components/forms/assets/ImageAsset.vue";

const ASSETS = [
  { id: 1, filename: "alpha.png", url: "/a.png" },
  { id: 2, filename: "beta.png", url: "/b.png" },
];

function mountIt(props: Record<string, unknown> = {}) {
  return mount(ImageAsset, {
    props: { imageAssets: ASSETS, canEdit: true, label: "Background", ...props },
    shallow: true,
  });
}

describe("ImageAsset", () => {
  it("forwards select from inner AssetPicker as its own select event", () => {
    const w = mountIt();
    const picker = w.findComponent({ name: "AssetPicker" });
    picker.vm.$emit("select", ASSETS[1]);
    expect(w.emitted("select")![0]).toEqual([ASSETS[1]]);
  });

  it("hides the clear button when no asset is selected", () => {
    const w = mountIt({ assetId: null });
    const buttons = w.findAllComponents({ name: "Button" });
    // No clear button should be present (it's gated on hasImage && canEdit).
    // The remaining buttons are upload + the picker trigger.
    const titles = buttons.map((b) => b.attributes("title")).filter(Boolean);
    expect(titles.some((t) => /clear/i.test(String(t)))).toBe(false);
  });

  it("emits clear when the clear button is clicked", async () => {
    const w = mountIt({ assetId: 1 });
    const clearBtn = w
      .findAllComponents({ name: "Button" })
      .find((b) => /clear/i.test(String(b.attributes("title"))));
    expect(clearBtn).toBeDefined();
    await clearBtn!.trigger("click");
    expect(w.emitted("clear")).toBeDefined();
  });

  it("renders the preview only when an asset is selected", () => {
    const noAsset = mountIt({ assetId: null });
    expect(noAsset.find("[style*='background-image']").exists()).toBe(false);

    const withAsset = mountIt({ assetId: 1 });
    const preview = withAsset.find("[style*='background-image']");
    expect(preview.exists()).toBe(true);
  });

  it("translates background-position dashes to spaces in preview style", () => {
    // jsdom canonicalises the CSS shorthand to horizontal-first, so
    // `top left` (vertical horizontal) round-trips as `left top`. Both are
    // valid; we assert on the canonical form.
    const w = mountIt({ assetId: 1, previewPosition: "top-left" });
    const preview = w.find("[style*='background-image']");
    expect(preview.attributes("style")).toContain("background-position: left top");
  });

  it("uses 100% 100% backgroundSize for fill mode, raw value otherwise", () => {
    const fill = mountIt({ assetId: 1, previewFit: "fill" });
    expect(fill.find("[style*='background-image']").attributes("style")).toContain(
      "background-size: 100% 100%",
    );

    const contain = mountIt({ assetId: 1, previewFit: "contain" });
    expect(contain.find("[style*='background-image']").attributes("style")).toContain(
      "background-size: contain",
    );
  });
});
