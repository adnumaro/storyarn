<script setup lang="ts">
import { computed, onUnmounted, ref, watch } from "vue";
import {
  Layers,
  MoveDiagonal2,
  PanelRightOpen,
  Pause,
  Play,
  RefreshCw,
  TriangleAlert,
} from "@lucide/vue";
import { Avatar, AvatarFallback, AvatarImage } from "@components/ui/avatar";
import { Badge } from "@components/ui/badge";
import { Button } from "@components/ui/button";
import { useLive } from "@shared/composables/useLive";
import DialogueVoice from "@modules/flows/player/components/DialogueVoice.vue";
import SequenceLocaleControls from "@modules/flows/sequence/components/SequenceLocaleControls.vue";
import SequenceVisualLayers from "@modules/flows/sequence/components/SequenceVisualLayers.vue";
import type {
  SequenceAudioTrack,
  SequenceEntityId,
  SequenceStageState,
  SequenceVisualLayer,
} from "@modules/flows/sequence/types";
import SequenceAudioTrackPreview from "./SequenceAudioTrackPreview.vue";

const { stage, canEdit = false } = defineProps<{
  stage: SequenceStageState;
  canEdit?: boolean;
}>();

const live = useLive();
const viewport = ref<HTMLElement | null>(null);
const selectedLayerKey = ref<string | null>(null);
const voicePreview = ref<InstanceType<typeof DialogueVoice> | null>(null);
const audioPreviews = ref<Array<InstanceType<typeof SequenceAudioTrackPreview> | null>>([]);
const voicePreviewPlaying = ref(false);
const voicePreviewBlocked = ref(false);

interface LayerGeometry {
  x: number;
  y: number;
  width: number;
  height: number;
}

const draftGeometry = ref<LayerGeometry | null>(null);

interface PointerSession {
  mode: "move" | "resize";
  key: string;
  sequenceId: SequenceEntityId | null;
  rowId: SequenceEntityId | null;
  startClientX: number;
  startClientY: number;
  viewportWidth: number;
  viewportHeight: number;
  x: number;
  y: number;
  width: number;
  height: number;
}

let pointerSession: PointerSession | null = null;

const intervention = computed(() => stage.intervention ?? null);
const composition = computed(() => stage.composition ?? null);
const layers = computed(() => composition.value?.layers ?? []);
const displayLayers = computed(() => {
  if (!selectedLayerKey.value || !draftGeometry.value) return layers.value;
  return layers.value.map((layer) =>
    layerKey(layer) === selectedLayerKey.value ? { ...layer, ...draftGeometry.value } : layer,
  );
});
const interactiveLayers = computed(() =>
  [...displayLayers.value]
    .filter((layer) => layer.visible !== false && Boolean(layer.url?.trim()))
    .sort((a, b) => {
      const depthDelta = layerDepth(a) - layerDepth(b);
      if (depthDelta !== 0) return depthDelta;
      const zDelta = layerZIndex(a) - layerZIndex(b);
      if (zDelta !== 0) return zDelta;
      return String(a.id).localeCompare(String(b.id));
    }),
);
const diagnostics = computed(() => composition.value?.diagnostics ?? []);
const previewableAudioTracks = computed(() =>
  (composition.value?.audioTracks ?? []).filter(
    (track) =>
      (track.kind === "music" || track.kind === "ambience") &&
      typeof track.url === "string" &&
      Boolean(track.url.trim()),
  ),
);
const hasVisibleLayers = computed(() => interactiveLayers.value.length > 0);
const owner = computed(() => stage.owner ?? null);
const localizationStatus = computed(
  () => stage.localizationStatus ?? intervention.value?.localization ?? null,
);
const stageVoice = computed(() => stage.voice ?? intervention.value?.voice ?? null);
const playableVoice = computed(
  () =>
    stageVoice.value?.available !== false &&
    typeof stageVoice.value?.url === "string" &&
    Boolean(stageVoice.value.url.trim()),
);
const canManipulate = computed(() => canEdit && stage.status === "ready" && owner.value != null);
const speakerInitials = computed(() => {
  if (intervention.value?.speakerInitials) return intervention.value.speakerInitials;

  const name = intervention.value?.speakerName?.trim();
  if (!name) return "?";

  const parts = name.split(/\s+/).filter(Boolean);
  return parts
    .slice(0, 2)
    .map((part) => part[0])
    .join("")
    .toUpperCase();
});

watch(
  () => owner.value?.nodeId,
  () => {
    stopVoicePreview();
    cancelPointerInteraction();
    clearSelection();
  },
);

