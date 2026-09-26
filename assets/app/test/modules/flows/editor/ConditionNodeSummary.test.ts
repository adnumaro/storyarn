import { mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vitest";
import ConditionNode from "@modules/flows/editor/components/entities/nodes/ConditionNode.vue";
import { NODE_CONFIGS } from "@modules/flows/editor/lib/node-configs";
import { setTestLocale } from "../../../setup";

afterEach(() => setTestLocale("en"));

function mountCondition(nodeData: Record<string, unknown>) {
  return mount(ConditionNode, {
    props: {
      data: { id: "node-1", nodeType: "condition", nodeData, inputs: {}, outputs: {} } as never,
      emit: vi.fn(),
      config: NODE_CONFIGS.condition,
      color: "#8b5cf6",
    },
    global: { stubs: { Ref: true } },
  });
}

describe("ConditionNode summary in Spanish", () => {
  it("reads a node the server just created, with no rules yet", () => {
    setTestLocale("es");

    expect(mountCondition({ condition: { logic: "all", rules: [] } }).text()).toContain(
      "Sin condición",
    );
    expect(
      mountCondition({ switch_mode: true, condition: { logic: "all", rules: [] } }).text(),
    ).toContain("Sin condiciones");
  });

  it("names a word operator with the builder's label", () => {
    setTestLocale("es");
    const rule = { id: "r1", sheet: "mara", variable: "brave", operator: "is_true", value: null };

    const text = mountCondition({ condition: { logic: "all", rules: [rule] } }).text();

    expect(text).toContain("mara.brave es verdadero");
    expect(text).not.toContain("is true");
  });
});
