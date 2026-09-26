import { mount } from "@vue/test-utils";
import { reactive } from "vue";
import { describe, expect, it, vi } from "vitest";
import FlowNode from "@modules/flows/editor/components/entities/rete/FlowNode.vue";
import { FLOW_CONTEXT_KEY } from "@modules/flows/editor/lib/flow-context";
import type { FlowNodeLock } from "@modules/flows/editor/services/editorHandlers";

function mountNode(nodeLocks: Record<string, FlowNodeLock>) {
  const ctx = reactive({
    nodeLocks,
    sheetsMap: {},
    hubsMap: {},
    lod: "full",
    nodeDataVersion: 0,
    selectedReteNodeId: "node-7",
    selectedReteIds: new Set<string | number>(["node-7"]),
    canEdit: true,
    toolbarProps: {},
  });

  return mount(FlowNode, {
    props: {
      data: { id: "node-7", nodeType: "hub", nodeData: { label: "Crossroads" } } as never,
      emit: vi.fn(),
    },
    global: {
      provide: { [FLOW_CONTEXT_KEY as symbol]: ctx },
      stubs: { HubNode: true, FlowNodeToolbar: { template: "<div data-test='toolbar' />" } },
    },
  });
}

describe("FlowNode collaboration lock", () => {
  it("shows who is editing a node locked by someone else and hides its toolbar", () => {
    const wrapper = mountNode({ "7": { userId: 2, name: "ana", color: "#e11d48" } });

    const badge = wrapper.get("[data-flow-node-lock='7']");
    expect(badge.text()).toBe("ana");
    expect(badge.attributes("aria-label")).toBe("ana is editing this node");
    expect(wrapper.find("[data-test='toolbar']").exists()).toBe(false);
  });

  it("shows the toolbar and no badge when the node is free", () => {
    const wrapper = mountNode({});

    expect(wrapper.find("[data-flow-node-lock]").exists()).toBe(false);
    expect(wrapper.find("[data-test='toolbar']").exists()).toBe(true);
  });
});