watch(
  [
    () => stageVoice.value?.continuityKey ?? stageVoice.value?.continuity_key,
    () => stageVoice.value?.url,
  ],
  () => {
    voicePreviewPlaying.value = false;
    voicePreviewBlocked.value = false;
  },
);

watch(
  () => layers.value.map(layerKey).join(":"),
  () => {
    if (!layers.value.some((layer) => layerKey(layer) === selectedLayerKey.value)) clearSelection();
  },
);

function layerKey(layer: SequenceVisualLayer): string {
  return String(layer.key ?? layer.id);
}

function layerDepth(layer: SequenceVisualLayer): number {
  return layer.sequence_depth ?? layer.sequenceDepth ?? 0;
}

function layerZIndex(layer: SequenceVisualLayer): number {
  return layer.z_index ?? layer.zIndex ?? 0;
}

function sameEntityId(
  left: SequenceEntityId | null | undefined,
  right: SequenceEntityId | null | undefined,
): boolean {
  return left != null && right != null && String(left) === String(right);
}

function audioTrackKey(track: SequenceAudioTrack): string {
  return String(track.continuityKey ?? track.continuity_key ?? track.id);
}

function normalized(value: number | null | undefined, fallback: number): number {
  if (typeof value !== "number" || Number.isNaN(value)) return fallback;
  return Math.min(1, Math.max(0, value));
}

function layerFrameStyle(layer: SequenceVisualLayer, stackIndex: number) {
  const x = normalized(layer.x, 0);
  const y = normalized(layer.y, 0);
  const width = normalized(layer.width, 1);
  const height = normalized(layer.height, 1);
  const anchorX = normalized(layer.anchor_x ?? layer.anchorX, 0);
  const anchorY = normalized(layer.anchor_y ?? layer.anchorY, 0);

  return {
    left: `${x * 100}%`,
    top: `${y * 100}%`,
    width: `${width * 100}%`,
    height: `${height * 100}%`,
    transform: `translate(${-anchorX * 100}%, ${-anchorY * 100}%)`,
    zIndex: stackIndex,
  };
}

function openInspector() {
  if (!owner.value) return;
  live.pushEvent("open_sequence_config", { id: owner.value.nodeId });
}

function setContentLocale(locale: string) {
  stopVoicePreview();
  live.pushEvent("set_sequence_content_locale", { locale });
}

function stopVoicePreview(): void {
  voicePreview.value?.stop();
  voicePreviewPlaying.value = false;
  voicePreviewBlocked.value = false;
}

function pausePreviews(): void {
  voicePreview.value?.pause();
  voicePreviewPlaying.value = false;
  for (const preview of audioPreviews.value) preview?.pause();
}

function stopPreviews(): void {
  stopVoicePreview();
  for (const preview of audioPreviews.value) preview?.stop();
}

defineExpose({
  pausePreviews,
  stopPreviews,
  stopVoicePreview,
});

function toggleVoicePreview() {
  if (voicePreviewPlaying.value) {
    voicePreview.value?.pause();
    return;
  }

  if (voicePreviewBlocked.value) {
    voicePreview.value?.retryBlockedAudio();
    return;
  }

  voicePreview.value?.play();
}

function selectLayer(layer: SequenceVisualLayer) {
  selectedLayerKey.value = layerKey(layer);
}

function clearSelection() {
  selectedLayerKey.value = null;
  draftGeometry.value = null;
}

function startPointerInteraction(
  event: PointerEvent,
  layer: SequenceVisualLayer,
  mode: PointerSession["mode"],
) {
  if (!canManipulate.value || !viewport.value) return;

  event.preventDefault();
  event.stopPropagation();
  selectLayer(layer);

  const bounds = viewport.value.getBoundingClientRect();
  if (bounds.width <= 0 || bounds.height <= 0) return;

  pointerSession = {
    mode,
    key: layerKey(layer),
    sequenceId: layer.sequence_id ?? layer.sequenceId ?? null,
    rowId: layer.row_id ?? layer.rowId ?? null,
    startClientX: event.clientX,
    startClientY: event.clientY,
    viewportWidth: bounds.width,
    viewportHeight: bounds.height,
    x: normalized(layer.x, 0),
    y: normalized(layer.y, 0),
    width: normalized(layer.width, 1),
    height: normalized(layer.height, 1),
  };
  draftGeometry.value = {
    x: pointerSession.x,
    y: pointerSession.y,
    width: pointerSession.width,
    height: pointerSession.height,
  };

  window.addEventListener("pointermove", updatePointerInteraction);
  window.addEventListener("pointerup", finishPointerInteraction, { once: true });
}

