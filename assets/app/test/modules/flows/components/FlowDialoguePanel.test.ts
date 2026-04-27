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
});
