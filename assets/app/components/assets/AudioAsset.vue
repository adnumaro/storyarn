<script setup lang="ts">
import type { Component } from "vue";
import { computed, onUnmounted, ref, watch } from "vue";
import { Loader2, Music, Pause, Play, Upload, Volume2, VolumeX, X } from "lucide-vue-next";

import AssetPicker from "@components/assets/AssetPicker.vue";
import { Button } from "@components/ui/button/index.ts";
import { Slider } from "@components/ui/slider/index.ts";
import { useUpload } from "@composables/useUpload";

interface AssetItem {
  id: number | string;
  filename: string;
  url?: string | null;
}

const {
  label,
  icon = Music,
  assetId = null,
  volume = null,
  audioAssets = [],
  canEdit = false,
  pickPlaceholder,
  searchPlaceholder,
} = defineProps<{
  label: string;
  icon?: Component;
  assetId?: number | string | null;
  volume?: number | null;
  audioAssets?: AssetItem[];
  canEdit?: boolean;
  pickPlaceholder?: string;
  searchPlaceholder?: string;
  clearTitle?: string;
}>();

const emit = defineEmits<{
  select: [asset: AssetItem];
  clear: [];
  "volume-change": [percent: number];
}>();

const hasTrack = computed(() => assetId != null);

const currentAsset = computed<AssetItem | null>(() => {
  if (!hasTrack.value) return null;
  return audioAssets.find((a) => String(a.id) === String(assetId)) ?? null;
});

// Local volume mirror — updates optimistically on slider drag so the preview
// audio reacts in real-time without waiting for the server round-trip via
// `volume-change` → server → prop. Re-syncs when the prop changes.
const volumeValue = ref(volume == null ? 100 : Math.round(Number(volume)));

watch(
  () => volume,
  (v) => {
    volumeValue.value = v == null ? 100 : Math.round(Number(v));
  },
);

function onVolumeChange(val: number[] | undefined) {
  if (!val || val.length === 0) return;
  const percent = val[0];
  if (!Number.isFinite(percent)) return;
  volumeValue.value = percent;
  if (audioEl.value) audioEl.value.volume = percent / 100;
  emit("volume-change", percent);
}

// Preview playback — single Audio element per component instance.
const isPlaying = ref(false);
const audioEl = ref<HTMLAudioElement | null>(null);

function teardownAudio() {
  if (audioEl.value) {
    audioEl.value.pause();
    audioEl.value = null;
  }
  isPlaying.value = false;
}

watch(
  () => currentAsset.value?.url,
  (newUrl) => {
    teardownAudio();
    if (newUrl) {
      const el = new Audio(newUrl);
      el.volume = volumeValue.value / 100;
      el.addEventListener("ended", () => {
        isPlaying.value = false;
      });
      audioEl.value = el;
    }
  },
  { immediate: true },
);

function togglePlay() {
  if (!audioEl.value) return;

  if (isPlaying.value) {
    audioEl.value.pause();
    isPlaying.value = false;
    return;
  }

  audioEl.value.play();
  isPlaying.value = true;
}

// Upload — multipart via useUpload composable. After success the new asset
// is emitted via `select` so the parent's existing track-attach flow runs.
const { uploadFile } = useUpload();
const isUploading = ref(false);

function triggerUpload() {
  const input = document.createElement("input");
  input.type = "file";
  input.accept = "audio/*";
  input.onchange = async (e) => {
    const file = (e.target as HTMLInputElement).files?.[0];
    if (!file) return;
    isUploading.value = true;
    try {
      const result = await uploadFile(file, "audio");
      if (result) {
        emit("select", { id: result.id, url: result.url, filename: file.name });
      }
    } finally {
      isUploading.value = false;
    }
  };
  input.click();
}

onUnmounted(teardownAudio);
</script>

<template>
  <div class="flex flex-col gap-1.5 border border-border rounded p-2">
    <div class="flex items-center gap-2">
      <component :is="icon" class="size-3.5 opacity-70 shrink-0" />
      <span class="text-xs font-medium flex-1">{{ label }}</span>
      <div class="flex items-center">
        <Button
          v-if="audioEl"
          variant="ghost"
          size="icon-xs"
          :title="isPlaying ? $t('common.assets.audio.pause') : $t('common.assets.audio.play')"
          @click="togglePlay"
        >
          <Pause v-if="isPlaying" class="size-3" />
          <Play v-else class="size-3" />
        </Button>
        <Button
          v-if="canEdit"
          variant="ghost"
          size="icon-xs"
          :title="$t('common.assets.audio.upload')"
          :disabled="isUploading"
          @click="triggerUpload"
        >
          <Loader2 v-if="isUploading" class="size-3 animate-spin" />
          <Upload v-else class="size-3" />
        </Button>
        <slot name="header-actions" />
        <Button
          v-if="hasTrack && canEdit"
          variant="ghost"
          size="icon-xs"
          :title="clearTitle || $t('common.assets.audio.clear')"
          @click="emit('clear')"
        >
          <X class="size-3" />
        </Button>
      </div>
    </div>

    <AssetPicker
      kind="audio"
      :assets="audioAssets"
      :selected-id="assetId"
      :search-placeholder="searchPlaceholder || $t('common.assets.audio.search')"
      @select="(asset) => emit('select', asset)"
    >
      <template #trigger>
        <Button
          variant="outline"
          class="justify-between text-xs h-auto py-1.5"
          :disabled="!canEdit"
        >
          <span class="truncate">
            {{ currentAsset?.filename || pickPlaceholder || $t("common.assets.audio.pick") }}
          </span>
          <VolumeX v-if="!hasTrack" class="size-3.5 shrink-0 opacity-50" />
          <Volume2 v-else class="size-3.5 shrink-0 text-blue-500" />
        </Button>
      </template>
    </AssetPicker>

    <div v-if="hasTrack" class="flex items-center gap-2">
      <Volume2 class="size-3 shrink-0 opacity-50" />
      <Slider
        :model-value="[volumeValue]"
        :min="0"
        :max="100"
        :step="1"
        :disabled="!canEdit"
        class="flex-1"
        @update:model-value="onVolumeChange"
      />
      <span class="text-xs tabular-nums w-8 text-right text-muted-foreground">
        {{ volumeValue }}
      </span>
    </div>
  </div>
</template>
