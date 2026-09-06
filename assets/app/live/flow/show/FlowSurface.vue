<script setup lang="ts">
import { useLiveVue } from "live_vue";
import { computed, onMounted, onUnmounted, ref, watch } from "vue";
import FlowDock from "@modules/flows/editor/components/chrome/dock/FlowDock.vue";
import FlowCollabToast from "@modules/flows/editor/components/collab/CollabToast.vue";
import FlowDebugPanel from "@modules/flows/editor/components/panels/FlowDebugPanel.vue";
import FlowSequenceStage from "@modules/flows/editor/components/sequence/FlowSequenceStage.vue";
import type { SequenceStageState } from "@modules/flows/sequence/types";
import FlowCanvas from "./FlowCanvas.vue";
import type { FlowCommentsPanelState, FlowCommentThread } from "@modules/flows/types/comments";

interface FlowSurfaceCanvasData {
  key: string;
  flowData: string | null;
  variableMap: string | null;
  loading: boolean;
  readonly: boolean;
  userId: number | string;
  userColor: string;
  canvasId: string;
  toolbarData: string;
  commentPins?: FlowCommentThread[];
  comments?: FlowCommentsPanelState | null;
  commentFocusThreadId?: number | null;
}

interface FlowDockSurface {
  canEdit: boolean;
  compact: boolean;
  debugPanelOpen: boolean;
}

type FlowDebugPanelProps = InstanceType<typeof FlowDebugPanel>["$props"];

interface FlowDebugSurface {
  open: FlowDebugPanelProps["open"];
  state: FlowDebugPanelProps["state"];
  nodes: FlowDebugPanelProps["nodes"];
  controls: FlowDebugPanelProps["controls"];
}

interface FlowSurface {
  canvas: FlowSurfaceCanvasData;
  dock: FlowDockSurface;
  stage?: SequenceStageState;
  sequencePanelOpen?: boolean;
  debug?: FlowDebugSurface;
}

const { surface: initialSurface } = defineProps<{
  surface: FlowSurface;
}>();

const liveVue = useLiveVue();
// `v-inject` keeps this boundary alive while route diffs replace the surface payload.
const surface = computed(
  () => (liveVue.vue?.props?.surface as FlowSurface | undefined) ?? initialSurface,
);
const emptyStage: SequenceStageState = { status: "empty" };
const stage = computed(() => surface.value.stage ?? emptyStage);
const sequencePanelOpen = computed(() => Boolean(surface.value.sequencePanelOpen));
const debugOpen = computed(() => Boolean(surface.value.debug?.open && surface.value.debug.state));
const root = ref<HTMLElement | null>(null);
const visualEditorOpen = ref(false);
const splitPercent = ref(60);
const upperFullscreen = ref(false);
let resizing = false;

const comments = computed(() => {
  const canvas = surface.value.canvas;
  if (!canvas.comments) return null;
  return {
    state: canvas.comments,
    pins: canvas.commentPins ?? [],
    focusThreadId: canvas.commentFocusThreadId ?? null,
  };
});

function splitLimits(height: number) {
  if (height <= 0) return { min: 30, max: 82 };
  const min = Math.min(72, (280 / height) * 100);
  const max = Math.max(min, 100 - (240 / height) * 100);
  return { min, max };
}

function setSplitFromClientY(clientY: number) {
  if (!root.value) return;
  const bounds = root.value.getBoundingClientRect();
  const limits = splitLimits(bounds.height);
  const percent = ((clientY - bounds.top) / bounds.height) * 100;
  splitPercent.value = Math.min(limits.max, Math.max(limits.min, percent));
}

function onSplitterPointerDown(event: PointerEvent) {
  event.preventDefault();
  resizing = true;
  document.body.style.cursor = "row-resize";
  document.body.style.userSelect = "none";
  window.addEventListener("pointermove", onSplitterPointerMove);
  window.addEventListener("pointerup", stopSplitterResize, { once: true });
  window.addEventListener("pointercancel", stopSplitterResize, { once: true });
}

function onSplitterPointerMove(event: PointerEvent) {
  if (resizing) setSplitFromClientY(event.clientY);
}

function stopSplitterResize() {
  resizing = false;
  document.body.style.cursor = "";
  document.body.style.userSelect = "";
  window.removeEventListener("pointermove", onSplitterPointerMove);
  window.removeEventListener("pointerup", stopSplitterResize);
  window.removeEventListener("pointercancel", stopSplitterResize);
}

