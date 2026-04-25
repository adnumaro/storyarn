<script setup lang="ts">
/**
 * Right sidebar opened when a sequence is selected on the canvas.
 *
 * Sections:
 *   1. Background image: asset picker + 9-cell position grid + fit selector.
 *   2. Audio tracks: one row per kind (background | music | ambient) with
 *      asset picker + volume slider + clear.
 *
 * Server events (see `GenericNodeHandlers`):
 *   - `update_sequence_config` — patches background_asset_id /
 *     background_position / background_fit. Partial payload; only fields
 *     the user just touched get sent.
 *   - `upsert_sequence_track` — sets asset_id and/or volume for a kind.
 *   - `clear_sequence_track` — deletes the track row.
 *
 * Name editing lives in the floating toolbar (`SequenceToolbar.vue`), not
 * here — kept the sidebar scoped to media config so it can grow into
 * heavier tooling (per-track timeline, clip-trim) without crowding the
 * always-visible toolbar.
 */
import { Image as ImageIcon, Layers, Music, Volume2, X } from "lucide-vue-next";
import { computed } from "vue";

import AssetPicker from "@components/AssetPicker.vue";
import AudioAsset from "@components/assets/AudioAsset.vue";
import Sidebar from "@components/layout/Sidebar.vue";
import { Button } from "@components/ui/button/index.ts";
import { useLive } from "@composables/useLive";

interface AssetEntry {
  id: number | string;
  filename: string;
  url?: string | null;
  content_type?: string | null;
}

interface SequenceConfig {
  name?: string | null;
  background_asset_id?: number | string | null;
  background_position?: string | null;
  background_fit?: string | null;
}

interface SequenceTrack {
  kind: string;
  asset_id?: number | string | null;
  volume?: number | null;
}

interface PanelData {
  sequence_id: number | string;
  config: SequenceConfig | null;
  tracks: SequenceTrack[];
  image_assets: AssetEntry[];
  audio_assets: AssetEntry[];
}

const { open = false, data = null, canEdit = false } = defineProps<{
  open?: boolean;
  data?: PanelData | null;
  canEdit?: boolean;
}>();

const live = useLive();

const TRACK_KINDS = ["background", "music", "ambient"] as const;

const BACKGROUND_POSITIONS = [
  "top-left",
  "top-center",
  "top-right",
  "center-left",
  "center",
  "center-right",
  "bottom-left",
  "bottom-center",
  "bottom-right",
] as const;

const BACKGROUND_FITS = ["cover", "contain", "fill"] as const;

const sequenceId = computed(() => data?.sequence_id ?? null);

const backgroundAssetId = computed(() => data?.config?.background_asset_id ?? null);
const backgroundPosition = computed(() => data?.config?.background_position ?? "center");
const backgroundFit = computed(() => data?.config?.background_fit ?? "cover");

const backgroundAsset = computed<AssetEntry | null>(() => {
  if (!data?.config?.background_asset_id) return null;
  return (
    data.image_assets.find(
      (a) => String(a.id) === String(data.config!.background_asset_id),
    ) ?? null
  );
});

function close() {
  // Closing the panel keeps the sequence selected (toolbar stays visible).
  // Mirrors `close_builder` / `close_editor` — sidebar dismiss != deselect.
  live.pushEvent("close_sequence_config", {});
}

function pushConfig(patch: Partial<SequenceConfig>) {
  if (!sequenceId.value) return;
  live.pushEvent("update_sequence_config", {
    id: sequenceId.value,
    ...patch,
  });
}

function pickBackgroundImage(asset: AssetEntry) {
  pushConfig({ background_asset_id: asset.id });
}

function clearBackgroundImage() {
  pushConfig({ background_asset_id: null });
}

function setBackgroundPosition(pos: string) {
  pushConfig({ background_position: pos });
}

function setBackgroundFit(fit: string) {
  pushConfig({ background_fit: fit });
}

// --- Tracks ----------------------------------------------------------------

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
  if (!sequenceId.value) return;
  live.pushEvent("upsert_sequence_track", {
    id: sequenceId.value,
    kind,
    asset_id: asset.id,
  });
}

function clearTrack(kind: string) {
  if (!sequenceId.value) return;
  live.pushEvent("clear_sequence_track", {
    id: sequenceId.value,
    kind,
  });
}

