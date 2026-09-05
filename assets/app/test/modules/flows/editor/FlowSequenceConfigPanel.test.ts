import { describe, expect, it, vi, beforeEach } from "vitest";
import { mount } from "@vue/test-utils";
import { createMockLive, setTestLocale } from "../../../setup";

const mockLive = createMockLive();

vi.mock("@shared/composables/useLive", () => ({
  useLive: () => mockLive,
}));

const { default: FlowSequenceConfigPanel } =
  await import("../../../../modules/flows/editor/components/panels/FlowSequenceConfigPanel.vue");
type PanelData = NonNullable<InstanceType<typeof FlowSequenceConfigPanel>["$props"]["data"]>;

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

const selectStub = {
  name: "Select",
  props: ["modelValue", "disabled"],
  emits: ["update:modelValue"],
  template: '<div data-stub="select"><slot /></div>',
};

const switchStub = {
  name: "Switch",
  props: ["modelValue", "disabled"],
  emits: ["update:modelValue"],
  template: '<button type="button" data-stub="switch" />',
};

const imageAssetStub = {
  name: "ImageAsset",
  props: ["label", "assetId", "canEdit"],
  emits: ["select", "clear"],
  template:
    '<div data-stub="image-asset" :data-asset-id="assetId"><span>{{ label }}</span><slot name="header-actions" /></div>',
};

function legacyPanelData(): PanelData {
  return {
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
  };
}

function mountIt(data: PanelData = legacyPanelData(), canEdit = true) {
  return mount(FlowSequenceConfigPanel, {
    props: {
      open: true,
      canEdit,
      data,
    },
    global: {
      stubs: {
        AudioAsset: { name: "AudioAsset", template: "<div data-stub='audio-asset' />" },
        ImageAsset: imageAssetStub,
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
        Select: selectStub,
        SelectTrigger: passthrough,
        SelectValue: passthrough,
        SelectContent: passthrough,
        SelectItem: passthrough,
        Switch: switchStub,
      },
    },
  });
}

function composedDialogueData(): PanelData {
  return {
    owner_id: 20,
    owner_type: "dialogue",
    composition_source_id: 10,
    composition_sources: [
      { id: 10, type: "sequence", label: "Courtyard" },
      { id: 11, type: "dialogue", label: "Earlier line" },
    ],
    config: null,
    visual_layers: [
      {
        id: "local-backdrop",
        key: "local-backdrop",
        local_row_id: 101,
        sequenceId: 20,
        kind: "backdrop",
        label: "Night courtyard",
        assetId: 1,
        url: "/courtyard.webp",
        slot: "full",
        fit: "cover",
        opacity: 1,
        zIndex: 0,
        origin: { nodeId: 20, inherited: false },
      },
      {
        id: "hero",
        key: "hero",
        local_row_id: 202,
        sequenceId: 10,
        kind: "character",
        label: "Aria",
        assetId: 2,
        url: "/aria.webp",
        slot: "bottom-center",
        x: 0.5,
        y: 1,
        width: 0.4,
        height: 0.9,
        fit: "contain",
        opacity: 1,
        visible: true,
        zIndex: 10,
        overridden_fields: ["x"],
        origin: { nodeId: 10, inherited: true },
        propertyOrigins: { x: { nodeId: 10, inherited: true } },
      },
    ],
    removed_visual_layers: [
      {
        id: 203,
        key: "lantern",
        layer_key: "lantern",
        kind: "prop",
        label: "Lantern",
        removed: true,
      },
    ],
    diagnostics: [{ code: "missing_asset", severity: "warning", nodeId: 10 }],
    tracks: [],
    image_assets: [
      { id: 1, filename: "courtyard.webp", url: "/courtyard.webp" },
      { id: 2, filename: "aria.webp", url: "/aria.webp" },
    ],
    audio_assets: [],
  };
}

