<script setup lang="ts">
import { computed, onUnmounted, ref, watch } from "vue";
import { useElementSize } from "@vueuse/core";
import {
  Layers,
  Library,
  Loader2,
  Maximize2,
  Minimize2,
  PanelRight,
  Play,
  RotateCcw,
  Square,
  TriangleAlert,
  Upload,
} from "@lucide/vue";
import { Button } from "@components/ui/button";
import AssetUploadDecisionDialog from "@shared/components/assets/AssetUploadDecisionDialog.vue";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@components/ui/select";
import { useLive } from "@shared/composables/useLive";
import { compareSequenceLayers, sequenceLayerKey } from "@modules/flows/sequence/layerOrder";
import type {
  SequenceConfigPanelData,
  SequenceAssetEntry,
  SequenceStageState,
  SequenceVisualLayerRecord,
} from "@modules/flows/sequence/types";
import SequenceLocaleControls from "@modules/flows/sequence/components/SequenceLocaleControls.vue";
import FlowSequenceAudio from "./FlowSequenceAudio.vue";
import { Tabs, TabsList, TabsTrigger } from "@components/ui/tabs";
import FlowSequenceStage from "./FlowSequenceStage.vue";
import FlowSequencePlayback from "./FlowSequencePlayback.vue";
import FlowSequenceComments from "./FlowSequenceComments.vue";
import type { FlowCommentsPanelState, FlowCommentThread } from "@modules/flows/types/comments";
import type { SequencePlaybackAction, SequencePlaybackState } from "./sequence-playback";
import FlowSequenceLibrary from "./FlowSequenceLibrary.vue";
import FlowSequenceLayerList from "./FlowSequenceLayerList.vue";
import FlowSequenceInspector, { type SequenceLayerPatch } from "./FlowSequenceInspector.vue";
import { newSequenceLayerGeometry } from "../../lib/sequence-layer-creation";
import { clamp } from "../../lib/sequence-stage-geometry";
import { commentNodeId } from "../../lib/comment-geometry";
import {
  SEQUENCE_IMAGE_ACCEPT,
  useSequenceImageImport,
} from "../../composables/useSequenceImageImport";
import { useSequenceWorkspaceResize } from "../../composables/useSequenceWorkspaceResize";
import type { SequenceLibraryImage, SequenceLibrarySheet } from "./sequence-library";

