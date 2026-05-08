import { describe, it, expect, vi, beforeEach } from "vitest";
import { mount } from "@vue/test-utils";
import { createMockLive } from "../../../setup";

const mockLive = createMockLive();

vi.mock("@shared/composables/useLive", () => ({
  useLive: () => mockLive,
}));

const { default: FlowDialoguePanel } =
  await import("@modules/flows/components/FlowDialoguePanel.vue");
// Importing the panel's own DialoguePanelData interface gives the fixture
// the exact same nominal type the prop expects — no structural-mismatch
// false positives from the IDE's TS server.
import type { DialoguePanelData } from "@modules/flows/components/FlowDialoguePanel.vue";

const BASE_DATA: DialoguePanelData = {
  nodeId: 36,
  speakerSheetId: null,
  text: "",
  stageDirections: "",
  menuText: "",
  technicalId: "",
  localizationId: "",
  audioAssetId: null,
  avatarId: null,
  responses: [
    {
      id: "r1_abc",
      text: "Initial response",
      condition: null,
      instructionAssignments: [],
    },
  ],
  allSheets: [],
  audioAssets: [],
  projectVariables: [],
};

function makeData(overrides: Partial<DialoguePanelData> = {}): DialoguePanelData {
  return { ...BASE_DATA, ...overrides };
}

function mountIt(overrides: Partial<{ data: DialoguePanelData; canEdit: boolean }> = {}) {
  return mount(FlowDialoguePanel, {
    props: {
      open: true,
      data: BASE_DATA,
      canEdit: true,
      ...overrides,
    },
    global: {
      stubs: {
        // TipTap pulls in heavy deps not relevant to wire-format tests.
        EditorContent: { template: "<div data-stub='tiptap' />" },
        // shadcn-vue's TabsContent (reka-ui Tabs) only mounts the active
        // tab's content. For wire-format tests we want every tab's children
        // visible at once.
        TabsContent: { template: "<div><slot /></div>" },
        // AudioAsset uses reka-ui Popover/Command which reach for
        // ResizeObserver (not defined in jsdom). Stub keeps the surface
        // findable for emit assertions.
        AudioAsset: { name: "AudioAsset", template: "<div data-stub='audio-asset' />" },
      },
    },
  });
}

