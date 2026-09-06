<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from "vue";
import {
  Layers,
  Maximize2,
  Minimize2,
  MoveDiagonal2,
  PanelRightOpen,
  Scan,
  TriangleAlert,
  ZoomIn,
  ZoomOut,
} from "@lucide/vue";
import { Avatar, AvatarFallback, AvatarImage } from "@components/ui/avatar";
import { Badge } from "@components/ui/badge";
import { Button } from "@components/ui/button";
import { useLive } from "@shared/composables/useLive";
import SequenceVisualLayers from "@modules/flows/sequence/components/SequenceVisualLayers.vue";
import { compareSequenceLayers } from "@modules/flows/sequence/layerOrder";
import type { SequenceStageState, SequenceVisualLayer } from "@modules/flows/sequence/types";
import { useSequenceStageManipulation } from "../../composables/useSequenceStageManipulation";
import {
  clamp,
  layerFrameStyle,
  RESIZE_CORNERS,
  RESIZE_SIDES,
} from "../../lib/sequence-stage-geometry";
import {
  parseSequenceLibraryImage,
  SEQUENCE_LIBRARY_IMAGE_MIME,
  type SequenceLibraryImage,
} from "./sequence-library";

const {
  stage,
  canEdit = false,
  fullscreen = false,
  embedded = false,
  selectedLayerKey: selectedLayerKeyProp,
  lockedLayerKeys = [],
} = defineProps<{
  stage: SequenceStageState;
  canEdit?: boolean;
  fullscreen?: boolean;
  embedded?: boolean;
  selectedLayerKey?: string | null;
  lockedLayerKeys?: string[];
}>();

const emit = defineEmits<{
  "toggle-fullscreen": [];
  "update:selectedLayerKey": [key: string | null];
  "add-image": [payload: { image: SequenceLibraryImage; x: number; y: number }];
}>();

const live = useLive();
const viewport = ref<HTMLElement | null>(null);
const canvas = ref<HTMLElement | null>(null);
const localSelection = ref<string | null>(null);
const selectedLayerKey = computed(() =>
  selectedLayerKeyProp === undefined ? localSelection.value : selectedLayerKeyProp,
);
function setSelection(key: string | null) {
  localSelection.value = key;
  emit("update:selectedLayerKey", key);
}
const { canManipulate, displayLayers, layerKey, isLocked, startPointer, nudge, cancel } =
  useSequenceStageManipulation({
    stage: () => stage,
    canEdit: () => canEdit,
    selectedKey: () => selectedLayerKey.value,
    select: setSelection,
    lockedKeys: () => lockedLayerKeys,
    viewport,
    live,
  });
const intervention = computed(() => stage.intervention ?? null);
const owner = computed(() => stage.owner ?? null);
const interactiveLayers = computed(() =>
  [...displayLayers.value]
    .filter((layer) => layer.visible !== false && Boolean(layer.url?.trim()))
    .sort(compareSequenceLayers),
);
const diagnostics = computed(() => stage.composition?.diagnostics ?? []);
const hasVisibleLayers = computed(() => interactiveLayers.value.length > 0);
const speakerInitials = computed(() => {
  if (intervention.value?.speakerInitials) return intervention.value.speakerInitials;
  const name = intervention.value?.speakerName?.trim();
  if (!name) return "?";
  return name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0])
    .join("")
    .toUpperCase();
});
watch(
  () => stage.composition?.layers ?? [],
  (layers) => {
    if (
      selectedLayerKey.value &&
      !layers.some((layer) => layerKey(layer) === selectedLayerKey.value)
    )
      setSelection(null);
  },
);
function openInspector() {
  if (owner.value) live.pushEvent("open_sequence_config", { id: owner.value.nodeId });
}
function selectLayer(layer: SequenceVisualLayer) {
  if (!isLocked(layer)) setSelection(layerKey(layer));
}
function clearSelection() {
  cancel();
  setSelection(null);
}