const {
  stage,
  data = null,
  sheets = [],
  canEdit = false,
  fullscreen = false,
  playback = null,
  comments = null,
  debugging = false,
} = defineProps<{
  stage: SequenceStageState;
  data?: SequenceConfigPanelData | null;
  sheets?: SequenceLibrarySheet[];
  canEdit?: boolean;
  fullscreen?: boolean;
  debugging?: boolean;
  playback?: SequencePlaybackState | null;
  comments?: { state: FlowCommentsPanelState; pins: FlowCommentThread[] } | null;
}>();
const emit = defineEmits<{ "toggle-fullscreen": [] }>();
const live = useLive();
const playbackPanel = ref<InstanceType<typeof FlowSequencePlayback> | null>(null);
const audioPanel = ref<InstanceType<typeof FlowSequenceAudio> | null>(null);
const playbackPending = ref(false);
const playbackFailed = ref(false);
const workspaceRoot = ref<HTMLElement | null>(null);
const workspaceHeader = ref<HTMLElement | null>(null);
const { height: headerHeight } = useElementSize(workspaceHeader);
const uploadInput = ref<HTMLInputElement | null>(null);
const uploadedAssets = ref<SequenceAssetEntry[]>([]);
const dragDepth = ref(0);
const dropOnStage = ref(false);
let ownerRevision = 0;
const {
  importing,
  fileName,
  errors: uploadErrors,
  importImages,
  dialog: uploadDialog,
  uploading: uploadingImage,
  progress: uploadProgress,
  error: uploadError,
  confirmDecision,
  cancelDecision,
} = useSequenceImageImport(() => canEdit && !playback);
const selectedLayerKey = ref<string | null>(null);
const lockedLayerKeys = ref<string[]>([]);
const libraryOpen = ref(true);
const inspectorOpen = ref(true);
const inspectorTab = ref("visual");
const {
  libraryWidth,
  inspectorWidth,
  libraryLimits,
  inspectorLimits,
  compact,
  resizing,
  startResize,
  onResizeKeydown,
} = useSequenceWorkspaceResize({
  root: workspaceRoot,
  libraryOpen: () => libraryOpen.value,
  inspectorOpen: () => inspectorOpen.value,
});
const narrowPanel = ref<"stage" | "library" | "inspector">("stage");
const insertKind = ref("character");
const adding = ref(false);
let creationGeneration = 0;
const pendingSelection = ref<{ ownerId: string; keys: string[] } | null>(null);
const ROOT_SOURCE = "__initial__";
const ownerId = computed(() => stage.owner?.nodeId ?? null);
const ownerReady = computed(
  () =>
    ownerId.value != null && String(data?.owner_id ?? data?.sequence_id) === String(ownerId.value),
);
const sourceWritable = computed(() => canEdit && !playback && ownerReady.value);
const writable = computed(() => sourceWritable.value && stage.status === "ready");
const layers = computed(() =>
  [...(ownerReady.value ? (data?.visual_layers ?? []) : [])].sort(compareSequenceLayers),
);
const selectedLayer = computed(
  () => layers.value.find((l) => sequenceLayerKey(l) === selectedLayerKey.value) ?? null,
);
const images = computed(() => {
  const ids = new Set(uploadedAssets.value.map((asset) => String(asset.id)));
  return [
    ...uploadedAssets.value,
    ...(data?.image_assets ?? []).filter((asset) => !ids.has(String(asset.id))),
  ];
});
const sources = computed(() => data?.composition_sources ?? []);
const removed = computed(() => data?.removed_visual_layers ?? []);
const diagnostics = computed(() => stage.composition?.diagnostics ?? []);
const sourceValue = computed(() =>
  data?.composition_source_id == null ? ROOT_SOURCE : String(data.composition_source_id),
);

watch(
  () => stage.owner?.nodeId,
  () => {
    ownerRevision++;
    creationGeneration++;
    selectedLayerKey.value = null;
    pendingSelection.value = null;
    adding.value = false;
  },
);
onUnmounted(() => {
  ownerRevision++;
  creationGeneration++;
});
watch(layers, (next) => {
  const keys = next.map(sequenceLayerKey);
  if (pendingSelection.value?.ownerId === String(ownerId.value)) {
    const addedKey = keys.find((key) => !pendingSelection.value!.keys.includes(key));
    if (addedKey) {
      selectedLayerKey.value = addedKey;
      pendingSelection.value = null;
    }
  }
  if (selectedLayerKey.value && !keys.includes(selectedLayerKey.value))
    selectedLayerKey.value = null;
});

function push(event: string, payload: Record<string, unknown>) {
  if (writable.value) live.pushEvent(event, { id: ownerId.value, ...payload });
}

function setContentLocale(locale: string) {
  audioPanel.value?.stopVoicePreview();
  playbackPanel.value?.stopVoice();
  live.pushEvent("set_sequence_content_locale", { locale });
}

function playbackAction(action: SequencePlaybackAction, responseId?: string) {
  if (playbackPending.value) return;
  if (action === "stop") playbackPanel.value?.stop();
  playbackPending.value = true;
  playbackFailed.value = false;
  live.pushEvent(
    "sequence_playback",
    { action, id: ownerId.value, response_id: responseId },
    () => {
      playbackPending.value = false;
    },
    () => {
      playbackPending.value = false;
      playbackFailed.value = true;
    },
  );
}

function updateLayer(layer: SequenceVisualLayerRecord, patch: SequenceLayerPatch) {
  const definition = layer.sequenceId ?? layer.sequence_id;
  const row = layer.local_row_id ?? layer.localRowId ?? layer.rowId ?? layer.row_id;
  if (definition != null && String(definition) === String(ownerId.value) && row != null) {
    push("update_sequence_visual_layer", { layer_id: row, ...patch });
  } else {
    push("override_sequence_visual_layer", { layer_key: sequenceLayerKey(layer), ...patch });
  }
}

function updateSelected(patch: SequenceLayerPatch) {
  if (selectedLayer.value) updateLayer(selectedLayer.value, patch);
}

