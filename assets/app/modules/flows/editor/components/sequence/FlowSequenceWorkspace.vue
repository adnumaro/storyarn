<script setup lang="ts">
import { computed, onUnmounted, ref, watch } from "vue";
import {
  Layers,
  Library,
  Maximize2,
  Minimize2,
  PanelRight,
  RotateCcw,
  TriangleAlert,
} from "@lucide/vue";
import { Button } from "@components/ui/button";
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
  SequenceStageState,
  SequenceVisualLayerRecord,
} from "@modules/flows/sequence/types";
import FlowSequenceStage from "./FlowSequenceStage.vue";
import FlowSequenceLibrary from "./FlowSequenceLibrary.vue";
import FlowSequenceLayerList from "./FlowSequenceLayerList.vue";
import FlowSequenceInspector, { type SequenceLayerPatch } from "./FlowSequenceInspector.vue";
import ImageAsset from "../assets/ImageAsset.vue";
import { newSequenceLayerGeometry } from "../../lib/sequence-layer-creation";
import type { SequenceLibraryImage, SequenceLibrarySheet } from "./sequence-library";

const {
  stage,
  data = null,
  sheets = [],
  canEdit = false,
  fullscreen = false,
} = defineProps<{
  stage: SequenceStageState;
  data?: SequenceConfigPanelData | null;
  sheets?: SequenceLibrarySheet[];
  canEdit?: boolean;
  fullscreen?: boolean;
}>();
const emit = defineEmits<{ "toggle-fullscreen": [] }>();
const live = useLive();
const selectedLayerKey = ref<string | null>(null);
const lockedLayerKeys = ref<string[]>([]);
const libraryOpen = ref(true);
const inspectorOpen = ref(true);
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
const writable = computed(() => canEdit && stage.status === "ready" && ownerReady.value);
const layers = computed(() =>
  [...(ownerReady.value ? (data?.visual_layers ?? []) : [])].sort(compareSequenceLayers),
);
const selectedLayer = computed(
  () => layers.value.find((l) => sequenceLayerKey(l) === selectedLayerKey.value) ?? null,
);
const images = computed(() => data?.image_assets ?? []);
const sources = computed(() => data?.composition_sources ?? []);
const removed = computed(() => data?.removed_visual_layers ?? []);
const diagnostics = computed(() => stage.composition?.diagnostics ?? []);
const sourceValue = computed(() =>
  data?.composition_source_id == null ? ROOT_SOURCE : String(data.composition_source_id),
);

watch(
  () => stage.owner?.nodeId,
  () => {
    creationGeneration++;
    selectedLayerKey.value = null;
    pendingSelection.value = null;
    adding.value = false;
  },
);
onUnmounted(() => {
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
  if (next) push("set_composition_source", { source_id: next === ROOT_SOURCE ? null : next });
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

async function addImage(image: SequenceLibraryImage, position?: { x: number; y: number }) {
  if (!writable.value || adding.value) return;
  const capturedOwner = ownerId.value;
  const generation = ++creationGeneration;
  const kind = insertKind.value;
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
    },
    () => {
      if (generation === creationGeneration) {
        adding.value = false;
        pendingSelection.value = null;
      }
    },
  );
  narrowPanel.value = "stage";
}

function replaceImage(image: SequenceLibraryImage) {
  updateSelected({ asset_id: image.asset_id, label: image.label });
  narrowPanel.value = "stage";
}

function selectLayer(key: string | null) {
  selectedLayerKey.value = key;
  if (key) inspectorOpen.value = true;
}
</script>

<template>
  <section
    class="sequence-workspace flex h-full min-h-0 flex-col overflow-hidden bg-background"
    data-sequence-workspace
  >
    <header class="flex shrink-0 flex-wrap items-center gap-2 border-b border-border px-3 py-2">
      <Layers class="size-4 shrink-0 text-muted-foreground" />
      <span class="text-xs font-medium">{{ $t("flows.sequence_workspace.title") }}</span>
      <template v-if="ownerReady">
        <span class="text-[11px] text-muted-foreground"
          >#{{ ownerId }} · {{ $t("flows.sequence_workspace.continues_from") }}</span
        >
        <Select
          :model-value="sourceValue"
          :disabled="!writable"
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
      <Button
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
    <div class="sequence-workspace-tabs shrink-0 gap-1 border-b border-border px-2 py-1">
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
    <div class="flex min-h-0 flex-1" :data-narrow-panel="narrowPanel">
      <aside
        class="sequence-workspace-library w-48 shrink-0 overflow-y-auto border-r border-border bg-card/30 p-3"
        :class="{ 'sequence-panel-collapsed': !libraryOpen }"
      >
        <label class="mb-3 grid gap-1 text-[11px] text-muted-foreground"
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
          remote-search
          :sheets="sheets"
          :image-assets="images"
          :speaker-sheet-id="stage.intervention?.speakerSheetId"
          :selected-asset-id="selectedLayer?.assetId ?? selectedLayer?.asset_id"
          :can-replace="selectedLayer != null"
          :can-edit="writable && !adding"
          @add-image="addImage"
          @replace-image="replaceImage"
        />
        <div class="mt-3 border-t border-border pt-3">
          <ImageAsset
            :key="String(ownerId)"
            :label="$t('flows.sequence_workspace.add_image')"
            :image-assets="images"
            :can-edit="writable && !adding"
            search-event="picker_search"
            :search-payload="{ resource: 'asset', kind: 'image' }"
            @select="
              addImage({
                asset_id: $event.id,
                url: $event.url ?? '',
                label: $event.filename,
                source: 'asset',
              })
            "
          />
        </div>
      </aside>
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
      <aside
        class="sequence-workspace-inspector flex w-72 shrink-0 flex-col gap-3 overflow-y-auto border-l border-border bg-card/30 p-3"
        :class="{ 'sequence-panel-collapsed': !inspectorOpen }"
      >
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
              @click="push('restore_sequence_visual_layer', { layer_key: sequenceLayerKey(layer) })"
              ><RotateCcw class="size-3.5"
            /></Button>
          </div>
        </details>
      </aside>
    </div>
  </section>
</template>

<style scoped>
.sequence-workspace {
  container-type: inline-size;
}
.sequence-workspace-tabs {
  display: none;
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
    display: block;
  }
  [data-narrow-panel="library"] .sequence-workspace-stage,
  [data-narrow-panel="inspector"] .sequence-workspace-stage {
    display: none;
  }
}
</style>
