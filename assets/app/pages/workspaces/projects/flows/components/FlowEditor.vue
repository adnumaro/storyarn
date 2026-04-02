<script setup>
import { onMounted, ref, watch } from "vue";
import { useLive } from "@composables/useLive.js";
import { useFlowEditor } from "../composables/useFlowEditor.js";
import FlowContextMenu from "./FlowContextMenu.vue";
import FlowCursors from "./FlowCursors.vue";
import FlowFloatingToolbar from "./FlowFloatingToolbar.vue";
import FlowMinimapToggle from "./FlowMinimapToggle.vue";

const { flowData, variableMap, labels, loading, readonly, userId, userColor, canvasId, toolbarData } = defineProps({
  flowData: { type: String, default: null },
  variableMap: { type: String, default: null },
  labels: { type: String, default: "{}" },
  loading: { type: Boolean, default: true },
  readonly: { type: Boolean, default: false },
  userId: { type: [Number, String], default: 0 },
  userColor: { type: String, default: "#3b82f6" },
  canvasId: { type: String, default: "flow-canvas" },
  toolbarData: { type: String, default: "{}" },
});

const containerRef = ref(null);
const live = useLive();
let initialized = false;

const { init, toolbarState, editor, area } = useFlowEditor({
  pushEvent: live.pushEvent,
  handleEvent: live.handleEvent,
});

async function initCanvas() {
  if (initialized || !containerRef.value || !flowData) return;
  initialized = true;

  const parsedFlowData = JSON.parse(flowData);
  const parsedSheetsMap = variableMap ? JSON.parse(variableMap) : {};
  const parsedLabels = JSON.parse(labels);

  await init(containerRef.value, parsedFlowData, {
    sheetsMap: parsedSheetsMap,
    labels: parsedLabels,
    readonly,
    userId: Number(userId),
    userColor,
  });
}

watch(
  () => flowData,
  (val) => {
    if (val && !initialized) initCanvas();
  },
);

onMounted(() => {
  if (flowData) initCanvas();
});

function safeParse(json, fallback = {}) {
  try {
    return JSON.parse(json);
  } catch {
    return fallback;
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
      v-bind="safeParse(toolbarData)"
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
