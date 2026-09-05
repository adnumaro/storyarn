import { mount } from "@vue/test-utils";
import { defineComponent } from "vue";

const { default: FlowPanels } = await import("@app/live/flow/show/FlowPanels.vue");
type PanelsData = InstanceType<typeof FlowPanels>["$props"]["panels"];

const FlowSequenceConfigPanelStub = defineComponent({
  name: "FlowSequenceConfigPanel",
  props: ["open", "data", "canEdit"],
  template:
    '<div data-sequence-panel-stub="true" :data-open="open" :data-node-id="data?.node_id" :data-can-edit="canEdit" />',
});

function panelsData(): PanelsData {
  return {
    versions: {
      open: false,
      versions: [],
      namedVersions: [],
      autoVersions: [],
      hasMore: false,
      canNameVersion: false,
      currentVersionId: null,
      canEdit: true,
      restoreEnabled: true,
      loading: false,
    },
    builder: {
      open: false,
      nodeType: null,
      nodeId: null,
      condition: null,
      assignments: [],
      switchMode: false,
      projectVariables: "{}",
      canEdit: true,
    },
    dialogue: { open: false, data: null, canEdit: true },
    dialogueFullscreen: { open: false, data: null, canEdit: true },
    preview: {
      open: false,
      currentNode: null,
      responses: [],
      hasNext: false,
      hasHistory: false,
    },
  };
}

function mountPanels(panels: PanelsData) {
  return mount(FlowPanels, {
    props: { panels },
    global: {
      stubs: {
        FlowBuilderPanel: true,
        FlowCommentsPanel: true,
        FlowDialogueFullscreenEditor: true,
        FlowDialoguePanel: true,
        FlowPreview: true,
        FlowSequenceConfigPanel: FlowSequenceConfigPanelStub,
        FlowVersionHistoryPanel: true,
      },
    },
  });
}

describe("FlowPanels sequence contract", () => {
  it("keeps the editor mounted while a pre-sequence payload transitions to the new contract", async () => {
    const legacyPanels = panelsData();
    const wrapper = mountPanels(legacyPanels);
    const sequencePanel = wrapper.get("[data-sequence-panel-stub]");

    expect(sequencePanel.attributes("data-open")).toBe("false");
    expect(sequencePanel.attributes("data-can-edit")).toBe("false");

    await wrapper.setProps({
      panels: {
        ...legacyPanels,
        sequence: {
          open: true,
          data: { node_id: 42 },
          canEdit: true,
        },
      },
    });

    expect(sequencePanel.attributes("data-open")).toBe("true");
    expect(sequencePanel.attributes("data-node-id")).toBe("42");
    expect(sequencePanel.attributes("data-can-edit")).toBe("true");
    wrapper.unmount();
  });
});
