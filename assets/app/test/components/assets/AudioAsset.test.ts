import { describe, it, expect, beforeAll, vi } from "vitest";
import { mount } from "@vue/test-utils";
import AudioAsset from "../../../components/forms/assets/AudioAsset.vue";

beforeAll(() => {
  // jsdom doesn't provide a working Audio constructor — stub it so AudioAsset
  // can be mounted without the watcher exploding when an asset has a url.
  // We don't exercise playback here; only the upload/select/volume contracts.
  vi.stubGlobal(
    "Audio",
    class {
      volume = 1;
      addEventListener() {}
      removeEventListener() {}
      pause() {}
      play() {
        return Promise.resolve();
      }
    },
  );
});

const ASSETS = [
  { id: 1, filename: "alpha.mp3", url: "/a.mp3" },
  { id: 2, filename: "beta.mp3", url: "/b.mp3" },
];

const triggerSlotStub = {
  name: "AssetPicker",
  template: '<div data-test="asset-picker-stub"><slot name="trigger" /></div>',
};

const buttonStub = {
  name: "Button",
  props: ["disabled"],
  template: "<button :disabled='disabled'><slot /></button>",
};

function mountIt(props: Record<string, unknown> = {}) {
  return mount(AudioAsset, {
    props: { audioAssets: ASSETS, canEdit: true, label: "Music", ...props },
    shallow: true,
  });
}

function mountWithTrigger(props: Record<string, unknown> = {}) {
  return mount(AudioAsset, {
    props: { audioAssets: ASSETS, canEdit: true, label: "Music", ...props },
    global: {
      stubs: {
        AssetPicker: triggerSlotStub,
        Button: buttonStub,
        Slider: true,
      },
    },
  });
}

describe("AudioAsset", () => {
  it("forwards select from inner AssetPicker", () => {
    const w = mountIt();
    const picker = w.findComponent({ name: "AssetPicker" });
    picker.vm.$emit("select", ASSETS[0]);
    expect(w.emitted("select")![0]).toEqual([ASSETS[0]]);
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

  it("emits volume-change with the integer percent from the slider", () => {
    const w = mountIt({ assetId: 1, volume: 50 });
    const slider = w.findComponent({ name: "Slider" });
    slider.vm.$emit("update:modelValue", [73]);
    expect(w.emitted("volume-change")![0]).toEqual([73]);
  });

  it("ignores empty / non-finite slider values without emitting", () => {
    const w = mountIt({ assetId: 1, volume: 50 });
    const slider = w.findComponent({ name: "Slider" });
    slider.vm.$emit("update:modelValue", []);
    slider.vm.$emit("update:modelValue", undefined);
    slider.vm.$emit("update:modelValue", [Number.NaN]);
    expect(w.emitted("volume-change")).toBeUndefined();
  });

  it("hides the slider while no asset is selected", () => {
    const w = mountIt({ assetId: null });
    expect(w.findComponent({ name: "Slider" }).exists()).toBe(false);
  });

  it("re-syncs the local volume mirror when the prop changes", async () => {
    const w = mountIt({ assetId: 1, volume: 50 });
    await w.setProps({ volume: 80 });
    // The slider receives the mirrored value via :model-value="[volumeValue]".
    const slider = w.findComponent({ name: "Slider" });
    expect(slider.props("modelValue")).toEqual([80]);
  });

  it("allows long selected filenames to truncate inside the picker trigger", () => {
    const longFilename =
      "atmospheric_factory_ambience_take_07_with_many_descriptive_words_and_suffix.mp3";
    const w = mountWithTrigger({
      assetId: 99,
      audioAssets: [{ id: 99, filename: longFilename, url: "/long.mp3" }],
    });

    const trigger = w.find('[data-test="asset-picker-stub"] button');
    expect(trigger.classes()).toEqual(
      expect.arrayContaining(["w-full", "min-w-0", "shrink", "overflow-hidden"]),
    );

    const filename = trigger.find("span");
    expect(filename.text()).toBe(longFilename);
    expect(filename.classes()).toEqual(expect.arrayContaining(["min-w-0", "flex-1", "truncate"]));
  });
});
