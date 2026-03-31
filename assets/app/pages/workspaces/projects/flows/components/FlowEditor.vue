<script setup>
import { onMounted, ref, watch } from "vue";
import { useLive } from "@composables/useLive.js";
import { useFlowEditor } from "../composables/useFlowEditor.js";
import FlowContextMenu from "./FlowContextMenu.vue";
import FlowCursors from "./FlowCursors.vue";
import FlowFloatingToolbar from "./FlowFloatingToolbar.vue";
import FlowMinimapToggle from "./FlowMinimapToggle.vue";

const props = defineProps({
  flowData: { type: String, default: null },
  sheetsMap: { type: String, default: null },
  labels: { type: String, default: "{}" },
  loading: { type: Boolean, default: true },
  readonly: { type: Boolean, default: false },
  userId: { type: [Number, String], default: 0 },
  userColor: { type: String, default: "#3b82f6" },
  canvasId: { type: String, default: "flow-canvas" },
  // Toolbar server data (JSON strings)
  flowHubs: { type: String, default: "[]" },
  availableFlows: { type: String, default: "[]" },
  allSheets: { type: String, default: "[]" },
  availableScenes: { type: String, default: "[]" },
  subflowExits: { type: String, default: "[]" },
  referencingJumps: { type: String, default: "[]" },
  referencingFlows: { type: String, default: "[]" },
  nodeSelectLoading: { type: Boolean, default: false },
  flowSearchHasMore: { type: Boolean, default: false },
});

const containerRef = ref(null);
const live = useLive();
let initialized = false;

const { init, toolbarState, editor, area } = useFlowEditor({
  pushEvent: live.pushEvent,
  handleEvent: live.handleEvent,
});

async function initCanvas() {
  if (initialized || !containerRef.value || !props.flowData) return;
  initialized = true;

  const flowData = JSON.parse(props.flowData);
  const sheetsMap = props.sheetsMap ? JSON.parse(props.sheetsMap) : {};
  const labels = JSON.parse(props.labels);

  await init(containerRef.value, flowData, {
    sheetsMap,
    labels,
    readonly: props.readonly,
    userId: Number(props.userId),
    userColor: props.userColor,
  });
}

watch(
  () => props.flowData,
  (val) => {
    if (val && !initialized) initCanvas();
  },
);

onMounted(() => {
  if (props.flowData) initCanvas();
});

function safeParse(json) {
  try {
    return JSON.parse(json);
  } catch {
    return [];
  }
}
</script>

<template>
  <div
    v-if="loading"
    class="w-full h-full flex items-center justify-center text-muted-foreground text-sm"
  >
    Loading...
  </div>
  <div v-show="!loading" class="w-full h-full relative">
    <div ref="containerRef" :id="canvasId" class="w-full h-full" />

    <FlowFloatingToolbar
      v-if="!readonly"
      :toolbar-state="toolbarState"
      :can-edit="!readonly"
      :flow-hubs="safeParse(flowHubs)"
      :available-flows="safeParse(availableFlows)"
      :all-sheets="safeParse(allSheets)"
      :available-scenes="safeParse(availableScenes)"
      :subflow-exits="safeParse(subflowExits)"
      :referencing-jumps="safeParse(referencingJumps)"
      :referencing-flows="safeParse(referencingFlows)"
      :node-select-loading="nodeSelectLoading"
      :flow-search-has-more="flowSearchHasMore"
    />

    <FlowContextMenu
      :container-el="containerRef"
      :can-edit="!readonly"
      :selected-node-id="toolbarState.nodeId"
      :selected-node-type="toolbarState.nodeType"
    />

    <FlowCursors
      v-if="!readonly && area"
      :area-transform="area?.area?.transform || { x: 0, y: 0, k: 1 }"
      :current-user-id="userId"
      :container-el="containerRef"
    />

    <FlowMinimapToggle v-if="area && editor" :area="area" :editor="editor" />
  </div>
</template>
