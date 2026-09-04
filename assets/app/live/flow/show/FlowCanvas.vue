<script setup lang="ts">
import { onMounted, ref, watch } from "vue";
import { useLive } from "@shared/composables/useLive";
import { registerPaletteCommands } from "@shared/command-palette/registry";
import { useFlowCanvas } from "@modules/flows/editor/composables/useFlowCanvas";
import FlowCursors from "@modules/flows/editor/components/chrome/FlowCursors.vue";
import FlowMinimapToggle from "@modules/flows/editor/components/chrome/FlowMinimapToggle.vue";
import FlowCanvasComments from "@modules/flows/editor/components/chrome/FlowCanvasComments.vue";
import type { FlowCommentsPanelState, FlowCommentThread } from "@modules/flows/types/comments";

interface CanvasComments {
  state: FlowCommentsPanelState;
  pins: FlowCommentThread[];
  focusThreadId: number | null;
}

const {
  flowData = null,
  variableMap = null,
  loading = true,
  readonly = false,
  userId = 0,
  userColor = "#3b82f6",
  canvasId = "flow-canvas",
  toolbarData = "{}",
  comments = null,
} = defineProps<{
  flowData: string | null;
  variableMap: string | null;
  loading: boolean;
  readonly: boolean;
  userId: number | string;
  userColor: string;
  canvasId: string;
  toolbarData: string;
  comments?: CanvasComments | null;
}>();

const containerRef = ref<HTMLElement | null>(null);
const live = useLive();
let initialized = false;
const canvasReady = ref(false);

const { init, editor, area, setToolbarProps, setCommentCounts } = useFlowCanvas({
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
    skipInitialFit: comments?.focusThreadId != null,
  });

  canvasReady.value = true;
  setToolbarProps(safeParse(toolbarData));
  setCommentCounts({}, comments != null);
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
  () => comments != null,
  (enabled) => setCommentCounts({}, enabled),
);

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
    <div
      ref="containerRef"
      :id="canvasId"
      class="w-full h-full"
      :data-user-id="userId"
      :data-user-color="userColor"
    />

    <FlowCursors
      v-if="!readonly && area"
      :area-transform="area?.area?.transform || { x: 0, y: 0, k: 1 }"
      :current-user-id="userId"
      :container-el="containerRef"
    />

    <FlowCanvasComments
      v-if="canvasReady && area && containerRef && comments"
      :area="area"
      :container="containerRef"
      :state="comments.state"
      :comment-pins="comments.pins"
      :focus-thread-id="comments.focusThreadId"
    />

    <FlowMinimapToggle
      v-if="area && editor"
      :area="area"
      :editor="editor"
      :register-commands="registerPaletteCommands"
    />
  </div>
</template>