describe("FlowSequenceConfigPanel", () => {
  beforeEach(() => {
    setTestLocale("en");
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

  it("targets a dialogue owner and changes its explicit composition source", () => {
    const wrapper = mountIt(composedDialogueData());

    expect(wrapper.text()).toContain("Dialogue · #20");
    expect(wrapper.text()).toContain("Courtyard");
    expect(wrapper.get("[data-composition-diagnostics]").text()).toContain("1 composition issue");

    wrapper.getComponent({ name: "Select" }).vm.$emit("update:modelValue", "11");
    expect(mockLive.pushEvent).toHaveBeenCalledWith("set_composition_source", {
      id: 20,
      source_id: "11",
    });

    vi.mocked(mockLive.pushEvent).mockClear();
    wrapper.getComponent({ name: "Select" }).vm.$emit("update:modelValue", "__composition_root__");
    expect(mockLive.pushEvent).toHaveBeenCalledWith("set_composition_source", {
      id: 20,
      source_id: null,
    });
  });

  it("renders translated visual diagnostics without exposing internal codes", () => {
    const data = composedDialogueData();
    data.diagnostics = [
      { code: "composition_cycle" },
      { code: "invalid_composition_source" },
      { code: "missing_composition_source" },
      { code: "missing_inherited_layer" },
      { code: "future_diagnostic" },
    ];

    const text = mountIt(data).get("[data-composition-diagnostics]").text();
    expect(text).toContain("The composition source chain contains a cycle.");
    expect(text).toContain("The selected composition source is not valid.");
    expect(text).toContain("The composition source is no longer available.");
    expect(text).toContain("A visual override no longer has a source layer.");
    expect(text).toContain("This composition contains an issue that needs attention.");
    expect(text).not.toContain("composition_cycle");
    expect(text).not.toContain("future_diagnostic");

    setTestLocale("es");
    const spanishText = mountIt(data).get("[data-composition-diagnostics]").text();
    expect(spanishText).toContain("La cadena de fuentes de composición contiene un ciclo.");
    expect(spanishText).toContain("La fuente de composición seleccionada no es válida.");
    expect(spanishText).toContain("La fuente de composición ya no está disponible.");
    expect(spanishText).toContain("Un ajuste visual ya no tiene una capa de origen.");
    expect(spanishText).toContain("Esta composición contiene un problema que requiere atención.");
  });

  it("updates local layers and overrides inherited layers by logical key", async () => {
    const wrapper = mountIt(composedDialogueData());
    const localLayer = wrapper
      .findAllComponents({ name: "ImageAsset" })
      .find((field) => field.props("assetId") === 1);

    expect(localLayer).toBeDefined();
    localLayer!.vm.$emit("clear");
    expect(mockLive.pushEvent).toHaveBeenCalledWith("delete_sequence_visual_layer", {
      id: 20,
      layer_id: 101,
    });

    vi.mocked(mockLive.pushEvent).mockClear();
    const inherited = wrapper.get('[data-layer-key="hero"]');
    const xInput = inherited.get('[data-layer-field="x"]');
    (xInput.element as HTMLInputElement).value = "0.65";
    await xInput.trigger("change");
    expect(mockLive.pushEvent).toHaveBeenCalledWith("override_sequence_visual_layer", {
      id: 20,
      layer_key: "hero",
      x: 0.65,
    });

    vi.mocked(mockLive.pushEvent).mockClear();
    await inherited.get('[data-revert-field="x"]').trigger("click");
    expect(mockLive.pushEvent).toHaveBeenCalledWith("revert_sequence_visual_layer", {
      id: 20,
      layer_key: "hero",
      fields: ["x"],
    });

    vi.mocked(mockLive.pushEvent).mockClear();
    await inherited.get("[data-remove-layer]").trigger("click");
    expect(mockLive.pushEvent).toHaveBeenCalledWith("remove_sequence_visual_layer", {
      id: 20,
      layer_key: "hero",
    });

    vi.mocked(mockLive.pushEvent).mockClear();
    await wrapper.get('[data-removed-layer-key="lantern"] [data-restore-layer]').trigger("click");
    expect(mockLive.pushEvent).toHaveBeenCalledWith("restore_sequence_visual_layer", {
      id: 20,
      layer_key: "lantern",
    });
  });

  it("keeps visual mutations inert in read-only mode", async () => {
    const wrapper = mountIt(composedDialogueData(), false);
    const revert = wrapper.get('[data-revert-field="x"]');

    expect(revert.attributes("disabled")).toBeDefined();
    await revert.trigger("click");
    wrapper.getComponent({ name: "Select" }).vm.$emit("update:modelValue", "11");
    wrapper.findAllComponents({ name: "ImageAsset" })[0]!.vm.$emit("clear");

    expect(mockLive.pushEvent).not.toHaveBeenCalled();
  });
});
