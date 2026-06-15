<script setup lang="ts">
/**
 * Right sidebar opened when a sequence is selected on the canvas.
 *
 * Sequences define stage context for the flow player: visual layers
 * compose parent-to-child, and audio tracks play as sequence-level sound.
 */
import {
  Box,
  Check,
  ChevronDown,
  Image as ImageIcon,
  Layers,
  Music,
  Sparkles,
  UserRound,
  Volume2,
  Wand2,
  X,
} from "lucide-vue-next";
import { computed, ref, type Component } from "vue";
import { useI18n } from "vue-i18n";

import AudioAsset from "../../../../../components/forms/assets/AudioAsset.vue";
import ImageAsset from "../../../../../components/forms/assets/ImageAsset.vue";
import ImageFit from "../../../../../components/forms/assets/ImageFit.vue";
import ImagePosition from "../../../../../components/forms/assets/ImagePosition.vue";
import { Button } from "../../../../../components/ui/button";
import { Command, CommandGroup, CommandItem, CommandList } from "../../../../../components/ui/command";
import { Popover, PopoverContent, PopoverTrigger } from "../../../../../components/ui/popover";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "../../../../../components/ui/tabs";
import { ToggleGroup, ToggleGroupItem } from "../../../../../components/ui/toggle-group";
import Sidebar from "../../../../../shell/Sidebar.vue";
import { useLive } from "../../../../../shared/composables/useLive";

interface AssetEntry {
  id: number | string;
  filename: string;
  url?: string | null;
  content_type?: string | null;
}

interface SequenceConfig {
  name?: string | null;
  width?: number | null;
  height?: number | null;
}

interface SequenceVisualLayer {
  id: number | string;
  kind: string;
  label?: string | null;
  asset_id?: number | string | null;
  z_index?: number | null;
  slot?: string | null;
  x?: number | null;
  y?: number | null;
  width?: number | null;
  height?: number | null;
  anchor_x?: number | null;
  anchor_y?: number | null;
  fit?: "cover" | "contain" | "fill" | null;
  opacity?: number | null;
  visible?: boolean | null;
}

interface SequenceTrack {
  kind: string;
  asset_id?: number | string | null;
  volume?: number | null;
}

interface PanelData {
  sequence_id: number | string;
  config: SequenceConfig | null;
  visual_layers: SequenceVisualLayer[];
  tracks: SequenceTrack[];
  image_assets: AssetEntry[];
  audio_assets: AssetEntry[];
}

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

const TRACK_KINDS = ["music", "ambience", "sfx"] as const;
const VISUAL_KINDS: readonly VisualKind[] = ["backdrop", "character", "prop", "overlay"];
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
] as const;

const sequenceId = computed(() => data?.sequence_id ?? null);

const visualLayers = computed(() =>
  [...(data?.visual_layers || [])].sort((a, b) => {
    const zDelta = (a.z_index ?? 0) - (b.z_index ?? 0);
    if (zDelta !== 0) return zDelta;
    return String(a.id).localeCompare(String(b.id));
  }),
);

function close() {
  live.pushEvent("close_sequence_config", {});
}

function pushSequenceEvent(event: string, payload: Record<string, unknown>) {
  if (!sequenceId.value) return;
  live.pushEvent(event, {
    id: sequenceId.value,
    ...payload,
  });
}

function createVisualLayer(kind: VisualKind, asset: AssetEntry) {
  pushSequenceEvent("create_sequence_visual_layer", {
    kind,
    asset_id: asset.id,
    label: asset.filename,
    slot: defaultSlot(kind),
  });
}

function updateVisualLayer(layer: SequenceVisualLayer, patch: Partial<SequenceVisualLayer>) {
  pushSequenceEvent("update_sequence_visual_layer", {
    layer_id: layer.id,
    ...patch,
  });
}

