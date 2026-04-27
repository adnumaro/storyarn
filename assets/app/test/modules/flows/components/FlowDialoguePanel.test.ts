import { describe, it, expect, vi, beforeEach } from "vitest";
import { mount } from "@vue/test-utils";
import { createMockLive } from "../../../setup";

const mockLive = createMockLive();

vi.mock("@composables/useLive", () => ({
  useLive: () => mockLive,
}));

const { default: FlowDialoguePanel } = await import(
  "@modules/flows/components/FlowDialoguePanel.vue"
);

interface NodeFixture {
  id: number | string;
  data: Record<string, unknown>;
}

const NODE: NodeFixture = {
  id: 36,
  data: {
    text: "",
    speaker_sheet_id: null,
    stage_directions: "",
    menu_text: "",
    technical_id: "",
    responses: [
      {
        id: "r1_abc",
        text: "Initial response",
        condition: null,
        instruction_assignments: [],
      },
    ],
  },
};

function mountIt(overrides: Partial<{ node: NodeFixture; canEdit: boolean }> = {}) {
  return mount(FlowDialoguePanel, {
    props: {
      open: true,
      node: NODE,
      canEdit: true,
      allSheets: [],
      projectVariables: [],
      ...overrides,
    },
    global: {
      stubs: {
        // TipTap pulls in heavy deps not relevant to wire-format tests.
        EditorContent: { template: "<div data-stub='tiptap' />" },
        // shadcn-vue's TabsContent (reka-ui Tabs) only mounts the active
        // tab's content. For wire-format tests we want every tab's children
        // visible at once so we can probe ConditionBuilder / InstructionBuilder
        // / "Add response" without juggling tab activation + nextTick.
        TabsContent: { template: "<div><slot /></div>" },
        // AudioAsset uses reka-ui Popover/Command which reach for
        // ResizeObserver (not defined in jsdom). The dialogue tests only
        // care about wire-format (which AudioAsset events trigger via
        // emits), so a passthrough stub keeps the surface alive.
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
    const addBtn = w
      .findAll("button")
      .find((b) => /add response|añadir respuesta/i.test(b.text()));
    expect(addBtn).toBeDefined();
    await addBtn!.trigger("click");

    expect(mockLive.pushEvent).toHaveBeenCalledWith("add_response", { "node-id": 36 });
  });

  it("remove_response sends response-id + node-id with hyphens", async () => {
    const w = mountIt();
    const removeBtn = w
      .findAll("button")
      .find((b) => /remove|eliminar|quitar/i.test(b.text()));
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
    // Defensive: the broken-old event name should NEVER fire.
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
    const node: NodeFixture = {
      id: 36,
      data: {
        responses: [
          {
            id: "r1_abc",
            text: "Hi",
            condition: JSON.stringify(conditionPayload),
          },
        ],
      },
    };
    const w = mountIt({ node });
    const builder = w.findComponent({ name: "ConditionBuilder" });
    expect(builder.props("condition")).toEqual(conditionPayload);
  });

  it("tolerates a non-stringified condition (defensive — old data shape)", () => {
    const node: NodeFixture = {
      id: 36,
      data: {
        responses: [
          {
            id: "r1_abc",
            text: "Hi",
            condition: { logic: "all", blocks: [] },
          },
        ],
      },
    };
    const w = mountIt({ node });
    const builder = w.findComponent({ name: "ConditionBuilder" });
    expect(builder.props("condition")).toEqual({ logic: "all", blocks: [] });
  });

  /**
   * Regression guard: V1's screenplay_editor.ex wraps each response's
   * condition + instruction in `<.expression_editor>` which exposes Builder
   * AND Code (CodeMirror IDE) tabs. V2 must use the equivalent
   * `<ExpressionEditor>` wrapper, NOT raw ConditionBuilder /
   * InstructionBuilder. If a future refactor inlines the builders again,
   * authors lose the Code tab silently — this test pins the wrapper.
   */
  it("wraps response condition + instruction in ExpressionEditor (not raw builders)", () => {
    const w = mountIt();
    const expressionEditors = w.findAllComponents({ name: "ExpressionEditor" });
    // One per (response × {condition, instruction}). With one response in
    // the fixture: 2 ExpressionEditors, one per mode.
    expect(expressionEditors.length).toBeGreaterThanOrEqual(2);
    const modes = expressionEditors.map((c) => c.props("mode"));
    expect(modes).toContain("condition");
    expect(modes).toContain("instruction");
  });

  // -- Phase 2: Settings tab parity (audio picker / generate-id /
  // localization copy / footer word count + audio attached label) --

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
    const node: NodeFixture = {
      id: 36,
      data: { audio_asset_id: 7, responses: [] },
    };
    const w = mountIt({ node });
    // Override audioAssets via props update
    await w.setProps({ audioAssets });

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
    // No localization_id → no copy button
    const empty = mountIt();
    const noCopy = empty
      .findAll("button")
      .find((b) => /copy to clipboard|copiar al portapapeles/i.test(b.attributes("title") || ""));
    expect(noCopy).toBeUndefined();

    // With localization_id → copy button shows
    const node: NodeFixture = {
      id: 36,
      data: {
        localization_id: "dialogue.abc123",
        responses: [],
      },
    };
    const withId = mountIt({ node });
    const copyBtn = withId
      .findAll("button")
      .find((b) => /copy to clipboard|copiar al portapapeles/i.test(b.attributes("title") || ""));
    expect(copyBtn).toBeDefined();
  });

  it("footer renders pluralised word count (1 word vs N words)", () => {
    // 0 / 1 / 2+ word case via the dialogue text + responses combined
    const oneWord: NodeFixture = {
      id: 36,
      data: { text: "<p>Hi</p>", responses: [] },
    };
    const w1 = mountIt({ node: oneWord });
    expect(w1.text()).toContain("1 word");

    const manyWords: NodeFixture = {
      id: 36,
      data: { text: "<p>The quick brown fox jumps</p>", responses: [] },
    };
    const w5 = mountIt({ node: manyWords });
    expect(w5.text()).toContain("5 words");
  });

  it("footer shows 'Audio attached' label only when audio_asset_id is set", () => {
    const noAudio = mountIt();
    expect(noAudio.text()).not.toContain("Audio attached");

    const node: NodeFixture = {
      id: 36,
      data: { audio_asset_id: 7, responses: [] },
    };
    const withAudio = mountIt({ node });
    expect(withAudio.text()).toContain("Audio attached");
  });
});