function removeSelected() {
  const layer = selectedLayer.value;
  if (!layer) return;
  const definition = layer.sequenceId ?? layer.sequence_id;
  const row = layer.local_row_id ?? layer.localRowId ?? layer.rowId ?? layer.row_id;
  if (definition != null && String(definition) === String(ownerId.value) && row != null) {
    push("delete_sequence_visual_layer", { layer_id: row });
  } else push("remove_sequence_visual_layer", { layer_key: sequenceLayerKey(layer) });
}

function toggleLock(key: string) {
  if (!canEdit) return;
  lockedLayerKeys.value = lockedLayerKeys.value.includes(key)
    ? lockedLayerKeys.value.filter((k) => k !== key)
    : [...lockedLayerKeys.value, key];
}

function sourceChanged(value: string | string[]) {
  const next = Array.isArray(value) ? value[0] : value;
  if (next && sourceWritable.value)
    live.pushEvent("set_composition_source", {
      id: ownerId.value,
      source_id: next === ROOT_SOURCE ? null : next,
    });
}

function imageRatio(url: string): Promise<number> {
  return new Promise((resolve) => {
    const image = new Image();
    const timeout = window.setTimeout(() => finish(1), 2500);
    function finish(ratio: number) {
      window.clearTimeout(timeout);
      image.onload = null;
      image.onerror = null;
      resolve(ratio);
    }
    image.onload = () =>
      finish(image.naturalHeight > 0 ? image.naturalWidth / image.naturalHeight : 1);
    image.onerror = () => finish(1);
    image.src = url;
  });
}

async function addImage(
  image: SequenceLibraryImage,
  position?: { x: number; y: number },
  kind = insertKind.value,
) {
  if (!writable.value || adding.value) return;
  const capturedOwner = ownerId.value;
  const generation = ++creationGeneration;
  adding.value = true;
  const ratio = await imageRatio(image.url);
  if (generation !== creationGeneration) return;
  if (capturedOwner !== ownerId.value || !writable.value) {
    adding.value = false;
    return;
  }
  pendingSelection.value = {
    ownerId: String(capturedOwner),
    keys: layers.value.map(sequenceLayerKey),
  };
  narrowPanel.value = "stage";
  await new Promise<void>((resolve) =>
    live.pushEvent(
      "create_sequence_visual_layer",
      {
        id: capturedOwner,
        asset_id: image.asset_id,
        label: image.label,
        kind,
        ...newSequenceLayerGeometry(kind, ratio, position),
      },
      () => {
        if (generation === creationGeneration) adding.value = false;
        resolve();
      },
      () => {
        if (generation === creationGeneration) {
          adding.value = false;
          pendingSelection.value = null;
        }
        resolve();
      },
    ),
  );
}

async function uploadImages(files: File[], position?: { x: number; y: number }) {
  const revision = ownerRevision;
  const kind = insertKind.value;
  await importImages(files, async (asset) => {
    uploadedAssets.value = [
      asset,
      ...uploadedAssets.value.filter((item) => String(item.id) !== String(asset.id)),
    ];
    if (position && revision === ownerRevision && writable.value) {
      await addImage(
        { asset_id: asset.id, url: asset.url ?? "", label: asset.filename, source: "asset" },
        position,
        kind,
      );
    }
  });
}

function fileChanged(event: Event) {
  const input = event.target as HTMLInputElement;
  const files = Array.from(input.files ?? []);
  input.value = "";
  void uploadImages(files);
}

function isFileDrag(event: DragEvent) {
  return event.dataTransfer?.types.includes("Files") || Boolean(event.dataTransfer?.files.length);
}

function isStageTarget(target: EventTarget | null): boolean {
  return target instanceof Element && target.closest("[data-sequence-canvas]") !== null;
}

function dragEntered(event: DragEvent) {
  if (isFileDrag(event)) dragDepth.value++;
}

function dragOver(event: DragEvent) {
  if (!isFileDrag(event)) return;
  event.preventDefault();
  dropOnStage.value = writable.value && isStageTarget(event.target);
  if (event.dataTransfer)
    event.dataTransfer.dropEffect = canEdit && !importing.value ? "copy" : "none";
}

