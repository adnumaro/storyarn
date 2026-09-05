import { mount } from "@vue/test-utils";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { createMockLive, setTestLocale } from "../../../setup";

const mockLive = createMockLive();

vi.mock("@shared/composables/useLive", () => ({
  useLive: () => mockLive,
}));

const { default: FlowDebugPanel } =
  await import("../../../../modules/flows/editor/components/panels/FlowDebugPanel.vue");

type DebugState = NonNullable<InstanceType<typeof FlowDebugPanel>["$props"]["state"]>;
type DebugNodes = InstanceType<typeof FlowDebugPanel>["$props"]["nodes"];
type DebugComposition = NonNullable<InstanceType<typeof FlowDebugPanel>["$props"]["composition"]>;
type DebugControls = InstanceType<typeof FlowDebugPanel>["$props"]["controls"];
type PlaybackAction = "step" | "back" | "choice" | "pause" | "reset" | "stop";

const passthrough = { template: "<div><slot /></div>" };
const tabsContentStub = {
  props: ["value"],
  template: '<section :data-tab-content="value"><slot /></section>',
};

function debugState(currentNodeId: number): DebugState {
  return {
    status: "paused",
    current_node_id: currentNodeId,
    start_node_id: 1,
    step_count: 1,
    max_steps: 1000,
    variables: {},
    console: [],
    history: [],
    execution_path: [currentNodeId],
    execution_log: [{ node_id: currentNodeId, depth: 0 }],
    pending_choices: null,
    call_stack: [],
    breakpoints: [],
  };
}

function composition(overrides: Partial<DebugComposition> = {}): DebugComposition {
  return {
    visualLayers: [],
    removedVisualLayers: [],
    audioTracks: [],
    removedAudioTracks: [],
    diagnostics: [],
    ...overrides,
  };
}

function debugNodes(): DebugNodes {
  return {
    "1": {
      type: "sequence",
      sequence_config: { name: "Base" },
    },
    "2": {
      type: "dialogue",
      data: { text: "<p>Reply</p>" },
    },
    "3": {
      type: "condition",
      data: {},
    },
    "4": {
      type: "dialogue",
      data: { text: "<p>Hostile branch</p>" },
    },
  };
}

function compositionFor(currentNodeId: number): DebugComposition | null {
  switch (currentNodeId) {
    case 1:
      return composition({
        presentationNodeId: 1,
        visualLayers: [
          {
            id: "room",
            key: "room",
            kind: "backdrop",
            label: "Room",
            origin: { nodeId: 1, inherited: false },
            overriddenProperties: [],
          },
        ],
      });
    case 2:
      return composition({
        presentationNodeId: 2,
        visualLayers: [
          {
            id: "hero",
            key: "hero",
            kind: "character",
            label: "Hero",
            origin: { nodeId: 1, inherited: true },
            lastChangedByNodeId: 2,
            overriddenProperties: [{ field: "opacity", nodeId: 2 }],
          },
        ],
        removedVisualLayers: [
          {
            id: "room",
            key: "room",
            kind: "backdrop",
            label: "Room",
            origin: { nodeId: 1, inherited: true },
            removed: true,
            removedByNodeId: 2,
            overriddenProperties: [],
          },
        ],
        audioTracks: [
          {
            id: "theme:13",
            trackKey: "theme",
            kind: "music",
            filename: "theme.mp3",
            origin: { nodeId: 1, inherited: true },
            lastChangedByNodeId: 2,
            overriddenProperties: [{ field: "volume", nodeId: 2 }],
          },
        ],
        removedAudioTracks: [
          {
            id: "wind",
            trackKey: "wind",
            kind: "ambience",
            origin: { nodeId: 1, inherited: true },
            removed: true,
            removedByNodeId: 2,
            overriddenProperties: [],
          },
        ],
        diagnostics: [{ code: "missing_inherited_layer", nodeId: 2, severity: "warning" }],
      });
    case 3: {
      const previousPresentation = compositionFor(2);
      return previousPresentation ? { ...previousPresentation, presentationNodeId: 2 } : null;
    }
    case 4:
      return composition({
        presentationNodeId: 4,
        audioTracks: [
          {
            id: "threat:41",
            trackKey: "threat",
            kind: "music",
            filename: "threat.mp3",
            origin: { nodeId: 4, inherited: false },
            overriddenProperties: [],
          },
        ],
      });
    default:
      return null;
  }
}

function defaultControls(): DebugControls {
  return {
    activeTab: "composition",
    autoPlaying: false,
    speed: 800,
    varFilter: "",
    varChangedOnly: false,
    flowName: "Opening",
    stepLimitReached: false,
  };
}

function mountPanel(
  currentNodeId = 2,
  options: {
    state?: DebugState;
    composition?: DebugComposition | null;
    controls?: DebugControls;
    onPlaybackAction?: (action: PlaybackAction) => void;
  } = {},
) {
  return mount(FlowDebugPanel, {
    props: {
      open: true,
      embedded: true,
      state: options.state ?? debugState(currentNodeId),
      nodes: debugNodes(),
      composition: options.composition ?? compositionFor(currentNodeId),
      controls: options.controls ?? defaultControls(),
      onPlaybackAction: options.onPlaybackAction,
    },
    global: {
      stubs: {
        Badge: { template: "<span><slot /></span>" },
        Button: { template: "<button type='button'><slot /></button>" },
        Checkbox: { template: "<input type='checkbox' />" },
        BooleanToggle: passthrough,
        Command: passthrough,
        CommandEmpty: passthrough,
        CommandGroup: passthrough,
        CommandInput: passthrough,
        CommandItem: passthrough,
        CommandList: passthrough,
        Popover: passthrough,
        PopoverContent: passthrough,
        PopoverTrigger: passthrough,
        Slider: passthrough,
        Tabs: passthrough,
        TabsContent: tabsContentStub,
        TabsList: passthrough,
        TabsTrigger: { props: ["value"], template: "<button><slot /></button>" },
      },
    },
  });
}

