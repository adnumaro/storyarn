<script setup lang="ts">
import { onMounted, ref, watch } from "vue";
import { useLive } from "@composables/useLive";
import { useFlowEditor } from "../composables/useFlowEditor";
import FlowContextMenu from "./FlowContextMenu.vue";
import FlowCursors from "./FlowCursors.vue";
import FlowFloatingToolbar from "./FlowFloatingToolbar.vue";
import FlowMinimapToggle from "./FlowMinimapToggle.vue";

const {
  flowData = null,
  variableMap = null,
  labels = "{}",
  loading = true,
  readonly = false,
  userId = 0,
  userColor = "#3b82f6",
  canvasId = "flow-canvas",
  toolbarData = "{}",
} = defineProps<{
  flowData: string | null;
  variableMap: string | null;
  labels: string;
  loading: boolean;
  readonly: boolean;
  userId: number | string;
  userColor: string;
  canvasId: string;
  toolbarData: string;
}>();

const containerRef = ref<HTMLElement | null>(null);
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

interface ToolbarExtraProps {
  hubs?: { id: string; label: string; color_hex?: string }[];
  projectFlows?: { id: number; name: string }[];
  sheetAvatars?: {
    id: number;
    name: string;
    avatars?: { id: number; name: string; asset?: { url: string } }[];
  }[];
  subflowExits?: { id: number; label?: string; exit_mode?: string }[];
  referencingJumps?: { node_id: number | string; label?: string }[];
  referencingFlows?: { id: number | string; name: string }[];
}

function safeParse(json: string, fallback: Record<string, unknown> = {}): Record<string, unknown> {
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