function updatePointerInteraction(event: PointerEvent) {
  if (!pointerSession) return;

  const dx = (event.clientX - pointerSession.startClientX) / pointerSession.viewportWidth;
  const dy = (event.clientY - pointerSession.startClientY) / pointerSession.viewportHeight;

  if (pointerSession.mode === "move") {
    draftGeometry.value = {
      x: clamp(pointerSession.x + dx, 0, 1),
      y: clamp(pointerSession.y + dy, 0, 1),
      width: pointerSession.width,
      height: pointerSession.height,
    };
  } else {
    draftGeometry.value = {
      x: pointerSession.x,
      y: pointerSession.y,
      width: clamp(pointerSession.width + dx, 0.02, 1),
      height: clamp(pointerSession.height + dy, 0.02, 1),
    };
  }
}

function finishPointerInteraction() {
  window.removeEventListener("pointermove", updatePointerInteraction);

  const session = pointerSession;
  const geometry = draftGeometry.value;
  pointerSession = null;

  if (!session || !geometry || !owner.value) return;

  if (session.mode === "move") {
    const x = rounded(geometry.x);
    const y = rounded(geometry.y);

    if (x !== rounded(session.x) || y !== rounded(session.y)) {
      persistLayerGeometry(session, { x, y });
    }
  } else {
    const width = rounded(geometry.width);
    const height = rounded(geometry.height);

    if (width !== rounded(session.width) || height !== rounded(session.height)) {
      persistLayerGeometry(session, { width, height });
    }
  }
  draftGeometry.value = null;
}

