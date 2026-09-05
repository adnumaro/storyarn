<script setup lang="ts">
import {
  Box,
  Check,
  ChevronDown,
  GitFork,
  Image as ImageIcon,
  Layers,
  Music,
  RotateCcw,
  Sparkles,
  Undo2,
  UserRound,
  Volume2,
  Wand2,
  X,
} from "@lucide/vue";
import { computed, ref, type Component } from "vue";
import { useI18n } from "vue-i18n";

import AudioAsset from "../assets/AudioAsset.vue";
import ImageAsset from "../assets/ImageAsset.vue";
import ImageFit from "../assets/ImageFit.vue";
import ImagePosition from "../assets/ImagePosition.vue";
import { Badge } from "../../../../../components/ui/badge";
import { Button } from "../../../../../components/ui/button";
import {
  Command,
  CommandGroup,
  CommandItem,
  CommandList,
} from "../../../../../components/ui/command";
import { Popover, PopoverContent, PopoverTrigger } from "../../../../../components/ui/popover";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "../../../../../components/ui/select";
import { Switch } from "../../../../../components/ui/switch";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "../../../../../components/ui/tabs";
import { ToggleGroup, ToggleGroupItem } from "../../../../../components/ui/toggle-group";
import Sidebar from "../../../../../shell/Sidebar.vue";
import { useLive } from "../../../../../shared/composables/useLive";
import type {
  SequenceAssetEntry as AssetEntry,
  SequenceAudioTrackRecord as SequenceTrack,
  SequenceConfigPanelData as PanelData,
  SequenceEntityId as EntityId,
  SequenceVisualLayerRecord as SequenceVisualLayer,
} from "../../../sequence/types";

type VisualKind = "backdrop" | "character" | "prop" | "overlay";
type PositionSlot =
  | "top-left"
  | "top-center"
  | "top-right"
  | "middle-left"
  | "middle-center"
  | "middle-right"
  | "bottom-left"
  | "bottom-center"
  | "bottom-right";
type VisualSlot = PositionSlot | "full" | "left" | "center" | "right" | "custom";
type VisualFit = "cover" | "contain" | "fill";
type LayoutMode = "full" | "positioned";
type PositionRow = "top" | "middle" | "bottom";
type PositionColumn = "left" | "center" | "right";
type LayerField =
  | "asset_id"
  | "kind"
  | "label"
  | "slot"
  | "x"
  | "y"
  | "width"
  | "height"
  | "z_index"
  | "fit"
  | "opacity"
  | "visible";
type TrackField = "asset_id" | "volume";
type TrackPropertyField = TrackField;
type LayerPatch = Partial<Record<LayerField | "anchor_x" | "anchor_y", unknown>>;

const {
  open = false,
  data = null,
  canEdit = false,
} = defineProps<{
  open?: boolean;
  data?: PanelData | null;
  canEdit?: boolean;
}>();

const live = useLive();
const { t } = useI18n();
const openLayerPicker = ref<string | null>(null);

const ROOT_SOURCE_VALUE = "__composition_root__";
const TRACK_KINDS = ["music", "ambience", "sfx"] as const;
const TRACK_PROPERTY_FIELDS: readonly TrackPropertyField[] = ["asset_id", "volume"];
const VISUAL_KINDS: readonly VisualKind[] = ["backdrop", "character", "prop", "overlay"];
const PICKER_SEARCH_EVENT = "picker_search";
const IMAGE_ASSET_SEARCH_PAYLOAD = { resource: "asset", kind: "image" };
const AUDIO_ASSET_SEARCH_PAYLOAD = { resource: "asset", kind: "audio" };
const POSITION_SLOTS: readonly PositionSlot[] = [
  "top-left",
  "top-center",
  "top-right",
  "middle-left",
  "middle-center",
  "middle-right",
  "bottom-left",
  "bottom-center",
  "bottom-right",
];
const NUMERIC_LAYER_FIELDS: ReadonlyArray<{
  field: "x" | "y" | "width" | "height" | "z_index";
  min: number;
  max: number;
  step: number;
}> = [
  { field: "x", min: 0, max: 1, step: 0.01 },
  { field: "y", min: 0, max: 1, step: 0.01 },
  { field: "width", min: 0.01, max: 1, step: 0.01 },
  { field: "height", min: 0.01, max: 1, step: 0.01 },
  { field: "z_index", min: -1000, max: 1000, step: 1 },
];

const ownerId = computed(() => data?.owner_id ?? data?.sequence_id ?? null);
const ownerType = computed(() => data?.owner_type ?? "sequence");
const sourceValue = computed(() =>
  data?.composition_source_id == null ? ROOT_SOURCE_VALUE : String(data.composition_source_id),
);
const compositionSources = computed(() => data?.composition_sources ?? []);
const diagnostics = computed(() => data?.diagnostics ?? []);
const visualLayers = computed(() =>
  [...(data?.visual_layers ?? [])].sort((a, b) => {
    const zDelta = layerZIndex(a) - layerZIndex(b);
    if (zDelta !== 0) return zDelta;
    return layerKey(a).localeCompare(layerKey(b));
  }),
);
const removedVisualLayers = computed(() => data?.removed_visual_layers ?? []);
const tracks = computed(() =>
  [...(data?.tracks ?? [])].sort((a, b) => {
    const kindDelta = trackKindOrder(a.kind) - trackKindOrder(b.kind);
    if (kindDelta !== 0) return kindDelta;
    return trackKey(a).localeCompare(trackKey(b));
  }),
);
const removedTracks = computed(() => data?.removed_tracks ?? []);
const missingTrackKinds = computed(() =>
  TRACK_KINDS.filter(
    (kind) =>
      !tracks.value.some(
        (track) => track.kind === kind && ownerDefinesTrack(track) && !trackIsOverride(track),
      ),
  ),
);