function dragLeft(event: DragEvent) {
  if (isFileDrag(event)) dragDepth.value = Math.max(0, dragDepth.value - 1);
}

function stageDropPosition(event: DragEvent) {
  if (!writable.value || !isStageTarget(event.target)) return;
  const frame = workspaceRoot.value
    ?.querySelector("[data-sequence-frame]")
    ?.getBoundingClientRect();
  if (!frame || frame.width <= 0 || frame.height <= 0) return;
  return {
    x: clamp((event.clientX - frame.left) / frame.width, -10, 10),
    y: clamp((event.clientY - frame.top) / frame.height, -10, 10),
  };
}

function filesDropped(event: DragEvent) {
  if (!isFileDrag(event)) return;
  event.preventDefault();
  event.stopPropagation();
  dragDepth.value = 0;
  void uploadImages(Array.from(event.dataTransfer?.files ?? []), stageDropPosition(event));
}

function replaceImage(image: SequenceLibraryImage) {
  updateSelected({ asset_id: image.asset_id, label: image.label });
  narrowPanel.value = "stage";
}

function selectLayer(key: string | null) {
  selectedLayerKey.value = key;
  if (key) inspectorOpen.value = true;
}
defineExpose({
  stopVoicePreview: () => audioPanel.value?.stopVoicePreview(),
  pausePreviews: () => audioPanel.value?.pausePreviews(),
  stopPreviews: () => audioPanel.value?.stopPreviews(),
});
</script>