function persistLayerGeometry(session: PointerSession, geometry: Partial<LayerGeometry>) {
  if (!owner.value) return;

  if (sameEntityId(session.sequenceId, owner.value.nodeId) && session.rowId != null) {
    live.pushEvent("update_sequence_visual_layer", {
      id: owner.value.nodeId,
      layer_id: session.rowId,
      ...geometry,
    });
    return;
  }

  live.pushEvent("override_sequence_visual_layer", {
    id: owner.value.nodeId,
    layer_key: session.key,
    ...geometry,
  });
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

function rounded(value: number): number {
  return Math.round(value * 10_000) / 10_000;
}

function cancelPointerInteraction() {
  window.removeEventListener("pointermove", updatePointerInteraction);
  window.removeEventListener("pointerup", finishPointerInteraction);
  pointerSession = null;
  draftGeometry.value = null;
}

onUnmounted(() => {
  stopPreviews();
  cancelPointerInteraction();
});
</script>

<template>
  <section
    id="flow-sequence-stage"
    class="h-[38%] min-h-56 max-h-96 shrink-0 border-b border-border bg-muted/20 flex flex-col"
    :data-status="stage.status"
  >
    <header
      class="min-h-9 shrink-0 px-3 py-1.5 flex flex-wrap items-center gap-2 border-b border-border/70 bg-background/80"
    >
      <Layers class="size-3.5 text-muted-foreground" />
      <h2 class="text-xs font-semibold tracking-wide">
        {{ $t("flows.sequence_stage.title") }}
      </h2>
      <Badge variant="outline" class="h-5 px-1.5 text-[10px] font-normal text-muted-foreground">
        {{ $t("flows.sequence_stage.static_preview") }}
      </Badge>
      <div
        v-if="stage.status === 'ready' && previewableAudioTracks.length > 0"
        class="flex min-w-0 items-center gap-1"
        data-sequence-audio-previews
      >
        <SequenceAudioTrackPreview
          v-for="track in previewableAudioTracks"
          ref="audioPreviews"
          :key="audioTrackKey(track)"
          :track="track"
        />
      </div>
      <div class="ml-auto flex items-center gap-1.5">
        <SequenceLocaleControls
          id="sequence-stage"
          :language-options="stage.languageOptions"
          :content-locale="stage.contentLocale"
          :localization-status="localizationStatus"
          :voice="stageVoice"
          @update:content-locale="setContentLocale"
        >
          <Button
            v-if="playableVoice"
            type="button"
            variant="outline"
            size="icon-xs"
            :title="
              voicePreviewBlocked
                ? $t('flows.presentation.retry_voice_preview')
                : voicePreviewPlaying
                  ? $t('flows.presentation.pause_voice_preview')
                  : $t('flows.presentation.play_voice_preview')
            "
            :aria-label="
              voicePreviewBlocked
                ? $t('flows.presentation.retry_voice_preview')
                : voicePreviewPlaying
                  ? $t('flows.presentation.pause_voice_preview')
                  : $t('flows.presentation.play_voice_preview')
            "
            :data-voice-preview-state="
              voicePreviewBlocked ? 'blocked' : voicePreviewPlaying ? 'playing' : 'paused'
            "
            data-sequence-voice-preview
            @click="toggleVoicePreview"
          >
            <RefreshCw v-if="voicePreviewBlocked" class="size-3.5" aria-hidden="true" />
            <Pause v-else-if="voicePreviewPlaying" class="size-3.5" aria-hidden="true" />
            <Play v-else class="size-3.5" aria-hidden="true" />
          </Button>
        </SequenceLocaleControls>
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
          size="icon-xs"
          :title="$t('flows.sequence_stage.open_inspector')"
          :aria-label="$t('flows.sequence_stage.open_inspector')"
          data-open-sequence-inspector
          @click="openInspector"
        >
          <PanelRightOpen class="size-3.5" />
        </Button>
      </div>
    </header>

    <DialogueVoice
      ref="voicePreview"
      :voice="stageVoice"
      :autoplay="false"
      @blocked-change="voicePreviewBlocked = $event"
      @playing-change="voicePreviewPlaying = $event"
    />

    <div class="flex-1 min-h-0 px-3 py-2.5 grid place-items-center overflow-hidden">
      <div
        ref="viewport"
        class="flow-sequence-viewport relative h-full max-w-full aspect-video overflow-hidden rounded-lg border border-border/80 bg-background shadow-sm"
        @pointerdown.self="clearSelection"
      >
        <SequenceVisualLayers v-if="stage.status === 'ready'" :layers="displayLayers" />

        <div
          v-if="canManipulate"
          class="pointer-events-none absolute inset-0 z-10"
          data-sequence-layer-controls
        >
          <button
            v-for="(layer, stackIndex) in interactiveLayers"
            :key="layerKey(layer)"
            type="button"
            class="pointer-events-auto absolute cursor-move border border-transparent outline-none transition-[border-color,box-shadow] hover:border-primary/60 focus-visible:border-primary focus-visible:ring-2 focus-visible:ring-primary/40"
            :class="
              selectedLayerKey === layerKey(layer)
                ? 'border-primary shadow-[inset_0_0_0_1px_var(--primary)]'
                : undefined
            "
            :style="layerFrameStyle(layer, stackIndex)"
            :aria-label="
              $t('flows.sequence_stage.select_layer', {
                name: layer.label || layer.kind,
              })
            "
            :data-layer-control="layerKey(layer)"
            :data-selected="selectedLayerKey === layerKey(layer) || undefined"
            @click="selectLayer(layer)"
            @pointerdown="startPointerInteraction($event, layer, 'move')"
          >
            <span
              v-if="selectedLayerKey === layerKey(layer)"
              class="absolute left-0 top-0 inline-flex max-w-full -translate-y-full items-center gap-1 rounded-t bg-primary px-1.5 py-0.5 text-[9px] font-medium text-primary-foreground"
              aria-hidden="true"
            >
              <MoveDiagonal2 class="size-2.5" />
              <span class="truncate">{{ layer.label || layer.kind }}</span>
            </span>
            <span
              v-if="selectedLayerKey === layerKey(layer)"
              class="absolute bottom-0 right-0 grid size-5 translate-x-1/2 translate-y-1/2 cursor-se-resize place-items-center rounded-sm border border-primary bg-background text-primary shadow-sm outline-none focus-visible:ring-2 focus-visible:ring-primary/50"
              aria-hidden="true"
              :title="$t('flows.sequence_stage.resize_layer', { name: layer.label || layer.kind })"
              data-layer-resize-handle
              @pointerdown="startPointerInteraction($event, layer, 'resize')"
            >
              <MoveDiagonal2 class="size-3" />
            </span>
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
          class="absolute inset-0 z-0 grid place-items-center text-xs text-muted-foreground sequence-stage-grid"
          data-sequence-empty-composition
        >
          {{ $t("flows.sequence_stage.no_layers") }}
        </div>

        <div
          v-if="stage.status === 'ready' && intervention"
          class="absolute inset-x-0 bottom-0 z-[2000] border-t border-white/10 bg-slate-950/88 px-4 py-3 text-slate-100 backdrop-blur-sm"
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
    </div>
  </section>
</template>

<style scoped>
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