function deleteVisualLayer(layer: SequenceVisualLayer) {
  pushSequenceEvent("delete_sequence_visual_layer", { layer_id: layer.id });
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
  if (!Number.isFinite(value)) return;
  updateVisualLayer(layer, { opacity: value / 100 });
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
  if (!mode) return;
  setVisualSlot(layer, mode === "full" ? "full" : positionForLayer(layer));
}

function geometryForSlot(kind: string, slot: string): Partial<SequenceVisualLayer> {
  if (kind === "backdrop" || slot === "full") {
    return fullLayerGeometry(kind);
  }

  if (kind === "character") {
    return characterLayerGeometry(slot);
  }

  if (isPositionSlot(slot)) {
    return positionedLayerGeometry(slot);
  }

  return centeredLayerGeometry();
}

function fullLayerGeometry(kind: string): Partial<SequenceVisualLayer> {
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
  if (kind === "backdrop" || kind === "overlay") return "cover";
  return "contain";
}

function characterLayerGeometry(slot: string): Partial<SequenceVisualLayer> {
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

function positionedLayerGeometry(slot: PositionSlot): Partial<SequenceVisualLayer> {
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

function centeredLayerGeometry(): Partial<SequenceVisualLayer> {
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
  if (col === "center") return 0.42;
  return 0.38;
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

function trackFor(kind: string): SequenceTrack | null {
  if (!data?.tracks) return null;
  return data.tracks.find((t) => t.kind === kind) ?? null;
}

function trackVolumePercent(kind: string): number | null {
  const t = trackFor(kind);
  if (!t || t.volume == null) return null;
  return Math.round(Number(t.volume) * 100);
}

function pickTrackAsset(kind: string, asset: AssetEntry) {
  pushSequenceEvent("upsert_sequence_track", {
    kind,
    asset_id: asset.id,
  });
}

function clearTrack(kind: string) {
  pushSequenceEvent("clear_sequence_track", { kind });
}

function onVolumeChange(kind: string, percent: number) {
  pushSequenceEvent("upsert_sequence_track", {
    kind,
    volume: percent / 100,
  });
}

function trackIcon(kind: string) {
  if (kind === "music") return Music;
  if (kind === "ambience") return Volume2;
  return Wand2;
}

function pickerKey(layer: SequenceVisualLayer, field: "kind"): string {
  return `${field}:${layer.id}`;
}

function pickerOpen(layer: SequenceVisualLayer, field: "kind"): boolean {
  return openLayerPicker.value === pickerKey(layer, field);
}

function setPickerOpen(layer: SequenceVisualLayer, field: "kind", open: boolean) {
  openLayerPicker.value = open ? pickerKey(layer, field) : null;
}

function visualKindLabel(kind: string): string {
  return t(`flows.sequences.visual_layers.kinds.${kind}`);
}

</script>

<template>
  <Sidebar side="right" :open="open" @close="close">
    <template #header>
      <div class="flex items-center justify-between py-2.5">
        <div class="flex items-center gap-2 text-sm font-medium">
          <Layers class="size-4" />
          {{ $t("flows.sequences.config_panel.title") }}
        </div>
        <Button type="button" variant="ghost" size="icon-xs" @click="close">
          <X class="size-4" />
        </Button>
      </div>
    </template>

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
          <div class="grid min-w-0 grid-cols-2 gap-2">
            <ImageAsset
              v-for="kind in VISUAL_KINDS"
              :key="kind"
              :label="addLayerLabel(kind)"
              :icon="kindIcon(kind)"
              :image-assets="data?.image_assets || []"
              :can-edit="canEdit"
              :pick-placeholder="$t('flows.sequences.visual_layers.pick_asset')"
              :search-placeholder="$t('flows.sequences.config_panel.search_image')"
              @select="(asset) => createVisualLayer(kind, asset)"
            />
          </div>

          <div v-if="visualLayers.length > 0" class="flex min-w-0 flex-col gap-3">
            <article
              v-for="layer in visualLayers"
              :key="layer.id"
              class="flex min-w-0 flex-col gap-2 overflow-hidden rounded border border-border bg-muted/20 p-2"
            >
              <ImageAsset
                :label="layer.label || $t(`flows.sequences.visual_layers.kinds.${layer.kind}`)"
                :icon="kindIcon(layer.kind)"
                :asset-id="layer.asset_id"
                :image-assets="data?.image_assets || []"
                :can-edit="canEdit"
                :pick-placeholder="$t('flows.sequences.visual_layers.pick_asset')"
                :search-placeholder="$t('flows.sequences.config_panel.search_image')"
                :clear-title="$t('flows.sequences.visual_layers.delete')"
                :preview-fit="layer.fit || 'contain'"
                @select="
                  (asset) =>
                    updateVisualLayer(layer, { asset_id: asset.id, label: asset.filename })
                "
                @clear="deleteVisualLayer(layer)"
              >
                <template #header-actions>
                  <Button
                    v-if="canEdit"
                    variant="ghost"
                    size="icon-xs"
                    :title="$t('flows.sequences.visual_layers.delete')"
                    @click="deleteVisualLayer(layer)"
                  >
                    <X class="size-3" />
                  </Button>
                </template>
              </ImageAsset>

              <div class="grid min-w-0 grid-cols-2 gap-2">
                <div class="flex min-w-0 flex-col gap-1 text-[11px] text-muted-foreground">
                  {{ $t("flows.sequences.visual_layers.kind") }}
                  <Popover
                    :open="pickerOpen(layer, 'kind')"
                    @update:open="setPickerOpen(layer, 'kind', $event)"
                  >
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
                              <span class="min-w-0 flex-1 truncate">
                                {{ visualKindLabel(kind) }}
                              </span>
                              <Check v-if="layer.kind === kind" class="size-3 shrink-0" />
                            </CommandItem>
                          </CommandGroup>
                        </CommandList>
                      </Command>
                    </PopoverContent>
                  </Popover>
                </div>

                <div class="flex flex-col gap-1 text-[11px] text-muted-foreground">
                  {{ $t("flows.sequences.visual_layers.layout") }}
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

              <label class="flex items-center gap-2 text-[11px] text-muted-foreground">
                <span class="w-14">{{ $t("flows.sequences.visual_layers.opacity") }}</span>
                <input
                  class="flex-1 accent-primary"
                  type="range"
                  min="0"
                  max="100"
                  step="1"
                  :value="Math.round((layer.opacity ?? 1) * 100)"
                  :disabled="!canEdit"
                  @input="setVisualOpacity(layer, $event)"
                />
                <span class="w-8 text-right tabular-nums">
                  {{ Math.round((layer.opacity ?? 1) * 100) }}
                </span>
              </label>
            </article>
          </div>
        </section>
      </TabsContent>

      <TabsContent value="audio" class="mt-0">
        <section class="flex min-w-0 flex-col gap-3">
          <AudioAsset
            v-for="kind in TRACK_KINDS"
            :key="kind"
            :label="$t(`flows.sequences.tracks.${kind}`)"
            :icon="trackIcon(kind)"
            :asset-id="trackFor(kind)?.asset_id"
            :volume="trackVolumePercent(kind)"
            :audio-assets="data?.audio_assets || []"
            :can-edit="canEdit"
            :pick-placeholder="$t('flows.sequences.config_panel.pick_audio')"
            :search-placeholder="$t('flows.sequences.config_panel.search_audio')"
            :clear-title="$t('flows.sequences.config_panel.clear_track')"
            @select="(asset) => pickTrackAsset(kind, asset)"
            @clear="clearTrack(kind)"
            @volume-change="(percent) => onVolumeChange(kind, percent)"
          />
        </section>
      </TabsContent>
    </Tabs>
  </Sidebar>
</template>
