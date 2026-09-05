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

const audioAssetStub = {
  name: "AudioAsset",
  props: ["label", "assetId", "volume", "canEdit"],
  emits: ["select", "clear", "volume-change"],
  template:
    '<div data-stub="audio-asset" :data-asset-id="assetId"><span>{{ label }}</span><slot name="header-actions" /></div>',
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
        AudioAsset: audioAssetStub,
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
    tracks: [
      {
        id: "music-continuity",
        trackKey: "theme",
        local_row_id: 301,
        sequenceId: 10,
        kind: "music",
        assetId: 3,
        url: "/theme.mp3",
        volume: 0.5,
        overridden_fields: ["volume"],
        propertyOrigins: {
          position: { nodeId: 10, inherited: true },
          asset_id: { nodeId: 10, inherited: true },
          start_time: { nodeId: 10, inherited: true },
          end_time: { nodeId: 10, inherited: true },
          volume: { nodeId: 20, inherited: false },
        },
      },
      {
        id: "local-sfx",
        trackKey: "door-sfx",
        local_row_id: 302,
        sequenceId: 20,
        kind: "sfx",
        assetId: 4,
        url: "/door.mp3",
        volume: 0.8,
      },
    ],
    removed_tracks: [
      {
        id: 303,
        trackKey: "wind",
        track_key: "wind",
        kind: "ambience",
        removed: true,
      },
    ],
    diagnostics: [{ code: "missing_asset", severity: "warning", nodeId: 10 }],
    image_assets: [
      { id: 1, filename: "courtyard.webp", url: "/courtyard.webp" },
      { id: 2, filename: "aria.webp", url: "/aria.webp" },
      { id: 9, filename: "aria-alt.webp", url: "/aria-alt.webp" },
    ],
    audio_assets: [
      { id: 3, filename: "theme.mp3", url: "/theme.mp3" },
      { id: 4, filename: "door.mp3", url: "/door.mp3" },
      { id: 9, filename: "alternate.mp3", url: "/alternate.mp3" },
    ],
  };
}

