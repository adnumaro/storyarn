<script setup lang="ts">
/**
 * Right sidebar opened when a sequence is selected on the canvas.
 *
 * Sequences define stage context for the flow player: visual layers
 * compose parent-to-child, and audio tracks play as sequence-level sound.
 */
import {
  Box,
  Image as ImageIcon,
  Layers,
  Music,
  Sparkles,
  UserRound,
  Volume2,
  Wand2,
  X,
} from "lucide-vue-next";
import { computed, type Component } from "vue";
import { useI18n } from "vue-i18n";

import AudioAsset from "../../../../../components/forms/assets/AudioAsset.vue";
import ImageAsset from "../../../../../components/forms/assets/ImageAsset.vue";
import { Button } from "../../../../../components/ui/button";
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
type VisualSlot = "full" | "left" | "center" | "right" | "custom";
type VisualFit = "cover" | "contain" | "fill";

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

const TRACK_KINDS = ["music", "ambience", "sfx"] as const;
const VISUAL_KINDS: readonly VisualKind[] = ["backdrop", "character", "prop", "overlay"];
const VISUAL_SLOTS: readonly VisualSlot[] = ["full", "left", "center", "right", "custom"];
const VISUAL_FITS: readonly VisualFit[] = ["cover", "contain", "fill"];

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
  updateVisualLayer(layer, { slot, ...geometryForSlot(layer.kind, slot) });
}

function setVisualFit(layer: SequenceVisualLayer, fit: string) {
  updateVisualLayer(layer, { fit: fit as VisualFit });
}

function setVisualKind(layer: SequenceVisualLayer, kind: string) {
  const slot = defaultSlot(kind);
  updateVisualLayer(layer, { kind, slot, ...geometryForSlot(kind, slot) });
}

function setVisualOpacity(layer: SequenceVisualLayer, event: Event) {
  const value = Number((event.target as HTMLInputElement).value);
  if (!Number.isFinite(value)) return;
  updateVisualLayer(layer, { opacity: value / 100 });
}

function eventValue(event: Event): string {
  return (event.target as HTMLSelectElement).value;
}

function defaultSlot(kind: string): VisualSlot {
  if (kind === "backdrop" || kind === "overlay") return "full";
  if (kind === "character") return "center";
  return "custom";
}

function geometryForSlot(kind: string, slot: string): Partial<SequenceVisualLayer> {
  if (kind === "backdrop" || kind === "overlay" || slot === "full") {
    return {
      x: 0,
      y: 0,
      width: 1,
      height: 1,
      anchor_x: 0,
      anchor_y: 0,
      fit: kind === "backdrop" || kind === "overlay" ? "cover" : "contain",
    };
  }

  if (kind === "character") {
    let x = 0.5;
    if (slot === "left") x = 0.25;
    if (slot === "right") x = 0.75;

    const width = slot === "center" ? 0.42 : 0.38;
    return {
      x,
      y: 1,
      width,
      height: 0.9,
      anchor_x: 0.5,
      anchor_y: 1,
      fit: "contain",
    };
  }

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

    <div class="flex flex-col gap-6">
      <section class="flex flex-col gap-3">
        <header
          class="flex items-center gap-2 text-xs font-medium uppercase tracking-wide text-muted-foreground"
        >
          <Layers class="size-3.5" />
          {{ $t("flows.sequences.visual_layers.title") }}
        </header>

        <div class="grid grid-cols-2 gap-2">
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

        <div v-if="visualLayers.length > 0" class="flex flex-col gap-3">
          <article
            v-for="layer in visualLayers"
            :key="layer.id"
            class="rounded border border-border bg-muted/20 p-2 flex flex-col gap-2"
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
                (asset) => updateVisualLayer(layer, { asset_id: asset.id, label: asset.filename })
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

            <div class="grid grid-cols-3 gap-2">
              <label class="flex flex-col gap-1 text-[11px] text-muted-foreground">
                {{ $t("flows.sequences.visual_layers.kind") }}
                <select
                  class="h-8 rounded border border-border bg-background px-2 text-xs text-foreground"
                  :value="layer.kind"
                  :disabled="!canEdit"
                  @change="setVisualKind(layer, eventValue($event))"
                >
                  <option v-for="kind in VISUAL_KINDS" :key="kind" :value="kind">
                    {{ $t(`flows.sequences.visual_layers.kinds.${kind}`) }}
                  </option>
                </select>
              </label>

              <label class="flex flex-col gap-1 text-[11px] text-muted-foreground">
                {{ $t("flows.sequences.visual_layers.slot") }}
                <select
                  class="h-8 rounded border border-border bg-background px-2 text-xs text-foreground"
                  :value="layer.slot || defaultSlot(layer.kind)"
                  :disabled="!canEdit"
                  @change="setVisualSlot(layer, eventValue($event))"
                >
                  <option v-for="slot in VISUAL_SLOTS" :key="slot" :value="slot">
                    {{ $t(`flows.sequences.visual_layers.slots.${slot}`) }}
                  </option>
                </select>
              </label>

              <label class="flex flex-col gap-1 text-[11px] text-muted-foreground">
                {{ $t("flows.sequences.visual_layers.fit") }}
                <select
                  class="h-8 rounded border border-border bg-background px-2 text-xs text-foreground"
                  :value="layer.fit || 'contain'"
                  :disabled="!canEdit"
                  @change="setVisualFit(layer, eventValue($event))"
                >
                  <option v-for="fit in VISUAL_FITS" :key="fit" :value="fit">
                    {{ $t(`common.assets.image.fit_${fit}`) }}
                  </option>
                </select>
              </label>
            </div>

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

      <section class="flex flex-col gap-3">
        <header
          class="flex items-center gap-2 text-xs font-medium uppercase tracking-wide text-muted-foreground"
        >
          <Music class="size-3.5" />
          {{ $t("flows.sequences.config_panel.audio_title") }}
        </header>

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
    </div>
  </Sidebar>
</template>
