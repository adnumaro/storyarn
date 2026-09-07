<script setup lang="ts">
import { computed, onUnmounted, ref } from "vue";
import { Loader2, RotateCcw, Upload, X } from "@lucide/vue";
import { Button } from "@components/ui/button";
import AssetPicker from "@components/forms/assets/AssetPicker.vue";
import { useUpload } from "@shared/composables/useUpload";
import type { SequenceAssetEntry, SequenceAudioTrackRecord } from "@modules/flows/sequence/types";
import SequenceAudioTrackPreview from "./SequenceAudioTrackPreview.vue";

const {
  kind,
  track = null,
  assets = [],
  canEdit = false,
  inherited = false,
} = defineProps<{
  kind: string;
  track?: SequenceAudioTrackRecord | null;
  assets?: SequenceAssetEntry[];
  canEdit?: boolean;
  inherited?: boolean;
}>();
const emit = defineEmits<{
  select: [assetId: string | number];
  volume: [volume: number];
  remove: [];
  revert: [];
}>();
const assetId = computed(() => track?.assetId ?? track?.asset_id ?? null);
const filename = computed(
  () => track?.filename || assets.find((a) => String(a.id) === String(assetId.value))?.filename,
);
const playable = computed(() =>
  track?.url ? { ...track, id: track.id ?? track.trackKey ?? kind, url: track.url } : null,
);
const preview = ref<InstanceType<typeof SequenceAudioTrackPreview> | null>(null);
const input = ref<HTMLInputElement | null>(null);
const uploading = ref(false);
const failed = ref(false);
const { uploadFile } = useUpload();
let disposed = false;
async function upload(event: Event) {
  const element = event.target as HTMLInputElement;
  const file = element.files?.[0];
  element.value = "";
  if (!file || !canEdit || uploading.value) return;
  uploading.value = true;
  failed.value = false;
  try {
    const result = await uploadFile(file, "audio");
    if (result && !disposed && canEdit) emit("select", result.id);
  } catch {
    if (!disposed) failed.value = true;
  } finally {
    uploading.value = false;
  }
}
onUnmounted(() => {
  disposed = true;
});
function changeVolume(event: Event) {
  if (canEdit) emit("volume", Number((event.target as HTMLInputElement).value) / 100);
}
defineExpose({ stop: () => preview.value?.stop(), pause: () => preview.value?.pause() });
</script>

<template>
  <div
    class="min-w-0 space-y-2 rounded-md border border-border bg-background/40 p-2"
    :data-sequence-audio-slot="kind"
  >
    <div class="flex items-center gap-1.5">
      <SequenceAudioTrackPreview v-if="playable" ref="preview" :track="playable" />
      <span v-else class="flex-1 text-xs font-medium">{{
        $t(`flows.sequences.tracks.${kind}`)
      }}</span>
      <span class="flex-1" />
      <span v-if="inherited" class="text-[10px] text-muted-foreground">{{
        $t("flows.sequences.config_panel.inherited")
      }}</span>
      <Button
        v-if="track?.overridden_fields?.length && inherited"
        variant="ghost"
        size="icon-xs"
        :disabled="!canEdit"
        :aria-label="$t('flows.sequences.config_panel.revert_all')"
        @click="emit('revert')"
        ><RotateCcw class="size-3"
      /></Button>
      <Button
        v-if="track"
        variant="ghost"
        size="icon-xs"
        :disabled="!canEdit"
        :aria-label="$t('flows.sequences.config_panel.clear_track')"
        @click="emit('remove')"
        ><X class="size-3"
      /></Button>
    </div>
    <div class="flex min-w-0 gap-1">
      <AssetPicker
        kind="audio"
        :assets="assets"
        :selected-id="assetId"
        search-event="picker_search"
        :search-payload="{ resource: 'asset', kind: 'audio' }"
        @select="canEdit && emit('select', $event.id)"
      >
        <template #trigger
          ><Button
            variant="outline"
            size="sm"
            class="min-w-0 flex-1 justify-start text-xs"
            :disabled="!canEdit"
            ><span class="truncate">{{
              filename || $t("flows.sequences.config_panel.pick_audio")
            }}</span></Button
          ></template
        >
      </AssetPicker>
      <input
        ref="input"
        type="file"
        accept="audio/*"
        class="sr-only"
        :aria-label="$t('common.assets.audio.upload')"
        :disabled="!canEdit || uploading"
        @change="upload"
      />
      <Button
        variant="ghost"
        size="icon-sm"
        :disabled="!canEdit || uploading"
        :aria-label="$t('common.assets.audio.upload')"
        @click="input?.click()"
        ><Loader2 v-if="uploading" class="size-3.5 animate-spin" /><Upload v-else class="size-3.5"
      /></Button>
    </div>
    <label v-if="track" class="flex items-center gap-2 text-xs text-muted-foreground">
      <span>{{ $t("flows.sequence_audio.volume") }}</span>
      <input
        type="range"
        min="0"
        max="100"
        step="1"
        :value="Math.round((track.volume ?? 1) * 100)"
        :disabled="!canEdit"
        class="min-w-0 flex-1 accent-primary"
        @change="changeVolume"
      />
      <span class="w-8 text-right tabular-nums">{{ Math.round((track.volume ?? 1) * 100) }}%</span>
    </label>
    <p v-if="failed" class="text-xs text-destructive" role="alert">
      {{ $t("flows.sequence_audio.upload_failed") }}
    </p>
  </div>
</template>
