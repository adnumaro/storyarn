import { describe, expect, it, vi, beforeEach } from "vitest";
import { mount } from "@vue/test-utils";
import { createMockLive } from "../../../setup";

const mockLive = createMockLive();

vi.mock("@shared/composables/useLive", () => ({
  useLive: () => mockLive,
}));

const { default: FlowSequenceConfigPanel } =
  await import("../../../../modules/flows/editor/components/panels/FlowSequenceConfigPanel.vue");

const passthrough = { template: "<div><slot /><slot name='header' /></div>" };

const toggleGroupStub = {
  name: "ToggleGroup",
  props: ["modelValue", "disabled"],
  emits: ["update:modelValue"],
  template: '<div data-stub="toggle-group"><slot /></div>',
};

const toggleGroupItemStub = {
  name: "ToggleGroupItem",
  props: ["value"],
  template: '<button type="button" data-stub="toggle-group-item" :value="value"><slot /></button>',
};

const commandItemStub = {
  name: "CommandItem",
  props: ["value"],
  emits: ["select"],
  template:
    '<button type="button" data-stub="command-item" @click="$emit(\'select\', $event)"><slot /></button>',
};

const tabsStub = {
  name: "Tabs",
  props: ["defaultValue", "modelValue"],
  emits: ["update:modelValue"],
  template: '<div data-stub="tabs"><slot /></div>',
};

const tabsTriggerStub = {
  name: "TabsTrigger",
  props: ["value"],
  template: '<button type="button" data-stub="tabs-trigger" :value="value"><slot /></button>',
};

const tabsContentStub = {
  name: "TabsContent",
  props: ["value"],
  template: '<div data-stub="tabs-content"><slot /></div>',
};

function mountIt() {
  return mount(FlowSequenceConfigPanel, {
    props: {
      open: true,
      canEdit: true,
      data: {
        sequence_id: 8,
        config: null,
        visual_layers: [
          {
            id: 101,
            kind: "backdrop",
            label: "sora_image_generation_remix_01km0deh04ei89912a1evvcrdz.webp",
            asset_id: 1,
            slot: "full",
            fit: "cover",
            opacity: 1,
          },
        ],
        tracks: [],
        image_assets: [
          {
            id: 1,
            filename: "sora_image_generation_remix_01km0deh04ei89912a1evvcrdz.webp",
            url: "/image.webp",
          },
        ],
        audio_assets: [],
      },
    },
    global: {
      stubs: {
        AudioAsset: { name: "AudioAsset", template: "<div data-stub='audio-asset' />" },
        ImageAsset: {
          name: "ImageAsset",
          template: "<div data-stub='image-asset'><slot name='header-actions' /></div>",
        },
        ImagePosition: { name: "ImagePosition", template: "<div data-stub='image-position' />" },
        Sidebar: {
          name: "Sidebar",
          template: "<aside><slot name='header' /><slot /></aside>",
        },
        ToggleGroup: toggleGroupStub,
        ToggleGroupItem: toggleGroupItemStub,
        Popover: passthrough,
        PopoverTrigger: passthrough,
        PopoverContent: passthrough,
        Command: passthrough,
        CommandList: passthrough,
        CommandGroup: passthrough,
        CommandItem: commandItemStub,
        Tabs: tabsStub,
        TabsList: passthrough,
        TabsTrigger: tabsTriggerStub,
        TabsContent: tabsContentStub,
      },
    },
  });
}

describe("FlowSequenceConfigPanel", () => {
  beforeEach(() => {
    vi.mocked(mockLive.pushEvent).mockClear();
  });

  it("uses popover for visual type and segmented tabs for fit", () => {
    const w = mountIt();

    expect(w.findAll("select")).toHaveLength(0);
    expect(w.text()).toContain("Backdrop");
    expect(w.text()).toContain("Layout");
    expect(w.text()).toContain("Cover");

    const settingsTabs = w.findAll('[data-stub="tabs-trigger"]').map((item) => item.text().trim());
    expect(settingsTabs).toEqual(["Visual composition", "Audio tracks"]);

    const options = w.findAll('[data-stub="command-item"]').map((item) => item.text());
    expect(options).toEqual(expect.arrayContaining(["Backdrop", "Character", "Prop", "Overlay"]));
    expect(options).not.toContain("Cover");
    expect(options).not.toContain("Contain");
    expect(options).not.toContain("Fill");

    const tabValues = w
      .findAll('[data-stub="toggle-group-item"]')
      .map((item) => item.attributes("value"));
    expect(tabValues).toEqual(expect.arrayContaining(["cover", "contain", "fill"]));
  });

  it("updates visual type from the popover and fit from segmented tabs", async () => {
    const w = mountIt();
    const items = w.findAll('[data-stub="command-item"]');

    const characterOption = items.find((item) => item.text() === "Character");
    expect(characterOption).toBeDefined();
    await characterOption!.trigger("click");

    expect(mockLive.pushEvent).toHaveBeenCalledWith(
      "update_sequence_visual_layer",
      expect.objectContaining({
        id: 8,
        layer_id: 101,
        kind: "character",
        slot: "bottom-center",
      }),
    );

    vi.mocked(mockLive.pushEvent).mockClear();

    const fitGroup = w
      .findAllComponents({ name: "ToggleGroup" })
      .find((group) => group.props("modelValue") === "cover");
    expect(fitGroup).toBeDefined();
    fitGroup!.vm.$emit("update:modelValue", "fill");

    expect(mockLive.pushEvent).toHaveBeenCalledWith(
      "update_sequence_visual_layer",
      expect.objectContaining({
        id: 8,
        layer_id: 101,
        fit: "fill",
      }),
    );
  });
});