<template>
  <section
    ref="workspaceRoot"
    class="sequence-workspace relative flex h-full min-h-0 flex-col overflow-hidden bg-background"
    :style="{ '--library-width': `${libraryWidth}px`, '--inspector-width': `${inspectorWidth}px` }"
    data-sequence-workspace
    @dragenter="dragEntered"
    @dragover="dragOver"
    @dragleave="dragLeft"
    @drop.capture="filesDropped"
  >
    <div
      v-if="dragDepth > 0 && canEdit && !playback && !importing"
      class="pointer-events-none absolute inset-1 z-50 grid place-items-center rounded-lg border-2 border-dashed border-primary bg-background/80"
      data-sequence-file-drop
    >
      <span class="rounded-lg bg-background p-4 text-center text-sm font-medium shadow-sm">
        <Upload class="mx-auto mb-2 size-6 text-primary" />
        {{
          $t(
            dropOnStage
              ? "flows.sequence_library.drop_on_stage"
              : "flows.sequence_library.drop_in_library",
          )
        }}
      </span>
    </div>
    <header
      ref="workspaceHeader"
      class="flex shrink-0 flex-wrap items-center gap-2 border-b border-border px-3 py-2"
    >
      <Layers class="size-4 shrink-0 text-muted-foreground" />
      <span class="text-xs font-medium">{{ $t("flows.sequence_workspace.title") }}</span>
      <template v-if="ownerReady && !playback">
        <span class="text-[11px] text-muted-foreground"
          >#{{ ownerId }} · {{ $t("flows.sequence_workspace.continues_from") }}</span
        >
        <Select
          :model-value="sourceValue"
          :disabled="!sourceWritable"
          @update:model-value="sourceChanged"
        >
          <SelectTrigger
            class="h-7 w-44 min-w-0 text-xs"
            :aria-label="$t('flows.sequence_workspace.continues_from')"
            data-workspace-source
            ><SelectValue
          /></SelectTrigger>
          <SelectContent
            ><SelectItem :value="ROOT_SOURCE">{{
              $t("flows.sequence_workspace.initial")
            }}</SelectItem
            ><SelectItem v-for="source in sources" :key="source.id" :value="String(source.id)">{{
              source.label
            }}</SelectItem></SelectContent
          >
        </Select>
      </template>
      <span
        v-if="diagnostics.length"
        class="inline-flex items-center gap-1 text-[11px] text-amber-600 dark:text-amber-400"
        data-sequence-diagnostics
      >
        <TriangleAlert class="size-3.5" />
        {{ $t("flows.sequence_stage.diagnostics", { count: diagnostics.length }) }}
      </span>
      <span class="flex-1" />
      <SequenceLocaleControls
        id="sequence-workspace"
        :language-options="playback?.languageOptions ?? stage.languageOptions"
        :content-locale="playback?.contentLocale ?? stage.contentLocale"
        :localization-status="playback ? playback.localizationStatus : stage.localizationStatus"
        :voice="playback ? playback.voice : stage.voice"
        @update:content-locale="setContentLocale"
      />
      <FlowSequenceComments
        v-if="comments && !playback"
        :node-id="ownerId"
        :state="comments.state"
        :top="headerHeight + 8"
        :count="
          comments.pins.filter((pin) => String(commentNodeId(pin)) === String(ownerId)).length
        "
      />
      <Button
        variant="outline"
        size="xs"
        :disabled="
          debugging ||
          playbackPending ||
          (!playback &&
            (!ownerReady ||
              stage.status !== 'ready' ||
              stage.owner?.type !== 'dialogue' ||
              adding ||
              importing))
        "
        :title="
          $t(playback ? 'flows.sequence_playback.stop' : 'flows.sequence_playback.start_hint')
        "
        data-sequence-playback-toggle
        @click="playbackAction(playback ? 'stop' : 'start')"
        ><Square v-if="playback" class="size-3.5" /><Play v-else class="size-3.5" />{{
          $t(playback ? "flows.sequence_playback.stop" : "flows.sequence_playback.start")
        }}</Button
      >
      <Button
        v-if="!playback"
        variant="ghost"
        size="icon-xs"
        :aria-label="$t('flows.sequence_library.title')"
        :aria-pressed="libraryOpen"
        @click="
          libraryOpen = !libraryOpen;
          narrowPanel = narrowPanel === 'library' ? 'stage' : 'library';
        "
        ><Library class="size-4"
      /></Button>
      <Button
        v-if="!playback"
        variant="ghost"
        size="icon-xs"
        :aria-label="$t('flows.sequence_workspace.inspector')"
        :aria-pressed="inspectorOpen"
        @click="
          inspectorOpen = !inspectorOpen;
          narrowPanel = narrowPanel === 'inspector' ? 'stage' : 'inspector';
        "
        ><PanelRight class="size-4"
      /></Button>
      <Button
        variant="ghost"
        size="icon-xs"
        :aria-label="
          $t(
            fullscreen ? 'flows.sequence_stage.exit_fullscreen' : 'flows.sequence_stage.fullscreen',
          )
        "
        data-workspace-fullscreen
        @click="emit('toggle-fullscreen')"
        ><Minimize2 v-if="fullscreen" class="size-4" /><Maximize2 v-else class="size-4"
      /></Button>
    </header>
    <p v-if="playbackFailed" class="shrink-0 px-3 py-2 text-xs text-destructive" role="alert">
      {{ $t("flows.sequence_playback.error") }}
    </p>
    <FlowSequencePlayback
      ref="playbackPanel"
      v-if="playback"
      :state="playback"
      :pending="playbackPending"
      @action="playbackAction"
    />
    <div
      v-show="!playback"
      class="sequence-workspace-tabs shrink-0 gap-1 border-b border-border px-2 py-1"
    >
      <Button
        v-for="panel in ['library', 'stage', 'inspector'] as const"
        :key="panel"
        variant="ghost"
        size="xs"
        :aria-pressed="narrowPanel === panel"
        @click="narrowPanel = panel"
        >{{ $t(`flows.sequence_workspace.panels.${panel}`) }}</Button
      >
    </div>
    <div v-show="!playback" class="flex min-h-0 flex-1" :data-narrow-panel="narrowPanel">
      <aside
        class="sequence-workspace-library flex shrink-0 min-h-0 flex-col bg-card/30"
        :class="{ 'sequence-panel-collapsed': !libraryOpen }"
      >
        <div class="shrink-0 space-y-2 border-b border-border p-3">
          <input
            ref="uploadInput"
            type="file"
            multiple
            :accept="SEQUENCE_IMAGE_ACCEPT"
            :aria-label="$t('flows.sequence_library.upload_images')"
            class="sr-only"
            :disabled="!canEdit || importing"
            data-sequence-upload-input
            @change="fileChanged"
          />
          <Button
            variant="outline"
            size="sm"
            class="w-full gap-2 text-xs"
            :disabled="!canEdit || importing"
            data-sequence-upload
            @click="uploadInput?.click()"
          >
            <Loader2 v-if="importing" class="size-3.5 animate-spin" /><Upload
              v-else
              class="size-3.5"
            />
            {{ $t(importing ? "common.assets.uploading" : "flows.sequence_library.upload_images") }}
          </Button>
          <p class="text-[11px] text-muted-foreground" data-sequence-upload-hint>
            {{ $t("flows.sequence_library.drop_in_library") }}
          </p>
          <p v-if="importing" class="truncate text-xs text-muted-foreground" role="status">
            {{ fileName }}
          </p>
          <ul
            v-if="uploadErrors.length"
            class="max-h-24 overflow-y-auto text-xs text-destructive"
            role="alert"
          >
            <li v-for="error in uploadErrors" :key="error">{{ error }}</li>
          </ul>
        </div>
        <label class="grid shrink-0 gap-1 px-3 py-2 text-[11px] text-muted-foreground"
          >{{ $t("flows.sequence_workspace.add_as") }}
          <Select v-model="insertKind" :disabled="!writable"
            ><SelectTrigger class="h-8 text-xs"><SelectValue /></SelectTrigger
            ><SelectContent
              ><SelectItem
                v-for="kind in ['character', 'backdrop', 'prop', 'overlay']"
                :key="kind"
                :value="kind"
                >{{ $t(`flows.sequences.visual_layers.kinds.${kind}`) }}</SelectItem
              ></SelectContent
            ></Select
          >
        </label>
        <FlowSequenceLibrary
          class="min-h-0 flex-1"
          remote-search
          :uploaded-assets="uploadedAssets"
          :sheets="sheets"
          :image-assets="images"
          :speaker-sheet-id="stage.intervention?.speakerSheetId"
          :selected-asset-id="selectedLayer?.assetId ?? selectedLayer?.asset_id"
          :can-replace="selectedLayer != null"
          :can-edit="writable && !adding && !importing"
          @add-image="addImage"
          @replace-image="replaceImage"
        />
      </aside>
      <div
        v-if="libraryOpen && !compact"
        class="sequence-workspace-separator"
        :class="{ 'is-resizing': resizing === 'library' }"
        role="separator"
        aria-orientation="vertical"
        :aria-label="$t('flows.sequence_workspace.resize_library')"
        :aria-valuemin="libraryLimits.min"
        :aria-valuemax="libraryLimits.max"
        :aria-valuenow="libraryWidth"
        tabindex="0"
        data-sequence-resize="library"
        @pointerdown="startResize($event, 'library')"
        @keydown="onResizeKeydown($event, 'library')"
      />
      <div class="sequence-workspace-stage min-w-0 flex-1">
        <FlowSequenceStage
          :stage="stage"
          :can-edit="writable"
          :fullscreen="fullscreen"
          embedded
          :selected-layer-key="selectedLayerKey"
          :locked-layer-keys="lockedLayerKeys"
          @update:selected-layer-key="selectLayer"
          @add-image="addImage($event.image, $event)"
          @toggle-fullscreen="emit('toggle-fullscreen')"
        />
      </div>
      <div
        v-if="inspectorOpen && !compact"
        class="sequence-workspace-separator"
        :class="{ 'is-resizing': resizing === 'inspector' }"
        role="separator"
        aria-orientation="vertical"
        :aria-label="$t('flows.sequence_workspace.resize_inspector')"
        :aria-valuemin="inspectorLimits.min"
        :aria-valuemax="inspectorLimits.max"
        :aria-valuenow="inspectorWidth"
        tabindex="0"
        data-sequence-resize="inspector"
        @pointerdown="startResize($event, 'inspector')"
        @keydown="onResizeKeydown($event, 'inspector')"
      />
      <aside
        class="sequence-workspace-inspector flex shrink-0 flex-col gap-3 overflow-y-auto bg-card/30 p-3"
        :class="{ 'sequence-panel-collapsed': !inspectorOpen }"
      >
        <Tabs v-model="inspectorTab" class="shrink-0">
          <TabsList class="grid w-full grid-cols-2"
            ><TabsTrigger value="visual" class="text-xs">{{
              $t("flows.sequences.visual_layers.title")
            }}</TabsTrigger
            ><TabsTrigger value="audio" class="text-xs">{{
              $t("flows.sequences.config_panel.audio_title")
            }}</TabsTrigger></TabsList
          >
        </Tabs>
        <FlowSequenceAudio
          ref="audioPanel"
          v-if="inspectorTab === 'audio' && ownerId != null && data && ownerReady && !playback"
          :key="String(ownerId)"
          :owner-id="ownerId"
          :data="data"
          :voice="stage.voice"
          :can-edit="writable"
        />
        <template v-if="inspectorTab === 'visual'">
          <FlowSequenceLayerList
            :layers="layers"
            :selected-key="selectedLayerKey"
            :locked-keys="lockedLayerKeys"
            :can-edit="writable"
            @select="selectLayer"
            @visibility="(layer, visible) => updateLayer(layer, { visible })"
            @lock="toggleLock"
            @reorder="push('reorder_sequence_visual_layers', { layer_keys: $event })"
          />
          <FlowSequenceInspector
            :key="`${ownerId}:${selectedLayerKey}`"
            :layer="selectedLayer"
            :image-assets="images"
            :can-edit="writable"
            :locked="selectedLayerKey != null && lockedLayerKeys.includes(selectedLayerKey)"
            @update="updateSelected"
            @remove="removeSelected"
            @revert="
              push('revert_sequence_visual_layer', { layer_key: selectedLayerKey, fields: $event })
            "
          />
          <details
            v-if="removed.length"
            class="border-t border-border pt-2 text-xs text-muted-foreground"
          >
            <summary class="cursor-pointer">
              {{ $t("flows.sequences.config_panel.removed_layers") }}
            </summary>
            <div
              v-for="layer in removed"
              :key="sequenceLayerKey(layer)"
              class="mt-2 flex items-center gap-2"
            >
              <span class="min-w-0 flex-1 truncate">{{ layer.label }}</span
              ><Button
                variant="ghost"
                size="icon-xs"
                :disabled="!writable"
                :aria-label="$t('flows.sequences.config_panel.restore')"
                @click="
                  push('restore_sequence_visual_layer', { layer_key: sequenceLayerKey(layer) })
                "
                ><RotateCcw class="size-3.5"
              /></Button>
            </div>
          </details>
        </template>
      </aside>
    </div>
    <AssetUploadDecisionDialog
      :state="uploadDialog"
      :uploading="uploadingImage"
      :progress="uploadProgress"
      :error="uploadError"
      @confirm="confirmDecision"
      @cancel="cancelDecision"
    />
  </section>