describe("FlowDialoguePanel — response wire-format (V1 contract)", () => {
  beforeEach(() => {
    vi.mocked(mockLive.pushEvent).mockClear();
  });

  it("add_response sends only node-id with hyphen", async () => {
    const w = mountIt();
    const addBtn = w.findAll("button").find((b) => /add response|añadir respuesta/i.test(b.text()));
    expect(addBtn).toBeDefined();
    await addBtn!.trigger("click");

    expect(mockLive.pushEvent).toHaveBeenCalledWith("add_response", { "node-id": 36 });
  });

  it("remove_response sends response-id + node-id with hyphens", async () => {
    const w = mountIt();
    const removeBtn = w.findAll("button").find((b) => /remove|eliminar|quitar/i.test(b.text()));
    expect(removeBtn).toBeDefined();
    await removeBtn!.trigger("click");

    expect(mockLive.pushEvent).toHaveBeenCalledWith("remove_response", {
      "response-id": "r1_abc",
      "node-id": 36,
    });
  });

  it("update_response_text uses value key + node-id (not text, not response_id)", async () => {
    const w = mountIt();
    const input = w.findAll("input").find((el) => el.element.value === "Initial response");
    expect(input).toBeDefined();
    await input!.setValue("New text");
    await input!.trigger("blur");

    expect(mockLive.pushEvent).toHaveBeenCalledWith("update_response_text", {
      "response-id": "r1_abc",
      "node-id": 36,
      value: "New text",
    });
  });

  it("update_response_condition stringifies the condition object before push", async () => {
    const w = mountIt();
    const builder = w.findComponent({ name: "ConditionBuilder" });
    expect(builder.exists()).toBe(true);
    builder.vm.$emit("update:condition", { logic: "all", blocks: [] });

    expect(mockLive.pushEvent).toHaveBeenCalledWith("update_response_condition", {
      "response-id": "r1_abc",
      "node-id": 36,
      value: '{"logic":"all","blocks":[]}',
    });
  });

  it("update_response_condition pushes empty string when condition is cleared", async () => {
    const w = mountIt();
    const builder = w.findComponent({ name: "ConditionBuilder" });
    builder.vm.$emit("update:condition", null);

    expect(mockLive.pushEvent).toHaveBeenCalledWith("update_response_condition", {
      "response-id": "r1_abc",
      "node-id": 36,
      value: "",
    });
  });

  it("update_response_instruction_builder is the event name (not update_response_assignments)", async () => {
    const w = mountIt();
    const builder = w.findComponent({ name: "InstructionBuilder" });
    expect(builder.exists()).toBe(true);
    const assignments = [{ variable: "health", op: "set", value: "100" }];
    builder.vm.$emit("update:assignments", assignments);

    expect(mockLive.pushEvent).toHaveBeenCalledWith("update_response_instruction_builder", {
      "response-id": "r1_abc",
      "node-id": 36,
      assignments,
    });
    expect(mockLive.pushEvent).not.toHaveBeenCalledWith(
      "update_response_assignments",
      expect.anything(),
    );
  });

  it("parses a stringified condition back into the builder on receive", () => {
    const conditionPayload = {
      logic: "any",
      blocks: [{ id: "b1", type: "block", logic: "all", rules: [] }],
    };
    const data = makeData({
      responses: [
        {
          id: "r1_abc",
          text: "Hi",
          condition: JSON.stringify(conditionPayload),
        },
      ],
    });
    const w = mountIt({ data });
    const builder = w.findComponent({ name: "ConditionBuilder" });
    expect(builder.props("condition")).toEqual(conditionPayload);
  });

  it("tolerates a non-stringified condition (defensive — old data shape)", () => {
    const data = makeData({
      responses: [
        {
          id: "r1_abc",
          text: "Hi",
          condition: { logic: "all", blocks: [] },
        },
      ],
    });
    const w = mountIt({ data });
    const builder = w.findComponent({ name: "ConditionBuilder" });
    expect(builder.props("condition")).toEqual({ logic: "all", blocks: [] });
  });

  it("wraps response condition + instruction in ExpressionEditor (not raw builders)", () => {
    const w = mountIt();
    const expressionEditors = w.findAllComponents({ name: "ExpressionEditor" });
    expect(expressionEditors.length).toBeGreaterThanOrEqual(2);
    const modes = expressionEditors.map((c) => c.props("mode"));
    expect(modes).toContain("condition");
    expect(modes).toContain("instruction");
  });

  // -- Phase 2: Settings tab parity --

  it("generate_technical_id button pushes the bare event (no params)", async () => {
    const w = mountIt();
    const btn = w
      .findAll("button")
      .find((b) => /generate technical id|generar id técnico/i.test(b.attributes("title") || ""));
    expect(btn).toBeDefined();
    await btn!.trigger("click");
    expect(mockLive.pushEvent).toHaveBeenCalledWith("generate_technical_id", {});
  });

  it("audio select / clear push update_node_field with audio_asset_id", async () => {
    const audioAssets = [{ id: 7, filename: "scream.mp3", url: "/x.mp3" }];
    const data = makeData({ audioAssetId: 7, audioAssets, responses: [] });
    const w = mountIt({ data });

    const audioComponent = w.findComponent({ name: "AudioAsset" });
    expect(audioComponent.exists()).toBe(true);
    audioComponent.vm.$emit("select", audioAssets[0]);
    expect(mockLive.pushEvent).toHaveBeenCalledWith("update_node_field", {
      field: "audio_asset_id",
      value: 7,
    });

    audioComponent.vm.$emit("clear");
    expect(mockLive.pushEvent).toHaveBeenCalledWith("update_node_field", {
      field: "audio_asset_id",
      value: null,
    });
  });

  it("localization id copy button only renders when value is non-empty", () => {
    const empty = mountIt();
    const noCopy = empty
      .findAll("button")
      .find((b) => /copy to clipboard|copiar al portapapeles/i.test(b.attributes("title") || ""));
    expect(noCopy).toBeUndefined();

    const data = makeData({ localizationId: "dialogue.abc123", responses: [] });
    const withId = mountIt({ data });
    const copyBtn = withId
      .findAll("button")
      .find((b) => /copy to clipboard|copiar al portapapeles/i.test(b.attributes("title") || ""));
    expect(copyBtn).toBeDefined();
  });

  it("footer renders pluralised word count (1 word vs N words)", () => {
    const w1 = mountIt({ data: makeData({ text: "<p>Hi</p>", responses: [] }) });
    expect(w1.text()).toContain("1 word");

    const w5 = mountIt({
      data: makeData({ text: "<p>The quick brown fox jumps</p>", responses: [] }),
    });
    expect(w5.text()).toContain("5 words");
  });

  it("footer shows 'Audio attached' label only when audioAssetId is set", () => {
    const noAudio = mountIt();
    expect(noAudio.text()).not.toContain("Audio attached");

    const withAudio = mountIt({ data: makeData({ audioAssetId: 7, responses: [] }) });
    expect(withAudio.text()).toContain("Audio attached");
  });

  // -- Phase 3: PropsSerializer / camelCase shape regression guard --

  it("renders nothing inside Tabs when `data` is null (panel closed state)", () => {
    const w = mountIt({ data: undefined });
    // The `<div v-if="data">` wrapper is absent; Tabs not rendered.
    expect(w.findComponent({ name: "Tabs" }).exists()).toBe(false);
  });
});