const zoom = ref(1);
const pan = ref({ x: 0, y: 0 });
const fittedWidth = ref(0);
const spaceHeld = ref(false);
let observer: ResizeObserver | null = null;
let panGesture: {
  x: number;
  y: number;
  initialX: number;
  initialY: number;
  pointerId: number;
} | null = null;
const viewStyle = computed(() => ({
  width: fittedWidth.value > 0 ? `${fittedWidth.value}px` : "80%",
  transform: `translate(-50%, -50%) translate(${pan.value.x}px, ${pan.value.y}px) scale(${zoom.value})`,
}));
function fitView() {
  cancel();
  zoom.value = 1;
  pan.value = { x: 0, y: 0 };
}
function changeZoom(amount: number) {
  cancel();
  zoom.value = clamp(zoom.value + amount, 0.25, 3);
}
function wheelZoom(event: WheelEvent) {
  if (!event.ctrlKey && !event.metaKey) return;
  event.preventDefault();
  changeZoom(event.deltaY < 0 ? 0.1 : -0.1);
}
function startPan(event: PointerEvent) {
  if (event.button !== 1 && !(event.button === 0 && spaceHeld.value)) return;
  event.preventDefault();
  event.stopPropagation();
  cancel();
  panGesture = {
    x: event.clientX,
    y: event.clientY,
    initialX: pan.value.x,
    initialY: pan.value.y,
    pointerId: event.pointerId,
  };
  window.addEventListener("pointermove", movePan);
  window.addEventListener("pointerup", endPan);
  window.addEventListener("pointercancel", cancelPan);
}
function movePan(event: PointerEvent) {
  if (panGesture && panGesture.pointerId === event.pointerId) {
    pan.value = {
      x: panGesture.initialX + event.clientX - panGesture.x,
      y: panGesture.initialY + event.clientY - panGesture.y,
    };
  }
}
function endPan(event?: PointerEvent) {
  if (event && panGesture?.pointerId !== event.pointerId) return;
  window.removeEventListener("pointermove", movePan);
  window.removeEventListener("pointerup", endPan);
  window.removeEventListener("pointercancel", cancelPan);
  panGesture = null;
}
function cancelPan(event?: PointerEvent) {
  if (event && panGesture?.pointerId !== event.pointerId) return;
  if (panGesture) pan.value = { x: panGesture.initialX, y: panGesture.initialY };
  endPan();
}
function viewKeydown(event: KeyboardEvent) {
  if (event.key === " " && !(event.target as HTMLElement).closest("[data-sequence-view-tools]")) {
    event.preventDefault();
    spaceHeld.value = true;
  } else if (event.key === "Escape") {
    cancelPan();
    cancel();
  }
}
function releaseSpace(event?: KeyboardEvent) {
  if (!event || event.key === " ") spaceHeld.value = false;
}
function blurView() {
  releaseSpace();
  cancelPan();
}
function allowDrop(event: DragEvent) {
  if (!canManipulate.value || !event.dataTransfer?.types.includes(SEQUENCE_LIBRARY_IMAGE_MIME))
    return;
  event.preventDefault();
  event.dataTransfer.dropEffect = "copy";
}
function dropImage(event: DragEvent) {
  if (!canManipulate.value || !viewport.value) return;
  const image = parseSequenceLibraryImage(
    event.dataTransfer?.getData(SEQUENCE_LIBRARY_IMAGE_MIME) ?? "",
  );
  if (!image) return;
  const bounds = viewport.value.getBoundingClientRect();
  if (bounds.width <= 0 || bounds.height <= 0) return;
  event.preventDefault();
  emit("add-image", {
    image,
    x: clamp((event.clientX - bounds.left) / bounds.width, -10, 10),
    y: clamp((event.clientY - bounds.top) / bounds.height, -10, 10),
  });
}
onMounted(() => {
  if (canvas.value && typeof ResizeObserver !== "undefined") {
    observer = new ResizeObserver(([entry]) => {
      if (!entry) return;
      cancel();
      fittedWidth.value = Math.max(
        1,
        Math.min(entry.contentRect.width - 64, ((entry.contentRect.height - 48) * 16) / 9),
      );
    });
    observer.observe(canvas.value);
  }
  window.addEventListener("keyup", releaseSpace);
  window.addEventListener("blur", blurView);
});
watch(
  () => owner.value?.nodeId,
  () => {
    cancelPan();
    fitView();
  },
);
onUnmounted(() => {
  observer?.disconnect();
  endPan();
  window.removeEventListener("keyup", releaseSpace);
  window.removeEventListener("blur", blurView);
});
</script>

