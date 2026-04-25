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

import AudioAsset from "@components/assets/AudioAsset.vue";
import ImageAsset from "@components/assets/ImageAsset.vue";
import ImagePosition from "@components/assets/ImagePosition.vue";
import Sidebar from "@components/layout/Sidebar.vue";
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

const sequenceId = computed(() => data?.sequence_id ?? null);

const backgroundAssetId = computed(() => data?.config?.background_asset_id ?? null);
const backgroundPosition = computed(() => data?.config?.background_position ?? "center");
const backgroundFit = computed<"cover" | "contain" | "fill">(
  () => (data?.config?.background_fit as "cover" | "contain" | "fill" | undefined) ?? "cover",
);

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

        <ImageAsset
          :asset-id="backgroundAssetId"
          :image-assets="data?.image_assets || []"
          :can-edit="canEdit"
          :pick-placeholder="$t('flows.sequences.config_panel.pick_image')"
          :search-placeholder="$t('flows.sequences.config_panel.search_image')"
          :clear-title="$t('flows.sequences.config_panel.clear_image')"
          :preview-position="backgroundPosition"
          :preview-fit="backgroundFit"
          @select="pickBackgroundImage"
          @clear="clearBackgroundImage"
        />

        <ImagePosition
          v-if="backgroundAssetId"
          :position="backgroundPosition"
          :fit="backgroundFit"
          :can-edit="canEdit"
          @position-change="setBackgroundPosition"
          @fit-change="setBackgroundFit"
        />
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