describe("FlowDebugPanel composition", () => {
  beforeEach(() => {
    setTestLocale("en");
    vi.mocked(mockLive.pushEvent).mockReset();
  });

  it("shows effective media, provenance, overridden properties, tombstones, and friendly diagnostics", () => {
    const wrapper = mountPanel();

    expect(wrapper.get("[data-debug-composition]").text()).toContain(
      "Effective composition · Reply",
    );
    expect(wrapper.get('[data-debug-layer-key="hero"]').text()).toContain("Inherited");
    expect(wrapper.get('[data-debug-layer-key="hero"]').text()).toContain("From Base");
    expect(wrapper.get('[data-debug-property="opacity"]').text()).toContain("Opacity · Reply");
    expect(wrapper.get('[data-debug-removed-layer-key="room"]').text()).toContain(
      "Removed by Reply",
    );
    expect(wrapper.get('[data-debug-removed-layer-key="room"]').text()).toContain("From Base");
    expect(wrapper.get('[data-debug-track-key="theme"]').text()).toContain("theme.mp3");
    expect(wrapper.get('[data-debug-property="volume"]').text()).toContain("Volume · Reply");
    expect(wrapper.get('[data-debug-removed-track-key="wind"]').text()).toContain(
      "Removed by Reply",
    );
    expect(wrapper.get('[data-debug-removed-track-key="wind"]').text()).toContain("From Base");
    expect(wrapper.get("[data-debug-composition-diagnostics]").text()).toContain(
      "A visual override no longer has a source layer.",
    );
    expect(wrapper.text()).not.toContain("missing_inherited_layer");
  });

  it("reacts to reset, step, condition branch, and step-back current-node changes", async () => {
    const wrapper = mountPanel(1);
    expect(wrapper.find('[data-debug-layer-key="room"]').exists()).toBe(true);

    await wrapper.setProps({ state: debugState(2), composition: compositionFor(2) });
    expect(wrapper.find('[data-debug-layer-key="hero"]').exists()).toBe(true);
    expect(wrapper.find('[data-debug-layer-key="room"]').exists()).toBe(false);

    await wrapper.setProps({ state: debugState(3), composition: compositionFor(3) });
    expect(wrapper.find("[data-debug-composition-unavailable]").exists()).toBe(false);
    expect(wrapper.get("[data-debug-composition]").text()).toContain(
      "Effective composition · Reply",
    );
    expect(wrapper.find('[data-debug-layer-key="hero"]').exists()).toBe(true);

    await wrapper.setProps({ state: debugState(4), composition: compositionFor(4) });
    expect(wrapper.find('[data-debug-track-key="threat"]').exists()).toBe(true);

    await wrapper.setProps({ state: debugState(2), composition: compositionFor(2) });
    expect(wrapper.find('[data-debug-layer-key="hero"]').exists()).toBe(true);
    expect(wrapper.find('[data-debug-track-key="threat"]').exists()).toBe(false);
  });

  it("renders the composition labels in Spanish", () => {
    setTestLocale("es");
    const wrapper = mountPanel();

    expect(wrapper.get("[data-debug-composition]").text()).toContain(
      "Composición efectiva · Reply",
    );
    expect(wrapper.get('[data-debug-removed-layer-key="room"]').text()).toContain(
      "Eliminada por Reply",
    );
  });

  it("emits every local media action before sending its Debug event", async () => {
    const order: string[] = [];
    const wrapper = mountPanel(2, {
      onPlaybackAction: (action) => order.push(`local:${action}`),
    });
    vi.mocked(mockLive.pushEvent).mockImplementation((event) => {
      order.push(`server:${event}`);
    });

    const assertOrderedAction = async (selector: string, action: PlaybackAction, event: string) => {
      order.length = 0;
      await wrapper.get(selector).trigger("click");
      expect(order).toEqual([`local:${action}`, `server:${event}`]);
    };

    await assertOrderedAction("[data-debug-step]", "step", "debug_step");
    await assertOrderedAction("[data-debug-step-back]", "back", "debug_step_back");
    await assertOrderedAction("[data-debug-reset]", "reset", "debug_reset");
    await assertOrderedAction("[data-debug-stop]", "stop", "debug_stop");

    await wrapper.setProps({ controls: { ...defaultControls(), autoPlaying: true } });
    await assertOrderedAction("[data-debug-toggle-play]", "pause", "debug_pause");

    await wrapper.setProps({
      state: {
        ...debugState(2),
        status: "waiting_input",
        pending_choices: [{ id: "accept", text: "Accept", valid: true }],
      },
    });
    await assertOrderedAction('[data-debug-choice="accept"]', "choice", "debug_choose_response");
    expect(mockLive.pushEvent).toHaveBeenLastCalledWith("debug_choose_response", {
      id: "accept",
    });
  });
});