<template>
  <section
    id="flow-sequence-stage"
    class="h-full min-h-0 bg-muted/20 flex flex-col"
    :data-status="stage.status"
  >
    <header
      v-if="!embedded"
      class="min-h-9 shrink-0 px-3 py-1.5 flex flex-wrap items-center gap-2 border-b border-border/70 bg-background/80"
    >
      <Layers class="size-3.5 text-muted-foreground" />
      <h2 class="text-xs font-semibold tracking-wide">
        {{ $t("flows.sequence_stage.title") }}
      </h2>
      <Badge variant="outline" class="h-5 px-1.5 text-[10px] font-normal text-muted-foreground">
        {{ $t("flows.sequence_stage.static_preview") }}
      </Badge>
      <div class="ml-auto flex items-center gap-1.5">
        <span
          v-if="diagnostics.length > 0"
          class="inline-flex items-center gap-1 text-[11px] text-amber-600 dark:text-amber-400"
          data-sequence-diagnostics
        >
          <TriangleAlert class="size-3.5" />
          {{ $t("flows.sequence_stage.diagnostics", { count: diagnostics.length }) }}
        </span>
        <Button
          v-if="owner"
          type="button"
          variant="ghost"
          size="sm"
          class="h-7 gap-1.5 px-2 text-xs"
          :title="$t('flows.sequence_stage.open_inspector')"
          :aria-label="$t('flows.sequence_stage.open_inspector')"
          data-open-sequence-inspector
          @click="openInspector"
        >
          <PanelRightOpen class="size-3.5" />
          <span>{{ $t("flows.sequence_stage.edit_composition") }}</span>
        </Button>
        <Button
          type="button"
          variant="ghost"
          size="icon-xs"
          :title="
            fullscreen
              ? $t('flows.sequence_stage.exit_fullscreen')
              : $t('flows.sequence_stage.fullscreen')
          "
          :aria-label="
            fullscreen
              ? $t('flows.sequence_stage.exit_fullscreen')
              : $t('flows.sequence_stage.fullscreen')
          "
          data-toggle-sequence-fullscreen
          @click="emit('toggle-fullscreen')"
        >
          <Minimize2 v-if="fullscreen" class="size-3.5" />
          <Maximize2 v-else class="size-3.5" />
        </Button>
      </div>
    </header>

    <div
      ref="canvas"
      class="relative flex-1 min-h-0 overflow-hidden outline-none bg-muted/40"
      :class="spaceHeld ? 'cursor-grab' : undefined"
      tabindex="0"
      data-sequence-canvas
      @pointerdown.capture="startPan"
      @pointerdown.self="clearSelection"
      @keydown="viewKeydown"
      @wheel="wheelZoom"
      @dragover="allowDrop"
      @drop="dropImage"
    >
      <div
        ref="viewport"
        data-sequence-frame
        class="flow-sequence-viewport absolute left-1/2 top-1/2 aspect-video border border-border/80 bg-background shadow-sm"
        :style="viewStyle"
        @pointerdown.self="clearSelection"
      >
        <SequenceVisualLayers v-if="stage.status === 'ready'" :layers="displayLayers" />
        <div
          class="sequence-frame-outline pointer-events-none absolute inset-0 z-30"
          aria-hidden="true"
          data-sequence-frame-outline
        />

        <div
          v-if="canManipulate"
          class="pointer-events-none absolute inset-0 z-10"
          data-sequence-layer-controls
        >
          <button
            v-for="(layer, stackIndex) in interactiveLayers"
            :key="layerKey(layer)"
            type="button"
            class="absolute cursor-move touch-none border border-transparent outline-none transition-[border-color,box-shadow] hover:border-primary/60 focus-visible:border-primary focus-visible:ring-2 focus-visible:ring-primary/40"
            :class="[
              isLocked(layer) ? 'pointer-events-none' : 'pointer-events-auto',
              selectedLayerKey === layerKey(layer)
                ? 'border-primary shadow-[inset_0_0_0_1px_hsl(var(--primary))]'
                : undefined,
            ]"
            :tabindex="isLocked(layer) ? -1 : 0"
            :aria-disabled="isLocked(layer) || undefined"
            :style="layerFrameStyle(layer, stackIndex)"
            :aria-label="
              $t('flows.sequence_stage.select_layer', {
                name: layer.label || layer.kind,
              })
            "
            :data-layer-control="layerKey(layer)"
            :data-selected="selectedLayerKey === layerKey(layer) || undefined"
            @click="selectLayer(layer)"
            @pointerdown="startPointer($event, layer)"
            @keydown="nudge($event, layer)"
          >
            <span
              v-if="selectedLayerKey === layerKey(layer)"
              class="absolute left-0 top-0 inline-flex max-w-full -translate-y-full items-center gap-1 rounded-t bg-primary px-1.5 py-0.5 text-[9px] font-medium text-primary-foreground"
              aria-hidden="true"
            >
              <MoveDiagonal2 class="size-2.5" />
              <span class="truncate">{{ layer.label || layer.kind }}</span>
            </span>
            <template v-if="selectedLayerKey === layerKey(layer) && !isLocked(layer)">
              <span
                v-for="corner in RESIZE_CORNERS"
                :key="corner"
                class="absolute size-2.5 rounded-[2px] border border-primary bg-background shadow-sm"
                :class="[
                  corner.startsWith('n') ? 'top-0 -translate-y-1/2' : 'bottom-0 translate-y-1/2',
                  corner.endsWith('w') ? 'left-0 -translate-x-1/2' : 'right-0 translate-x-1/2',
                  corner === 'nw' || corner === 'se' ? 'cursor-nwse-resize' : 'cursor-nesw-resize',
                ]"
                aria-hidden="true"
                :title="
                  $t('flows.sequence_stage.resize_layer', { name: layer.label || layer.kind })
                "
                :data-layer-resize-handle="corner"
                @pointerdown="startPointer($event, layer, corner)"
              />
              <span
                v-for="side in RESIZE_SIDES"
                :key="side"
                class="absolute rounded-[2px] border border-primary bg-background shadow-sm"
                :class="[
                  side === 'n' || side === 's'
                    ? 'left-1/2 h-1.5 w-3 -translate-x-1/2 cursor-ns-resize'
                    : 'top-1/2 h-3 w-1.5 -translate-y-1/2 cursor-ew-resize',
                  {
                    'top-0 -translate-y-1/2': side === 'n',
                    'bottom-0 translate-y-1/2': side === 's',
                    'left-0 -translate-x-1/2': side === 'w',
                    'right-0 translate-x-1/2': side === 'e',
                  },
                ]"
                aria-hidden="true"
                :title="
                  $t('flows.sequence_stage.resize_layer', { name: layer.label || layer.kind })
                "
                :data-layer-resize-handle="side"
                @pointerdown="startPointer($event, layer, side)"
              />
            </template>
          </button>
        </div>

        <div
          v-if="stage.status === 'empty'"
          class="absolute inset-0 z-10 grid place-items-center px-6 text-center sequence-stage-grid"
        >
          <div class="max-w-sm">
            <span
              class="mx-auto mb-3 grid size-10 place-items-center rounded-lg border border-border bg-background text-muted-foreground shadow-sm"
            >
              <Layers class="size-5" />
            </span>
            <p class="text-sm font-medium">{{ $t("flows.sequence_stage.empty_title") }}</p>
            <p class="mt-1 text-xs leading-relaxed text-muted-foreground">
              {{ $t("flows.sequence_stage.empty_description") }}
            </p>
          </div>
        </div>

        <div
          v-else-if="stage.status === 'error'"
          class="absolute inset-0 z-10 grid place-items-center px-6 text-center sequence-stage-grid"
          role="status"
        >
          <div class="max-w-sm">
            <span
              class="mx-auto mb-3 grid size-10 place-items-center rounded-lg border border-destructive/30 bg-destructive/10 text-destructive"
            >
              <TriangleAlert class="size-5" />
            </span>
            <p class="text-sm font-medium">{{ $t("flows.sequence_stage.error_title") }}</p>
            <p class="mt-1 text-xs leading-relaxed text-muted-foreground">
              {{ stage.errorMessage || $t("flows.sequence_stage.error_description") }}
            </p>
          </div>
        </div>

        <div
          v-else-if="!hasVisibleLayers"
          class="absolute inset-0 z-0 grid place-items-center px-6 text-center text-xs text-muted-foreground sequence-stage-grid"
          data-sequence-empty-composition
        >
          <div class="flex max-w-sm flex-col items-center gap-3">
            <p>{{ $t("flows.sequence_stage.no_layers") }}</p>
            <Button
              v-if="owner && canEdit && !embedded"
              type="button"
              size="sm"
              class="gap-1.5"
              data-empty-sequence-inspector
              @click="openInspector"
            >
              <PanelRightOpen class="size-3.5" />
              {{ $t("flows.sequence_stage.edit_composition") }}
            </Button>
          </div>
        </div>

        <div
          v-if="stage.status === 'ready' && intervention"
          class="pointer-events-none absolute inset-x-0 bottom-0 z-20 border-t border-white/10 bg-slate-950/88 px-4 py-3 text-slate-100 backdrop-blur-sm"
          data-sequence-intervention
        >
          <div class="mx-auto flex max-w-3xl items-start gap-3">
            <Avatar class="size-9 shrink-0 border border-white/15">
              <AvatarImage
                v-if="intervention.speakerAvatarUrl"
                :src="intervention.speakerAvatarUrl"
                :alt="intervention.speakerName || ''"
              />
              <AvatarFallback
                class="text-xs font-semibold text-white"
                :style="
                  intervention.speakerColor
                    ? { backgroundColor: intervention.speakerColor }
                    : undefined
                "
              >
                {{ speakerInitials }}
              </AvatarFallback>
            </Avatar>

            <div class="min-w-0 flex-1">
              <p class="text-xs font-semibold text-white">
                {{ intervention.speakerName || $t("flows.sequence_stage.narrator") }}
              </p>
              <!-- eslint-disable-next-line vue/no-v-html -->
              <div
                v-if="intervention.text"
                class="mt-0.5 line-clamp-2 text-xs leading-relaxed text-slate-200 [&_p]:inline"
                v-html="intervention.text"
              />
              <p
                v-if="intervention.stageDirections"
                class="mt-1 truncate text-[11px] italic text-slate-400"
              >
                {{ intervention.stageDirections }}
              </p>
            </div>
          </div>
        </div>
      </div>
      <div
        class="absolute bottom-2 left-2 z-30 flex items-center gap-0.5 rounded-md border border-border bg-background/95 p-0.5 shadow-sm"
        data-sequence-view-tools
      >
        <Button
          type="button"
          variant="ghost"
          size="icon-xs"
          :aria-label="$t('flows.sequence_stage.zoom_out')"
          @click="changeZoom(-0.25)"
          ><ZoomOut class="size-3.5"
        /></Button>
        <span class="min-w-9 text-center text-[10px] tabular-nums text-muted-foreground"
          >{{ Math.round(zoom * 100) }}%</span
        >
        <Button
          type="button"
          variant="ghost"
          size="icon-xs"
          :aria-label="$t('flows.sequence_stage.zoom_in')"
          @click="changeZoom(0.25)"
          ><ZoomIn class="size-3.5"
        /></Button>
        <Button
          type="button"
          variant="ghost"
          size="icon-xs"
          :title="$t('flows.sequence_stage.fit_view')"
          :aria-label="$t('flows.sequence_stage.fit_view')"
          data-fit-sequence-view
          @click="fitView"
          ><Scan class="size-3.5"
        /></Button>
      </div>
      <span
        class="pointer-events-none absolute bottom-3 right-3 z-30 hidden text-[10px] text-muted-foreground 2xl:block"
        >{{ $t("flows.sequence_stage.canvas_hint") }}</span
      >
    </div>
  </section>
</template>

<style scoped>
.sequence-frame-outline {
  border: 1px solid hsl(var(--foreground) / 0.75);
  box-shadow: 0 0 0 1px hsl(var(--background) / 0.9);
}
.sequence-stage-grid {
  background-image:
    linear-gradient(
      to right,
      color-mix(in oklch, var(--border) 45%, transparent) 1px,
      transparent 1px
    ),
    linear-gradient(
      to bottom,
      color-mix(in oklch, var(--border) 45%, transparent) 1px,
      transparent 1px
    );
  background-size: 20px 20px;
}
</style>
