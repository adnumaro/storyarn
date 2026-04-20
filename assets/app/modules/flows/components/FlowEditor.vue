<script setup lang="ts">
import { onMounted, ref, watch } from "vue";
import { useLive } from "@composables/useLive";
import { useFlowEditor } from "../composables/useFlowEditor";
import FlowCursors from "./FlowCursors.vue";
import FlowMinimapToggle from "./FlowMinimapToggle.vue";

const {
  flowData = null,
  variableMap = null,
  loading = true,
  readonly = false,
  userId = 0,
  userColor = "#3b82f6",
  canvasId = "flow-canvas",
  toolbarData = "{}",
} = defineProps<{
  flowData: string | null;
  variableMap: string | null;
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

const { init, toolbarState, editor, area, setToolbarProps } = useFlowEditor({
  pushEvent: live.pushEvent,
  handleEvent: live.handleEvent,
});

async function initCanvas() {
  if (initialized || !containerRef.value || !flowData) return;
  initialized = true;

  const parsedFlowData = JSON.parse(flowData);
  const parsedSheetsMap = variableMap ? JSON.parse(variableMap) : {};

  await init(containerRef.value, parsedFlowData, {
    sheetsMap: parsedSheetsMap,
    readonly,
    userId: Number(userId),
    userColor,
  });

  setToolbarProps(safeParse(toolbarData));
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

watch(
  () => toolbarData,
  (val) => setToolbarProps(safeParse(val)),
  { immediate: true },
);
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

    <FlowCursors
      v-if="!readonly && area"
      :area-transform="area?.area?.transform || { x: 0, y: 0, k: 1 }"
      :current-user-id="userId"
      :container-el="containerRef"
    />

    <FlowMinimapToggle v-if="area && editor" :area="area" :editor="editor" />
  </div>
</template>