describe("FlowSequenceConfigPanel", () => {
  beforeEach(() => {
    setTestLocale("en");
    vi.mocked(mockLive.pushEvent).mockClear();
  });

  it("provides accessible names for the panel and composition controls", () => {
    const w = mountIt(composedDialogueData());

    expect(w.get('button[aria-label="Close"]').attributes("title")).toBe("Close");
    expect(w.get("[data-composition-source-trigger]").attributes("aria-labelledby")).toBe(
      "sequence-composition-source-label",
    );
    expect(w.get("#sequence-composition-source-label").text()).toBe("Composition source");
    expect(
      w.findAll("[data-layer-visible]").map((control) => control.attributes("aria-label")),
    ).toEqual(["Visible: Night courtyard", "Visible: Aria"]);
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
    const w = mountIt(composedDialogueData());

    expect(w.text()).toContain("Dialogue · #20");
    expect(w.text()).toContain("Courtyard");
    expect(w.get("[data-composition-diagnostics]").text()).toContain("1 composition issue");

    w.getComponent({ name: "Select" }).vm.$emit("update:modelValue", "11");

    expect(mockLive.pushEvent).toHaveBeenCalledWith("set_composition_source", {
      id: 20,
      source_id: "11",
    });

    vi.mocked(mockLive.pushEvent).mockClear();
    w.getComponent({ name: "Select" }).vm.$emit("update:modelValue", "__composition_root__");

    expect(mockLive.pushEvent).toHaveBeenCalledWith("set_composition_source", {
      id: 20,
      source_id: null,
    });
  });

  it("renders translated composition diagnostics without exposing internal codes", () => {
    const data = composedDialogueData();
    data.diagnostics = [
      { code: "composition_cycle" },
      { code: "invalid_composition_source" },
      { code: "missing_composition_source" },
      { code: "missing_inherited_layer" },
      { code: "missing_inherited_track" },
      { code: "future_diagnostic" },
    ];

    const text = mountIt(data).get("[data-composition-diagnostics]").text();

    expect(text).toContain("The composition source chain contains a cycle.");
    expect(text).toContain("The selected composition source is not valid.");
    expect(text).toContain("The composition source is no longer available.");
    expect(text).toContain("A visual override no longer has a source layer.");
    expect(text).toContain("An audio override no longer has a source track.");
    expect(text).toContain("This composition contains an issue that needs attention.");
    expect(text).not.toContain("composition_cycle");
    expect(text).not.toContain("future_diagnostic");

    setTestLocale("es");
    const spanishText = mountIt(data).get("[data-composition-diagnostics]").text();

    expect(spanishText).toContain("La cadena de fuentes de composición contiene un ciclo.");
    expect(spanishText).toContain("La fuente de composición seleccionada no es válida.");
    expect(spanishText).toContain("La fuente de composición ya no está disponible.");
    expect(spanishText).toContain("Un ajuste visual ya no tiene una capa de origen.");
    expect(spanishText).toContain("Un ajuste de audio ya no tiene una pista de origen.");
    expect(spanishText).toContain("Esta composición contiene un problema que requiere atención.");
    expect(spanishText).not.toContain("composition_cycle");
    expect(spanishText).not.toContain("future_diagnostic");
  });

  it("deletes owner-defined layers and clears owner-defined tracks", () => {
    const w = mountIt(composedDialogueData());
    const localLayer = w
      .findAllComponents({ name: "ImageAsset" })
      .find((field) => field.props("assetId") === 1);
    const localTrack = w
      .findAllComponents({ name: "AudioAsset" })
      .find((field) => field.props("assetId") === 4);

    expect(localLayer).toBeDefined();
    expect(localTrack).toBeDefined();

    localLayer!.vm.$emit("clear");
    expect(mockLive.pushEvent).toHaveBeenCalledWith("delete_sequence_visual_layer", {
      id: 20,
      layer_id: 101,
    });

    vi.mocked(mockLive.pushEvent).mockClear();
    localTrack!.vm.$emit("clear");
    expect(mockLive.pushEvent).toHaveBeenCalledWith("clear_sequence_track", {
      id: 20,
      kind: "sfx",
    });
  });

  it("removes a materialized track restoration by logical key", () => {
    const data = composedDialogueData();
    data.tracks?.push({
      id: "restored-rain",
      trackKey: "rain",
      local_row_id: 304,
      sequenceId: 20,
      isOverride: true,
      kind: "ambience",
      assetId: 9,
      url: "/alternate.mp3",
      volume: 0.6,
      overridden_fields: ["position", "asset_id", "start_time", "end_time", "volume"],
    });

    const w = mountIt(data);
    const restoredTrack = w
      .findAllComponents({ name: "AudioAsset" })
      .find((field) => field.props("assetId") === 9);

    expect(restoredTrack).toBeDefined();
    restoredTrack!.vm.$emit("volume-change", 40);
    expect(mockLive.pushEvent).toHaveBeenCalledWith("override_sequence_track", {
      id: 20,
      track_key: "rain",
      volume: 0.4,
    });

    vi.mocked(mockLive.pushEvent).mockClear();
    restoredTrack!.vm.$emit("clear");

    expect(mockLive.pushEvent).toHaveBeenCalledWith("remove_sequence_track", {
      id: 20,
      track_key: "rain",
    });
  });

  it("overrides, reverts, removes and restores effective layers by logical key", async () => {
    const w = mountIt(composedDialogueData());
    const inherited = w.get('[data-layer-key="hero"]');
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
    await w.get('[data-removed-layer-key="lantern"] [data-restore-layer]').trigger("click");
    expect(mockLive.pushEvent).toHaveBeenCalledWith("restore_sequence_visual_layer", {
      id: 20,
      layer_key: "lantern",
    });
  });

  it("uses overrides for inherited tracks and legacy upsert for owner tracks", async () => {
    const w = mountIt(composedDialogueData());
    const audioFields = w.findAllComponents({ name: "AudioAsset" });
    const inherited = audioFields.find((field) => field.props("assetId") === 3);
    const local = audioFields.find((field) => field.props("assetId") === 4);

    expect(inherited).toBeDefined();
    expect(local).toBeDefined();

    inherited!.vm.$emit("select", { id: 9, filename: "alternate.mp3" });
    expect(mockLive.pushEvent).toHaveBeenCalledWith("override_sequence_track", {
      id: 20,
      track_key: "theme",
      asset_id: 9,
    });

    vi.mocked(mockLive.pushEvent).mockClear();
    inherited!.vm.$emit("volume-change", 75);
    expect(mockLive.pushEvent).toHaveBeenCalledWith("override_sequence_track", {
      id: 20,
      track_key: "theme",
      volume: 0.75,
    });

    vi.mocked(mockLive.pushEvent).mockClear();
    local!.vm.$emit("select", { id: 9, filename: "alternate.mp3" });
    expect(mockLive.pushEvent).toHaveBeenCalledWith("upsert_sequence_track", {
      id: 20,
      kind: "sfx",
      asset_id: 9,
    });

    vi.mocked(mockLive.pushEvent).mockClear();
    inherited!.vm.$emit("clear");
    expect(mockLive.pushEvent).toHaveBeenCalledWith("remove_sequence_track", {
      id: 20,
      track_key: "theme",
    });

    vi.mocked(mockLive.pushEvent).mockClear();
    await w.get("[data-revert-track]").trigger("click");
    expect(mockLive.pushEvent).toHaveBeenCalledWith("revert_sequence_track", {
      id: 20,
      track_key: "theme",
      fields: ["volume"],
    });

    vi.mocked(mockLive.pushEvent).mockClear();
    await w.get('[data-removed-track-key="wind"] [data-restore-track]').trigger("click");
    expect(mockLive.pushEvent).toHaveBeenCalledWith("restore_sequence_track", {
      id: 20,
      track_key: "wind",
    });
  });

  it("reverts individual inherited track fields with localized labels", async () => {
    const data = composedDialogueData();
    const inheritedTrack = data.tracks?.[0];
    if (!inheritedTrack) throw new Error("missing inherited track fixture");
    inheritedTrack.overridden_fields = ["asset_id", "volume"];

    const english = mountIt(data);
    const overrides = english.get('[data-track-key="theme"] [data-track-overrides]');

    expect(overrides.text()).toContain("Asset");
    expect(overrides.text()).toContain("Volume");

    await overrides.get('[data-revert-track-field="volume"]').trigger("click");
    expect(mockLive.pushEvent).toHaveBeenCalledWith("revert_sequence_track", {
      id: 20,
      track_key: "theme",
      fields: ["volume"],
    });
    english.unmount();

    setTestLocale("es");
    const spanish = mountIt(data).get('[data-track-key="theme"] [data-track-overrides]').text();
    expect(spanish).toContain("Recurso");
    expect(spanish).toContain("Volumen");
  });

  it("keeps sequence mutations inert in read-only mode", async () => {
    const w = mountIt(composedDialogueData(), false);
    const visualRevert = w.get('[data-revert-field="x"]');
    const trackRevert = w.get("[data-revert-track]");
    const trackFieldRevert = w.get('[data-revert-track-field="volume"]');

    expect(visualRevert.attributes("disabled")).toBeDefined();
    expect(trackRevert.attributes("disabled")).toBeDefined();
    expect(trackFieldRevert.attributes("disabled")).toBeDefined();

    await visualRevert.trigger("click");
    await trackRevert.trigger("click");
    await trackFieldRevert.trigger("click");

    w.getComponent({ name: "Select" }).vm.$emit("update:modelValue", "11");
    w.findAllComponents({ name: "ImageAsset" })[0]!.vm.$emit("clear");
    w.findAllComponents({ name: "AudioAsset" })[0]!.vm.$emit("volume-change", 25);

    expect(mockLive.pushEvent).not.toHaveBeenCalled();
  });

  it("shows the source owner for each effective track property", () => {
    const w = mountIt(composedDialogueData());
    const track = w.get('[data-track-key="theme"]');
    const assetOrigin = track.get('[data-track-property-origin="asset_id"]');
    const volumeOrigin = track.get('[data-track-property-origin="volume"]');

    expect(track.findAll("[data-track-property-origin]")).toHaveLength(2);
    expect(assetOrigin.text()).toContain("Asset");
    expect(assetOrigin.text()).toContain("Courtyard");
    expect(volumeOrigin.text()).toContain("Volume");
    expect(volumeOrigin.text()).toContain("this node");
  });

  it("offers local track slots when the same kinds are inherited or removed", () => {
    const w = mountIt(composedDialogueData());
    const emptyTrackFields = w
      .findAllComponents({ name: "AudioAsset" })
      .filter((field) => field.props("assetId") == null);

    expect(emptyTrackFields.map((field) => field.props("label"))).toEqual(["Music", "Ambience"]);

    emptyTrackFields[0]!.vm.$emit("select", { id: 9, filename: "alternate.mp3" });
    expect(mockLive.pushEvent).toHaveBeenCalledWith("upsert_sequence_track", {
      id: 20,
      kind: "music",
      asset_id: 9,
    });

    vi.mocked(mockLive.pushEvent).mockClear();
    emptyTrackFields[1]!.vm.$emit("select", { id: 9, filename: "alternate.mp3" });
    expect(mockLive.pushEvent).toHaveBeenCalledWith("upsert_sequence_track", {
      id: 20,
      kind: "ambience",
      asset_id: 9,
    });
  });
});