function close() {
  live.pushEvent("close_sequence_config", {});
}

function sameId(left: EntityId | null | undefined, right: EntityId | null | undefined): boolean {
  return left != null && right != null && String(left) === String(right);
}

function pushOwnerEvent(event: string, payload: Record<string, unknown>) {
  if (!canEdit || ownerId.value == null) return;
  live.pushEvent(event, { id: ownerId.value, ...payload });
}

function setCompositionSource(value: string | string[]) {
  const selected = Array.isArray(value) ? value[0] : value;
  if (!selected) return;
  pushOwnerEvent("set_composition_source", {
    source_id: selected === ROOT_SOURCE_VALUE ? null : selected,
  });
}

function createVisualLayer(kind: VisualKind, asset: AssetEntry) {
  pushOwnerEvent("create_sequence_visual_layer", {
    kind,
    asset_id: asset.id,
    label: asset.filename,
    slot: defaultSlot(kind),
    ...geometryForSlot(kind, defaultSlot(kind)),
  });
}

function layerKey(layer: SequenceVisualLayer): string {
  return String(layer.key ?? layer.layer_key ?? layer.id);
}

function layerSequenceId(layer: SequenceVisualLayer): EntityId | null {
  return layer.sequenceId ?? layer.sequence_id ?? ownerId.value;
}

function layerLocalRowId(layer: SequenceVisualLayer): EntityId | null {
  return layer.local_row_id ?? layer.localRowId ?? layer.rowId ?? layer.row_id ?? layer.id ?? null;
}

function layerAssetId(layer: SequenceVisualLayer): EntityId | null {
  return layer.assetId ?? layer.asset_id ?? null;
}

function layerZIndex(layer: SequenceVisualLayer): number {
  return Number(layer.zIndex ?? layer.z_index ?? 0);
}

function ownerDefinesLayer(layer: SequenceVisualLayer): boolean {
  return sameId(layerSequenceId(layer), ownerId.value);
}

function layerOverrideFields(layer: SequenceVisualLayer): string[] {
  return layer.overridden_fields ?? layer.overriddenFields ?? [];
}

function layerHasLocalPatch(layer: SequenceVisualLayer): boolean {
  return !ownerDefinesLayer(layer) && layerOverrideFields(layer).length > 0;
}

function updateVisualLayer(layer: SequenceVisualLayer, patch: LayerPatch) {
  const rowId = layerLocalRowId(layer);

  if (ownerDefinesLayer(layer) && rowId != null) {
    pushOwnerEvent("update_sequence_visual_layer", { layer_id: rowId, ...patch });
  } else {
    pushOwnerEvent("override_sequence_visual_layer", {
      layer_key: layerKey(layer),
      ...patch,
    });
  }
}

function removeVisualLayer(layer: SequenceVisualLayer) {
  const rowId = layerLocalRowId(layer);

  if (ownerDefinesLayer(layer) && rowId != null) {
    pushOwnerEvent("delete_sequence_visual_layer", { layer_id: rowId });
    return;
  }

  pushOwnerEvent("remove_sequence_visual_layer", { layer_key: layerKey(layer) });
}

function restoreVisualLayer(layer: SequenceVisualLayer) {
  pushOwnerEvent("restore_sequence_visual_layer", { layer_key: layerKey(layer) });
}

function revertVisualLayer(layer: SequenceVisualLayer, fields: string[]) {
  if (fields.length === 0) return;
  pushOwnerEvent("revert_sequence_visual_layer", {
    layer_key: layerKey(layer),
    fields,
  });
}

function setVisualSlot(layer: SequenceVisualLayer, slot: string) {
  const normalizedSlot = normalizeSlot(layer.kind, slot);
  updateVisualLayer(layer, {
    slot: normalizedSlot,
    ...geometryForSlot(layer.kind, normalizedSlot),
  });
}

function setVisualFit(layer: SequenceVisualLayer, fit: string) {
  updateVisualLayer(layer, { fit: fit as VisualFit });
}

function setVisualKind(layer: SequenceVisualLayer, kind: string) {
  const slot = defaultSlot(kind);
  updateVisualLayer(layer, { kind, slot, ...geometryForSlot(kind, slot) });
}

function pickVisualKind(layer: SequenceVisualLayer, kind: VisualKind) {
  setVisualKind(layer, kind);
  openLayerPicker.value = null;
}

function setVisualOpacity(layer: SequenceVisualLayer, event: Event) {
  const value = Number((event.target as HTMLInputElement).value);
  if (Number.isFinite(value)) updateVisualLayer(layer, { opacity: value / 100 });
}

function setNumericLayerField(
  layer: SequenceVisualLayer,
  field: "x" | "y" | "width" | "height" | "z_index",
  event: Event,
) {
  const value = Number((event.target as HTMLInputElement).value);
  if (Number.isFinite(value)) updateVisualLayer(layer, { [field]: value });
}