function onSplitterKeydown(event: KeyboardEvent) {
  if (!root.value || !["ArrowUp", "ArrowDown", "Home", "End"].includes(event.key)) return;
  event.preventDefault();
  const limits = splitLimits(root.value.getBoundingClientRect().height);

  if (event.key === "Home") splitPercent.value = limits.min;
  else if (event.key === "End") splitPercent.value = limits.max;
  else {
    const delta = event.key === "ArrowDown" ? 3 : -3;
    splitPercent.value = Math.min(limits.max, Math.max(limits.min, splitPercent.value + delta));
  }
}

function toggleUpperFullscreen() {
  upperFullscreen.value = !upperFullscreen.value;
}

function toggleVisualEditor() {
  visualEditorOpen.value = !visualEditorOpen.value;
  if (!visualEditorOpen.value) upperFullscreen.value = false;
}

function onDocumentKeydown(event: KeyboardEvent) {
  if (event.key === "Escape" && upperFullscreen.value) {
    event.preventDefault();
    upperFullscreen.value = false;
  }
}

watch(
  () => surface.value.canvas.key,
  () => {
    visualEditorOpen.value = false;
    upperFullscreen.value = false;
  },
);

onMounted(() => document.addEventListener("keydown", onDocumentKeydown));
onUnmounted(() => {
  stopSplitterResize();
  document.removeEventListener("keydown", onDocumentKeydown);
});
</script>

<template>
  <div ref="root" class="h-full min-h-0 relative flex flex-col bg-background">
    <div
      v-if="visualEditorOpen"
      data-flow-upper-workspace
      :class="[
        upperFullscreen ? 'fixed inset-0 z-[100] h-dvh bg-background' : 'relative min-h-0 shrink-0',
        !upperFullscreen && sequencePanelOpen ? 'md:pr-[24.75rem]' : undefined,
        'transition-[padding] duration-200 ease-out',
      ]"
      :style="upperFullscreen ? undefined : { height: `${splitPercent}%` }"
    >
      <FlowSequenceStage
        :stage="stage"
        :can-edit="surface.dock.canEdit && !surface.canvas.readonly"
        :fullscreen="upperFullscreen"
        @toggle-fullscreen="toggleUpperFullscreen"
      />
    </div>

    <div
      v-if="visualEditorOpen"
      v-show="!upperFullscreen"
      role="separator"
      aria-orientation="horizontal"
      :aria-label="$t('flows.sequence_stage.resize_split')"
      :aria-valuenow="Math.round(splitPercent)"
      aria-valuemin="0"
      aria-valuemax="100"
      tabindex="0"
      class="group relative z-40 h-2 shrink-0 cursor-row-resize touch-none bg-border/60 outline-none transition-colors hover:bg-primary/35 focus-visible:bg-primary/45"
      data-flow-splitter
      @pointerdown="onSplitterPointerDown"
      @keydown="onSplitterKeydown"
    >
      <span
        class="pointer-events-none absolute left-1/2 top-1/2 h-1 w-12 -translate-x-1/2 -translate-y-1/2 rounded-full bg-muted-foreground/35 transition-colors group-hover:bg-primary/70"
      />
    </div>

    <div
      v-show="!upperFullscreen"
      id="flow-lower-workspace"
      class="relative flex-1 min-h-0 overflow-hidden"
    >
      <div
        :key="surface.canvas.key"
        v-show="!debugOpen"
        class="absolute inset-0"
        data-flow-workspace="canvas"
      >
        <FlowCanvas
          :flow-data="surface.canvas.flowData"
          :variable-map="surface.canvas.variableMap"
          :loading="surface.canvas.loading"
          :readonly="surface.canvas.readonly"
          :user-id="surface.canvas.userId"
          :user-color="surface.canvas.userColor"
          :canvas-id="surface.canvas.canvasId"
          :toolbar-data="surface.canvas.toolbarData"
          :comments="comments"
        />

        <div id="flow-dock" class="contents">
          <FlowDock
            :can-edit="surface.dock.canEdit"
            :compact="surface.dock.compact"
            :debug-panel-open="surface.dock.debugPanelOpen"
            :visual-editor-open="visualEditorOpen"
            @toggle-visual-editor="toggleVisualEditor"
          />
        </div>
      </div>

      <div
        v-if="surface.debug"
        v-show="debugOpen"
        class="absolute inset-0"
        data-flow-workspace="debug"
      >
        <FlowDebugPanel
          embedded
          :open="surface.debug.open"
          :state="surface.debug.state"
          :nodes="surface.debug.nodes"
          :controls="surface.debug.controls"
        />
      </div>
    </div>

    <div id="flow-collab-toast" class="contents">
      <FlowCollabToast />
    </div>
  </div>
</template>
