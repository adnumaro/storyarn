import { mount } from "@vue/test-utils";
import { reactive } from "vue";
import { describe, expect, it, vi } from "vitest";
import FlowNode from "@modules/flows/editor/components/entities/rete/FlowNode.vue";
import SequenceNode from "@modules/flows/editor/components/entities/nodes/SequenceNode.vue";
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

function mountSequence(nodeLocks: Record<string, FlowNodeLock>) {
  const ctx = reactive({
    nodeLocks,
    nodeDataVersion: 0,
    selectedReteIds: new Set<string | number>(["node-9"]),
    canEdit: true,
    toolbarProps: {},
    zoom: 1,
  });

  return mount(SequenceNode, {
    props: {
      data: { id: "node-9", nodeType: "sequence", nodeData: { name: "Opening" } } as never,
    },
    global: {
      provide: { [FLOW_CONTEXT_KEY as symbol]: ctx },
      stubs: { FlowNodeToolbar: { template: "<div data-test='toolbar' />" } },
    },
  });
}

describe("SequenceNode collaboration lock", () => {
  it("shows who is editing a locked sequence and hides its toolbar and resize handle", () => {
    const wrapper = mountSequence({ "9": { userId: 2, name: "ana", color: "#e11d48" } });

    expect(wrapper.get("[data-flow-node-lock='9']").text()).toBe("ana");
    expect(wrapper.find("[data-test='toolbar']").exists()).toBe(false);
    expect(wrapper.find(".flow-sequence-resize-handle").exists()).toBe(false);
  });

  it("keeps its toolbar and resize handle when nobody else is editing it", () => {
    const wrapper = mountSequence({});

    expect(wrapper.find("[data-flow-node-lock]").exists()).toBe(false);
    expect(wrapper.find("[data-test='toolbar']").exists()).toBe(true);
    expect(wrapper.find(".flow-sequence-resize-handle").exists()).toBe(true);
  });
});