function numericLayerValue(
  layer: SequenceVisualLayer,
  field: "x" | "y" | "width" | "height" | "z_index",
): number {
  if (field === "z_index") return layerZIndex(layer);
  return Number(layer[field] ?? (field === "width" || field === "height" ? 1 : 0));
}

function setVisualVisibility(layer: SequenceVisualLayer, visible: boolean) {
  updateVisualLayer(layer, { visible });
}

function fieldOriginLabel(layer: SequenceVisualLayer, field: string): string {
  return originLabel(
    layer.propertyOrigins?.[field]?.nodeId ?? layer.origin?.nodeId ?? layerSequenceId(layer),
  );
}

function layerStatusLabel(layer: SequenceVisualLayer): string {
  if (ownerDefinesLayer(layer)) return t("flows.sequences.config_panel.local");
  if (layerHasLocalPatch(layer)) return t("flows.sequences.config_panel.customized");
  return t("flows.sequences.config_panel.inherited");
}

function defaultSlot(kind: string): VisualSlot {
  if (kind === "backdrop" || kind === "overlay") return "full";
  if (kind === "character") return "bottom-center";
  return "middle-center";
}

function defaultPositionSlot(kind: string): PositionSlot {
  return kind === "character" ? "bottom-center" : "middle-center";
}

function isPositionSlot(slot: string): slot is PositionSlot {
  return (POSITION_SLOTS as readonly string[]).includes(slot);
}

function normalizeSlot(kind: string, slot: string | null | undefined): VisualSlot {
  if (!slot) return defaultSlot(kind);
  if (slot === "left") return "bottom-left";
  if (slot === "right") return "bottom-right";
  if (slot === "center") return kind === "character" ? "bottom-center" : "middle-center";
  if (slot === "custom" || slot === "full" || isPositionSlot(slot)) return slot;
  return defaultSlot(kind);
}

function positionForLayer(layer: SequenceVisualLayer): PositionSlot {
  const slot = normalizeSlot(layer.kind, layer.slot || defaultSlot(layer.kind));
  return isPositionSlot(slot) ? slot : defaultPositionSlot(layer.kind);
}

function layoutModeForLayer(layer: SequenceVisualLayer): LayoutMode {
  return normalizeSlot(layer.kind, layer.slot || defaultSlot(layer.kind)) === "full"
    ? "full"
    : "positioned";
}

function setVisualLayoutMode(layer: SequenceVisualLayer, value: string | string[]) {
  const mode = Array.isArray(value) ? value[0] : value;
  if (mode) setVisualSlot(layer, mode === "full" ? "full" : positionForLayer(layer));
}

function geometryForSlot(kind: string, slot: string): LayerPatch {
  if (kind === "backdrop" || slot === "full") return fullLayerGeometry(kind);
  if (kind === "character") return characterLayerGeometry(slot);
  if (isPositionSlot(slot)) return positionedLayerGeometry(slot);
  return centeredLayerGeometry();
}

function fullLayerGeometry(kind: string): LayerPatch {
  return {
    x: 0,
    y: 0,
    width: 1,
    height: 1,
    anchor_x: 0,
    anchor_y: 0,
    fit: fullLayerFit(kind),
  };
}

function fullLayerFit(kind: string): VisualFit {
  return kind === "backdrop" || kind === "overlay" ? "cover" : "contain";
}

function characterLayerGeometry(slot: string): LayerPatch {
  const position = isPositionSlot(slot) ? slot : defaultPositionSlot("character");
  const { row, col } = splitPositionSlot(position);
  return {
    x: characterColumnX(col),
    y: characterRowY(row),
    width: characterWidth(col),
    height: 0.9,
    anchor_x: 0.5,
    anchor_y: characterRowY(row),
    fit: "contain",
  };
}

function positionedLayerGeometry(slot: PositionSlot): LayerPatch {
  const { row, col } = splitPositionSlot(slot);
  return {
    x: safeColumnX(col),
    y: safeRowY(row),
    width: 0.25,
    height: 0.25,
    anchor_x: 0.5,
    anchor_y: 0.5,
    fit: "contain",
  };
}

function centeredLayerGeometry(): LayerPatch {
  return {
    x: 0.5,
    y: 0.5,
    width: 0.25,
    height: 0.25,
    anchor_x: 0.5,
    anchor_y: 0.5,
    fit: "contain",
  };
}

function splitPositionSlot(slot: PositionSlot): { row: PositionRow; col: PositionColumn } {
  const [row, col] = slot.split("-") as [PositionRow, PositionColumn];
  return { row, col };
}

function characterColumnX(col: PositionColumn): number {
  if (col === "left") return 0.25;
  if (col === "right") return 0.75;
  return 0.5;
}

function safeColumnX(col: PositionColumn): number {
  if (col === "left") return 0.2;
  if (col === "right") return 0.8;
  return 0.5;
}

function characterRowY(row: PositionRow): number {
  if (row === "top") return 0;
  if (row === "bottom") return 1;
  return 0.5;
}

function safeRowY(row: PositionRow): number {
  if (row === "top") return 0.2;
  if (row === "bottom") return 0.8;
  return 0.5;
}