function onVolumeChange(kind: string, percent: number) {
  if (!sequenceId.value) return;
  live.pushEvent("upsert_sequence_track", {
    id: sequenceId.value,
    kind,
    volume: percent / 100,
  });
}

function trackIcon(kind: string) {
  if (kind === "music") return Music;
  if (kind === "ambient") return Volume2;
  return Layers;
}
</script>

<template>
  <Sidebar side="right" :open="open" @close="close">
    <template #header>
      <div class="flex items-center justify-between px-3 py-2.5">
        <div class="flex items-center gap-2 text-sm font-medium">
          <Layers class="size-4" />
          {{ $t("flows.sequences.config_panel.title") }}
        </div>
        <button
          type="button"
          class="p-1 rounded hover:bg-muted transition-colors text-muted-foreground hover:text-foreground"
          @click="close"
        >
          <X class="size-4" />
        </button>
      </div>
    </template>

    <div class="flex flex-col gap-6 p-4">
      <!-- Background image section -->
      <section class="flex flex-col gap-3">
        <header class="flex items-center gap-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">
          <ImageIcon class="size-3.5" />
          {{ $t("flows.sequences.config_panel.background_title") }}
        </header>

        <!-- Asset picker -->
        <div class="flex items-center gap-2">
          <AssetPicker
            kind="image"
            :assets="data?.image_assets || []"
            :search-placeholder="$t('flows.sequences.config_panel.search_image')"
            @select="pickBackgroundImage"
          >
            <template #trigger>
              <Button
                variant="outline"
                class="flex-1 justify-between text-sm h-auto py-2"
                :disabled="!canEdit"
              >
                <span class="truncate">
                  {{ backgroundAsset?.filename || $t("flows.sequences.config_panel.pick_image") }}
                </span>
                <ImageIcon class="size-3.5 shrink-0 opacity-60" />
              </Button>
            </template>
          </AssetPicker>
          <button
            v-if="backgroundAssetId && canEdit"
            type="button"
            class="toolbar-btn"
            :title="$t('flows.sequences.config_panel.clear_image')"
            @click="clearBackgroundImage"
          >
            <X class="size-3.5" />
          </button>
        </div>

        <!-- Preview with applied position + fit -->
        <div
          v-if="backgroundAsset?.url"
          class="aspect-video rounded border border-border bg-muted/40 overflow-hidden"
          :style="{
            backgroundImage: `url(${backgroundAsset.url})`,
            backgroundPosition: backgroundPosition.replace('-', ' '),
            backgroundSize: backgroundFit === 'fill' ? '100% 100%' : backgroundFit,
            backgroundRepeat: 'no-repeat',
          }"
        />

        <!-- Position 3x3 grid -->
        <div v-if="backgroundAssetId" class="flex flex-col gap-1.5">
          <label class="text-xs text-muted-foreground">
            {{ $t("flows.sequences.config_panel.position_label") }}
          </label>
          <div class="grid grid-cols-3 gap-1 w-24">
            <button
              v-for="pos in BACKGROUND_POSITIONS"
              :key="pos"
              type="button"
              class="aspect-square rounded border transition-colors"
              :class="{
                'border-primary bg-primary/20': backgroundPosition === pos,
                'border-border hover:bg-muted': backgroundPosition !== pos,
              }"
              :title="pos"
              :disabled="!canEdit"
              @click="setBackgroundPosition(pos)"
            />
          </div>
        </div>

        <!-- Fit selector -->
        <div v-if="backgroundAssetId" class="flex flex-col gap-1.5">
          <label class="text-xs text-muted-foreground">
            {{ $t("flows.sequences.config_panel.fit_label") }}
          </label>
          <div class="flex gap-1">
            <button
              v-for="fit in BACKGROUND_FITS"
              :key="fit"
              type="button"
              class="flex-1 text-xs py-1.5 rounded border transition-colors"
              :class="{
                'border-primary bg-primary/20 text-foreground': backgroundFit === fit,
                'border-border text-muted-foreground hover:bg-muted': backgroundFit !== fit,
              }"
              :disabled="!canEdit"
              @click="setBackgroundFit(fit)"
            >
              {{ $t(`flows.sequences.config_panel.fit_${fit}`) }}
            </button>
          </div>
        </div>
      </section>

      <!-- Audio tracks section -->
      <section class="flex flex-col gap-3">
        <header class="flex items-center gap-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">
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