</template>

<style scoped>
.sequence-workspace {
  container-type: inline-size;
}
.sequence-workspace-tabs {
  display: none;
}
.sequence-workspace-library {
  width: var(--library-width);
}
.sequence-workspace-inspector {
  width: var(--inspector-width);
}
.sequence-workspace-separator {
  display: grid;
  width: 6px;
  flex-shrink: 0;
  place-items: center;
  cursor: col-resize;
  touch-action: none;
  background: hsl(var(--border));
}
.sequence-workspace-separator::after {
  content: "";
  width: 2px;
  height: 32px;
  border-radius: 2px;
  background: hsl(var(--muted-foreground));
  opacity: 0.4;
}
.sequence-workspace-separator:hover,
.sequence-workspace-separator:focus-visible,
.sequence-workspace-separator.is-resizing {
  background: hsl(var(--primary));
  outline: none;
}
.sequence-workspace-separator:focus-visible::after,
.sequence-workspace-separator.is-resizing::after {
  background: hsl(var(--primary-foreground));
  opacity: 1;
}
.sequence-panel-collapsed {
  display: none;
}
@container (max-width: 780px) {
  .sequence-workspace-tabs {
    display: flex;
  }
  .sequence-workspace-library,
  .sequence-workspace-inspector {
    display: none;
    width: 100%;
    border: 0;
  }
  [data-narrow-panel="library"] .sequence-workspace-library,
  [data-narrow-panel="inspector"] .sequence-workspace-inspector {
    display: flex;
  }
  [data-narrow-panel="library"] .sequence-workspace-stage,
  [data-narrow-panel="inspector"] .sequence-workspace-stage {
    display: none;
  }
}
</style>