function characterWidth(col: PositionColumn): number {
  return col === "center" ? 0.42 : 0.38;
}

function kindIcon(kind: string): Component {
  if (kind === "backdrop") return ImageIcon;
  if (kind === "character") return UserRound;
  if (kind === "overlay") return Sparkles;
  return Box;
}

function addLayerLabel(kind: string): string {
  return `${t("flows.sequences.visual_layers.add")} ${t(`flows.sequences.visual_layers.kinds.${kind}`)}`;
}

function pickerKey(layer: SequenceVisualLayer): string {
  return `kind:${layerKey(layer)}`;
}

function pickerOpen(layer: SequenceVisualLayer): boolean {
  return openLayerPicker.value === pickerKey(layer);
}

function setPickerOpen(layer: SequenceVisualLayer, isOpen: boolean) {
  openLayerPicker.value = isOpen ? pickerKey(layer) : null;
}

function visualKindLabel(kind: string): string {
  return t(`flows.sequences.visual_layers.kinds.${kind}`);
}

function trackKey(track: SequenceTrack): string {
  return String(track.trackKey ?? track.track_key ?? track.id ?? track.kind);
}

function trackKindOrder(kind: string): number {
  const index = TRACK_KINDS.indexOf(kind as (typeof TRACK_KINDS)[number]);
  return index < 0 ? TRACK_KINDS.length : index;
}

function trackSequenceId(track: SequenceTrack): EntityId | null {
  return track.sequenceId ?? track.sequence_id ?? ownerId.value;
}

function trackAssetId(track: SequenceTrack): EntityId | null {
  return track.assetId ?? track.asset_id ?? null;
}

function ownerDefinesTrack(track: SequenceTrack): boolean {
  return sameId(trackSequenceId(track), ownerId.value);
}

function trackIsOverride(track: SequenceTrack): boolean {
  return track.isOverride ?? track.is_override ?? false;
}

function trackOverrideFields(track: SequenceTrack): TrackPropertyField[] {
  const fields = track.overridden_fields ?? track.overriddenFields ?? [];
  return TRACK_PROPERTY_FIELDS.filter((field) => fields.includes(field));
}

function trackOriginFields(track: SequenceTrack): TrackPropertyField[] {
  return TRACK_PROPERTY_FIELDS.filter((field) => track.propertyOrigins?.[field] != null);
}

function trackFieldOriginLabel(track: SequenceTrack, field: string): string {
  return originLabel(track.propertyOrigins?.[field]?.nodeId ?? trackSequenceId(track));
}

function trackHasLocalPatch(track: SequenceTrack): boolean {
  return !ownerDefinesTrack(track) && trackOverrideFields(track).length > 0;
}

function trackStatusLabel(track: SequenceTrack): string {
  if (ownerDefinesTrack(track)) return t("flows.sequences.config_panel.local");
  if (trackHasLocalPatch(track)) return t("flows.sequences.config_panel.customized");
  return t("flows.sequences.config_panel.inherited");
}

function updateTrack(track: SequenceTrack, patch: Partial<Record<TrackField, unknown>>) {
  if (ownerDefinesTrack(track) && !trackIsOverride(track)) {
    pushOwnerEvent("upsert_sequence_track", { kind: track.kind, ...patch });
  } else {
    pushOwnerEvent("override_sequence_track", {
      track_key: trackKey(track),
      ...patch,
    });
  }
}

function pickTrackAsset(track: SequenceTrack, asset: AssetEntry) {
  updateTrack(track, { asset_id: asset.id });
}

function createTrack(kind: string, asset: AssetEntry) {
  pushOwnerEvent("upsert_sequence_track", { kind, asset_id: asset.id });
}

function onTrackVolumeChange(track: SequenceTrack, percent: number) {
  updateTrack(track, { volume: percent / 100 });
}

function removeTrack(track: SequenceTrack) {
  if (ownerDefinesTrack(track) && !trackIsOverride(track)) {
    pushOwnerEvent("clear_sequence_track", { kind: track.kind });
    return;
  }

  pushOwnerEvent("remove_sequence_track", { track_key: trackKey(track) });
}

function restoreTrack(track: SequenceTrack) {
  pushOwnerEvent("restore_sequence_track", { track_key: trackKey(track) });
}

function revertTrack(track: SequenceTrack, fields: string[]) {
  if (fields.length === 0) return;
  pushOwnerEvent("revert_sequence_track", {
    track_key: trackKey(track),
    fields,
  });
}

function trackVolumePercent(track: SequenceTrack): number | null {
  return track.volume == null ? null : Math.round(Number(track.volume) * 100);
}

function trackIcon(kind: string) {
  if (kind === "music") return Music;
  if (kind === "ambience") return Volume2;
  return Wand2;
}

function originLabel(originId: EntityId | null | undefined): string {
  if (sameId(originId, ownerId.value)) return t("flows.sequences.config_panel.this_node");
  const source = compositionSources.value.find((item) => sameId(item.id, originId));
  return (
    source?.label ??
    (originId == null ? t("flows.sequences.config_panel.unknown_origin") : `#${originId}`)
  );
}

function ownerTypeLabel(): string {
  return t(`flows.node_types.${ownerType.value}`);
}

function fieldLabel(field: string): string {
  return t(`flows.sequences.config_panel.fields.${field}`);
}

