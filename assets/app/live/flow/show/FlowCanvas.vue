<script setup lang="ts">
import { onMounted, ref, watch } from "vue";
import { AreaExtensions } from "rete-area-plugin";
import { useLive } from "@shared/composables/useLive";
import { registerPaletteCommands } from "@shared/command-palette/registry";
import { useFlowCanvas } from "@modules/flows/editor/composables/useFlowCanvas";
import FlowCursors from "@modules/flows/editor/components/chrome/FlowCursors.vue";
import FlowMinimapToggle from "@modules/flows/editor/components/chrome/FlowMinimapToggle.vue";
import FlowCanvasComments from "@modules/flows/editor/components/chrome/FlowCanvasComments.vue";
import type { FlowCommentsPanelState, FlowCommentThread } from "@modules/flows/types/comments";
import type { FlowNodeLock } from "@modules/flows/editor/services/editorHandlers";

interface CanvasComments {
  state: FlowCommentsPanelState;
  pins: FlowCommentThread[];
  focusThreadId: number | null;
}

/** The collaborator looking at this canvas: their id and cursor colour. */
interface CanvasViewer {
  id: number | string;
  color: string;
}

const {
  flowData = null,
  variableMap = null,
  loading = true,
  readonly = false,
  viewer = { id: 0, color: "#3b82f6" },
  canvasId = "flow-canvas",
  toolbarData = "{}",
  comments = null,
  fitViewRequest = 0,
  nodeLocks = {},
} = defineProps<{
  flowData: string | null;
  variableMap: string | null;
  loading: boolean;
  readonly: boolean;
  viewer: CanvasViewer;
  canvasId: string;
  toolbarData: string;
  comments?: CanvasComments | null;
  fitViewRequest?: number;
  nodeLocks?: Record<string, FlowNodeLock>;
}>();

const containerRef = ref<HTMLElement | null>(null);
const live = useLive();
let initialized = false;
const canvasReady = ref(false);
// Rete mutates its transform in place; mirror it so overlays re-render on pan and zoom.
const viewTransform = ref({ x: 0, y: 0, k: 1 });

const { init, editor, area, setToolbarProps, setCommentCounts, setNodeLocks } = useFlowCanvas({
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
    userId: Number(viewer.id),
    userColor: viewer.color,
    commentsEnabled: comments != null,
    skipInitialFit: comments?.focusThreadId != null,
  });

  canvasReady.value = true;
  trackViewTransform();
  setToolbarProps(safeParse(toolbarData));
  setCommentCounts({}, comments != null);
  setNodeLocks(nodeLocks, Number(viewer.id));
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
  () => nodeLocks,
  (locks) => setNodeLocks(locks, Number(viewer.id)),
);

watch(
  () => toolbarData,
  (val) => setToolbarProps(safeParse(val)),
  { immediate: true },
);
watch(
  () => fitViewRequest,
  () =>
    requestAnimationFrame(() => {
      const nodes = editor.value?.getNodes() ?? [];
      if (containerRef.value?.isConnected && area.value && nodes.length > 0)
        void AreaExtensions.zoomAt(area.value, nodes);
    }),
);
function trackViewTransform(): void {
  const plugin = area.value;
  if (!plugin) return;
  viewTransform.value = { ...plugin.area.transform };
  plugin.addPipe((context) => {
    const type = (context as { type: string }).type;
    if (type === "translated" || type === "zoomed") {
      viewTransform.value = { ...plugin.area.transform };
    }
    return context;
  });
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
    {{ $t("common.loading") }}
  </div>
  <div v-show="!loading" class="w-full h-full relative">
    <div
      ref="containerRef"
      :id="canvasId"
      class="w-full h-full"
      :data-user-id="viewer.id"
      :data-user-color="viewer.color"
    />

    <FlowCursors
      v-if="!readonly && area"
      :area-transform="viewTransform"
      :current-user-id="viewer.id"
      :container-el="containerRef"
    />

    <FlowCanvasComments
      v-if="canvasReady && area && containerRef && comments"
      :area="area"
      :container="containerRef"
      :state="comments.state"
      :comment-pins="comments.pins"
      :focus-thread-id="comments.focusThreadId"
      :draft-storage-key="`storyarn:flow-comment-draft:${viewer.id}:${canvasId}`"
      :current-user-id="Number(viewer.id) || null"
    />

    <FlowMinimapToggle
      v-if="area && editor"
      :area="area"
      :editor="editor"
      :register-commands="registerPaletteCommands"
    />
  </div>
</template>