function diagnosticLabel(code: string): string {
  const key = `flows.sequences.config_panel.diagnostic_messages.${code}`;
  const translated = t(key);

  return translated === key
    ? t("flows.sequences.config_panel.diagnostic_messages.fallback")
    : translated;
}
</script>

<template>
  <Sidebar side="right" :open="open" @close="close">
    <template #header>
      <div class="flex items-center justify-between py-2.5">
        <div class="min-w-0">
          <div class="flex items-center gap-2 text-sm font-medium">
            <Layers class="size-4" />
            {{ $t("flows.sequences.config_panel.title") }}
          </div>
          <p v-if="data" class="mt-0.5 text-[11px] text-muted-foreground">
            {{ ownerTypeLabel() }} · #{{ ownerId }}
          </p>
        </div>
        <Button
          type="button"
          variant="ghost"
          size="icon-xs"
          :title="$t('flows.preview.close')"
          :aria-label="$t('flows.preview.close')"
          @click="close"
        >
          <X class="size-4" aria-hidden="true" />
        </Button>
      </div>
    </template>

    <div v-if="data" class="flex min-w-0 flex-col gap-3 pb-4">
      <section class="rounded-lg border border-border bg-muted/20 p-3" data-composition-source>
        <div class="mb-2 flex items-center gap-2">
          <GitFork class="size-3.5 text-muted-foreground" />
          <span id="sequence-composition-source-label" class="text-xs font-medium">
            {{ $t("flows.sequences.config_panel.composition_source") }}
          </span>
        </div>
        <Select
          :model-value="sourceValue"
          :disabled="!canEdit"
          @update:model-value="setCompositionSource"
        >
          <SelectTrigger
            class="h-8 w-full text-xs"
            aria-labelledby="sequence-composition-source-label"
            data-composition-source-trigger
          >
            <SelectValue :placeholder="$t('flows.sequences.config_panel.no_source')" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem :value="ROOT_SOURCE_VALUE">
              {{ $t("flows.sequences.config_panel.no_source") }}
            </SelectItem>
            <SelectItem
              v-for="source in compositionSources"
              :key="source.id"
              :value="String(source.id)"
            >
              <span class="flex items-center gap-2">
                <Badge variant="outline" class="px-1 py-0 text-[9px]">{{ source.type }}</Badge>
                <span class="truncate">{{ source.label }}</span>
              </span>
            </SelectItem>
          </SelectContent>
        </Select>
        <p class="mt-2 text-[11px] leading-relaxed text-muted-foreground">
          {{ $t("flows.sequences.config_panel.composition_source_help") }}
        </p>
      </section>

      <div
        v-if="diagnostics.length > 0"
        class="rounded-lg border border-amber-500/30 bg-amber-500/10 p-2.5"
        data-composition-diagnostics
      >
        <p class="text-xs font-medium text-amber-700 dark:text-amber-300">
          {{ $t("flows.sequences.config_panel.diagnostics", { count: diagnostics.length }) }}
        </p>
        <ul class="mt-1 space-y-1 text-[11px] text-muted-foreground">
          <li v-for="diagnostic in diagnostics" :key="`${diagnostic.code}:${diagnostic.nodeId}`">
            {{ diagnosticLabel(diagnostic.code)
            }}<span v-if="diagnostic.nodeId"> · #{{ diagnostic.nodeId }}</span>
          </li>
        </ul>
      </div>

      <Tabs default-value="visual" class="flex min-w-0 flex-col gap-3">
        <TabsList class="grid h-8 w-full grid-cols-2">
          <TabsTrigger value="visual" class="gap-1.5 text-xs">
            <Layers class="size-3.5" />
            {{ $t("flows.sequences.visual_layers.title") }}
          </TabsTrigger>
          <TabsTrigger value="audio" class="gap-1.5 text-xs">
            <Music class="size-3.5" />
            {{ $t("flows.sequences.config_panel.audio_title") }}
          </TabsTrigger>
        </TabsList>

        <TabsContent value="visual" class="mt-0">
          <section class="flex min-w-0 flex-col gap-3">
            <div v-if="visualLayers.length > 0" class="flex min-w-0 flex-col gap-3">
              <article
                v-for="layer in visualLayers"
                :key="layerKey(layer)"
                class="flex min-w-0 flex-col gap-2 overflow-hidden rounded-lg border border-border bg-muted/20 p-2.5"
                :data-layer-key="layerKey(layer)"
              >
                <div class="flex min-w-0 items-center gap-2">
                  <Badge
                    :variant="ownerDefinesLayer(layer) ? 'secondary' : 'outline'"
                    class="shrink-0 text-[10px]"
                  >
                    {{ layerStatusLabel(layer) }}
                  </Badge>
                  <span class="min-w-0 flex-1 truncate text-[11px] text-muted-foreground">
                    {{ $t("flows.sequences.config_panel.from") }}
                    {{ originLabel(layer.origin?.nodeId ?? layerSequenceId(layer)) }}
                  </span>
                  <Button
                    v-if="canEdit"
                    type="button"
                    variant="ghost"
                    size="icon-xs"
                    :title="$t('flows.sequences.visual_layers.delete')"
                    data-remove-layer
                    @click="removeVisualLayer(layer)"
                  >
                    <X class="size-3" />
                  </Button>
                </div>

                <div
                  v-if="layerHasLocalPatch(layer)"
                  class="flex flex-wrap items-center gap-1 rounded border border-border/70 bg-background/70 p-1.5"
                  data-layer-overrides
                >
                  <span class="mr-1 text-[10px] text-muted-foreground">
                    {{ $t("flows.sequences.config_panel.local_fields") }}
                  </span>
                  <Button
                    v-for="field in layerOverrideFields(layer)"
                    :key="field"
                    type="button"
                    variant="outline"
                    size="xs"
                    class="h-6 gap-1 px-1.5 text-[10px]"
                    :disabled="!canEdit"
                    :data-revert-field="field"
                    :title="
                      $t('flows.sequences.config_panel.revert_field_from', {
                        origin: fieldOriginLabel(layer, field),
                      })
                    "
                    @click="revertVisualLayer(layer, [field])"
                  >
                    <Undo2 class="size-2.5" />
                    {{ fieldLabel(field) }}
                  </Button>
                </div>

                <ImageAsset
                  :label="layer.label || $t(`flows.sequences.visual_layers.kinds.${layer.kind}`)"
                  :icon="kindIcon(layer.kind)"
                  :asset-id="layerAssetId(layer)"
                  :image-assets="data.image_assets || []"
                  :can-edit="canEdit"
                  :pick-placeholder="$t('flows.sequences.visual_layers.pick_asset')"
                  :search-placeholder="$t('flows.sequences.config_panel.search_image')"
                  :clear-title="$t('flows.sequences.visual_layers.delete')"
                  :preview-fit="layer.fit || 'contain'"
                  :search-event="PICKER_SEARCH_EVENT"
                  :search-payload="IMAGE_ASSET_SEARCH_PAYLOAD"
                  @select="
                    (asset) =>
                      updateVisualLayer(layer, { asset_id: asset.id, label: asset.filename })
                  "
                  @clear="removeVisualLayer(layer)"
                />

                <div class="grid min-w-0 grid-cols-2 gap-2">
                  <div class="flex min-w-0 flex-col gap-1 text-[11px] text-muted-foreground">
                    <span :title="fieldOriginLabel(layer, 'kind')">
                      {{ $t("flows.sequences.visual_layers.kind") }}
                    </span>
                    <Popover :open="pickerOpen(layer)" @update:open="setPickerOpen(layer, $event)">
                      <PopoverTrigger as-child>
                        <Button
                          variant="outline"
                          size="sm"
                          class="h-8 w-full min-w-0 shrink justify-between overflow-hidden px-2 text-xs font-normal"
                          :disabled="!canEdit"
                        >
                          <span class="min-w-0 flex-1 truncate text-left text-foreground">
                            {{ visualKindLabel(layer.kind) }}
                          </span>
                          <ChevronDown class="size-3 shrink-0 opacity-50" />
                        </Button>
                      </PopoverTrigger>
                      <PopoverContent
                        class="w-(--reka-popover-trigger-width) min-w-32 p-0"
                        align="start"
                        :side-offset="4"
                      >
                        <Command>
                          <CommandList>
                            <CommandGroup>
                              <CommandItem
                                v-for="kind in VISUAL_KINDS"
                                :key="kind"
                                :value="visualKindLabel(kind)"
                                class="gap-2 text-xs"
                                @select="pickVisualKind(layer, kind)"
                              >
                                <component :is="kindIcon(kind)" class="size-3.5 shrink-0" />
                                <span class="min-w-0 flex-1 truncate">{{
                                  visualKindLabel(kind)
                                }}</span>
                                <Check v-if="layer.kind === kind" class="size-3 shrink-0" />
                              </CommandItem>
                            </CommandGroup>
                          </CommandList>
                        </Command>
                      </PopoverContent>
                    </Popover>
                  </div>

                  <div class="flex flex-col gap-1 text-[11px] text-muted-foreground">
                    <span :title="fieldOriginLabel(layer, 'slot')">
                      {{ $t("flows.sequences.visual_layers.layout") }}
                    </span>
                    <ToggleGroup
                      type="single"
                      variant="outline"
                      size="xs"
                      :model-value="layoutModeForLayer(layer)"
                      :disabled="!canEdit"
                      class="w-full"
                      @update:model-value="setVisualLayoutMode(layer, $event)"
                    >
                      <ToggleGroupItem value="full" class="flex-1 text-xs">
                        {{ $t("flows.sequences.visual_layers.layout_modes.full") }}
                      </ToggleGroupItem>
                      <ToggleGroupItem value="positioned" class="flex-1 text-xs">
                        {{ $t("flows.sequences.visual_layers.layout_modes.positioned") }}
                      </ToggleGroupItem>
                    </ToggleGroup>
                  </div>
                </div>

                <ImagePosition
                  v-if="layoutModeForLayer(layer) === 'positioned'"
                  :position="positionForLayer(layer)"
                  :fit="layer.fit || 'contain'"
                  :can-edit="canEdit"
                  :position-label="$t('flows.sequences.config_panel.position_label')"
                  :fit-label="$t('flows.sequences.config_panel.fit_label')"
                  @position-change="(slot) => setVisualSlot(layer, slot)"
                  @fit-change="(fit) => setVisualFit(layer, fit)"
                />

                <ImageFit
                  v-else
                  :fit="layer.fit || 'contain'"
                  :can-edit="canEdit"
                  :fit-label="$t('flows.sequences.config_panel.fit_label')"
                  @fit-change="(fit) => setVisualFit(layer, fit)"
                />

                <div class="grid grid-cols-2 gap-2 sm:grid-cols-3">
                  <label
                    v-for="definition in NUMERIC_LAYER_FIELDS"
                    :key="definition.field"
                    class="flex min-w-0 flex-col gap-1 text-[10px] text-muted-foreground"
                    :title="fieldOriginLabel(layer, definition.field)"
                  >
                    {{ fieldLabel(definition.field) }}
                    <input
                      type="number"
                      class="h-7 min-w-0 rounded-md border border-input bg-background px-2 text-xs tabular-nums text-foreground outline-none focus:border-ring focus:ring-2 focus:ring-ring/30 disabled:opacity-50"
                      :min="definition.min"
                      :max="definition.max"
                      :step="definition.step"
                      :value="numericLayerValue(layer, definition.field)"
                      :disabled="!canEdit"
                      :data-layer-field="definition.field"
                      @change="setNumericLayerField(layer, definition.field, $event)"
                    />
                  </label>
                </div>

                <label class="flex items-center gap-2 text-[11px] text-muted-foreground">
                  <span class="w-14" :title="fieldOriginLabel(layer, 'opacity')">
                    {{ $t("flows.sequences.visual_layers.opacity") }}
                  </span>
                  <input
                    class="flex-1 accent-primary"
                    type="range"
                    min="0"
                    max="100"
                    step="1"
                    :value="Math.round((layer.opacity ?? 1) * 100)"
                    :disabled="!canEdit"
                    data-layer-opacity
                    @change="setVisualOpacity(layer, $event)"
                  />
                  <span class="w-8 text-right tabular-nums">{{
                    Math.round((layer.opacity ?? 1) * 100)
                  }}</span>
                </label>

                <div class="flex items-center justify-between text-[11px] text-muted-foreground">
                  <span :title="fieldOriginLabel(layer, 'visible')">
                    {{ $t("flows.sequences.config_panel.fields.visible") }}
                  </span>
                  <Switch
                    :model-value="layer.visible !== false"
                    :disabled="!canEdit"
                    :aria-label="`${$t('flows.sequences.config_panel.fields.visible')}: ${layer.label || visualKindLabel(layer.kind)}`"
                    data-layer-visible
                    @update:model-value="setVisualVisibility(layer, $event)"
                  />
                </div>
              </article>
            </div>

            <p
              v-else
              class="rounded-lg border border-dashed border-border p-4 text-center text-xs text-muted-foreground"
            >
              {{ $t("flows.sequences.config_panel.no_visual_layers") }}
            </p>

            <div class="grid min-w-0 grid-cols-2 gap-2">
              <ImageAsset
                v-for="kind in VISUAL_KINDS"
                :key="kind"
                :label="addLayerLabel(kind)"
                :icon="kindIcon(kind)"
                :image-assets="data.image_assets || []"
                :can-edit="canEdit"
                :pick-placeholder="$t('flows.sequences.visual_layers.pick_asset')"
                :search-placeholder="$t('flows.sequences.config_panel.search_image')"
                :search-event="PICKER_SEARCH_EVENT"
                :search-payload="IMAGE_ASSET_SEARCH_PAYLOAD"
                @select="(asset) => createVisualLayer(kind, asset)"
              />
            </div>

            <section
              v-if="removedVisualLayers.length > 0"
              class="rounded-lg border border-dashed border-border p-2.5"
            >
              <p class="mb-2 text-[11px] font-medium text-muted-foreground">
                {{ $t("flows.sequences.config_panel.removed_layers") }}
              </p>
              <div class="space-y-1">
                <div
                  v-for="layer in removedVisualLayers"
                  :key="layerKey(layer)"
                  class="flex items-center gap-2 rounded bg-muted/40 px-2 py-1.5 text-xs"
                  :data-removed-layer-key="layerKey(layer)"
                >
                  <component :is="kindIcon(layer.kind)" class="size-3.5 text-muted-foreground" />
                  <span class="min-w-0 flex-1 truncate">{{ layer.label || layerKey(layer) }}</span>
                  <Button
                    type="button"
                    variant="ghost"
                    size="xs"
                    class="gap-1"
                    :disabled="!canEdit"
                    data-restore-layer
                    @click="restoreVisualLayer(layer)"
                  >
                    <RotateCcw class="size-3" />
                    {{ $t("flows.sequences.config_panel.restore") }}
                  </Button>
                </div>
              </div>
            </section>
          </section>
        </TabsContent>

        <TabsContent value="audio" class="mt-0">
          <section class="flex min-w-0 flex-col gap-3">
            <article
              v-for="track in tracks"
              :key="trackKey(track)"
              class="rounded-lg border border-border bg-muted/20 p-2"
              :data-track-key="trackKey(track)"
            >
              <div class="mb-2 flex min-w-0 items-center gap-2 px-0.5">
                <Badge
                  :variant="ownerDefinesTrack(track) ? 'secondary' : 'outline'"
                  class="shrink-0 text-[10px]"
                >
                  {{ trackStatusLabel(track) }}
                </Badge>
                <span class="min-w-0 flex-1 truncate text-[11px] text-muted-foreground">
                  {{ $t("flows.sequences.config_panel.from") }}
                  {{ originLabel(trackSequenceId(track)) }}
                </span>
                <Button
                  v-if="trackHasLocalPatch(track)"
                  type="button"
                  variant="ghost"
                  size="icon-xs"
                  :disabled="!canEdit"
                  :title="$t('flows.sequences.config_panel.revert_all')"
                  :aria-label="$t('flows.sequences.config_panel.revert_all')"
                  data-revert-track
                  @click="revertTrack(track, trackOverrideFields(track))"
                >
                  <Undo2 class="size-3" aria-hidden="true" />
                </Button>
              </div>
              <div
                v-if="trackHasLocalPatch(track)"
                class="mb-2 flex flex-wrap items-center gap-1 rounded border border-border/70 bg-background/70 p-1.5"
                data-track-overrides
              >
                <span class="mr-1 text-[10px] text-muted-foreground">
                  {{ $t("flows.sequences.config_panel.local_fields") }}
                </span>
                <Button
                  v-for="field in trackOverrideFields(track)"
                  :key="field"
                  type="button"
                  variant="outline"
                  size="xs"
                  class="h-6 gap-1 px-1.5 text-[10px]"
                  :disabled="!canEdit"
                  :data-revert-track-field="field"
                  :title="
                    $t('flows.sequences.config_panel.revert_field_from', {
                      origin: trackFieldOriginLabel(track, field),
                    })
                  "
                  @click="revertTrack(track, [field])"
                >
                  <Undo2 class="size-2.5" aria-hidden="true" />
                  {{ fieldLabel(field) }}
                </Button>
              </div>
              <AudioAsset
                :label="$t(`flows.sequences.tracks.${track.kind}`)"
                :icon="trackIcon(track.kind)"
                :asset-id="trackAssetId(track)"
                :volume="trackVolumePercent(track)"
                :audio-assets="data.audio_assets || []"
                :can-edit="canEdit"
                :pick-placeholder="$t('flows.sequences.config_panel.pick_audio')"
                :search-placeholder="$t('flows.sequences.config_panel.search_audio')"
                :clear-title="$t('flows.sequences.config_panel.remove_track')"
                :search-event="PICKER_SEARCH_EVENT"
                :search-payload="AUDIO_ASSET_SEARCH_PAYLOAD"
                @select="(asset) => pickTrackAsset(track, asset)"
                @clear="removeTrack(track)"
                @volume-change="(percent) => onTrackVolumeChange(track, percent)"
              />
              <dl
                class="mt-2 grid grid-cols-2 gap-1.5 text-[10px] sm:grid-cols-3"
                data-track-property-origins
              >
                <div
                  v-for="field in trackOriginFields(track)"
                  :key="field"
                  class="min-w-0 rounded border border-border/70 bg-background/70 px-2 py-1"
                  :data-track-property-origin="field"
                >
                  <dt class="truncate text-muted-foreground">{{ fieldLabel(field) }}</dt>
                  <dd class="truncate font-medium" :title="trackFieldOriginLabel(track, field)">
                    {{ trackFieldOriginLabel(track, field) }}
                  </dd>
                </div>
              </dl>
            </article>

            <div v-if="missingTrackKinds.length > 0" class="space-y-2">
              <p class="text-[11px] font-medium text-muted-foreground">
                {{ $t("flows.sequences.config_panel.add_track") }}
              </p>
              <AudioAsset
                v-for="kind in missingTrackKinds"
                :key="kind"
                :label="$t(`flows.sequences.tracks.${kind}`)"
                :icon="trackIcon(kind)"
                :audio-assets="data.audio_assets || []"
                :can-edit="canEdit"
                :pick-placeholder="$t('flows.sequences.config_panel.pick_audio')"
                :search-placeholder="$t('flows.sequences.config_panel.search_audio')"
                :search-event="PICKER_SEARCH_EVENT"
                :search-payload="AUDIO_ASSET_SEARCH_PAYLOAD"
                @select="(asset) => createTrack(kind, asset)"
              />
            </div>

            <section
              v-if="removedTracks.length > 0"
              class="rounded-lg border border-dashed border-border p-2.5"
            >
              <p class="mb-2 text-[11px] font-medium text-muted-foreground">
                {{ $t("flows.sequences.config_panel.removed_tracks") }}
              </p>
              <div class="space-y-1">
                <div
                  v-for="track in removedTracks"
                  :key="trackKey(track)"
                  class="flex items-center gap-2 rounded bg-muted/40 px-2 py-1.5 text-xs"
                  :data-removed-track-key="trackKey(track)"
                >
                  <component :is="trackIcon(track.kind)" class="size-3.5 text-muted-foreground" />
                  <span class="min-w-0 flex-1 truncate">{{
                    $t(`flows.sequences.tracks.${track.kind}`)
                  }}</span>
                  <Button
                    type="button"
                    variant="ghost"
                    size="xs"
                    class="gap-1"
                    :disabled="!canEdit"
                    data-restore-track
                    @click="restoreTrack(track)"
                  >
                    <RotateCcw class="size-3" />
                    {{ $t("flows.sequences.config_panel.restore") }}
                  </Button>
                </div>
              </div>
            </section>
          </section>
        </TabsContent>
      </Tabs>
    </div>
  </Sidebar>
</template>
