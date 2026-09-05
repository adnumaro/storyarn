<script setup lang="ts">
import { computed, onUnmounted, ref, watch } from "vue";
import { Music, Pause, Play, RefreshCw, Volume2 } from "@lucide/vue";
import { useI18n } from "vue-i18n";
import { Button } from "@components/ui/button";
import type { SequenceAudioTrack } from "@modules/flows/sequence/types";

const { track } = defineProps<{ track: SequenceAudioTrack }>();

const { t } = useI18n();
const audioElement = ref<HTMLAudioElement | null>(null);
const playing = ref(false);
const blocked = ref(false);
let playAttempt = 0;

const trackLabel = computed(() => t(`flows.sequences.tracks.${track.kind}`));
const state = computed(() => {
  if (blocked.value) return "blocked";
  if (playing.value) return "playing";
  return "paused";
});
const actionLabel = computed(() => {
  let action = "play";

  if (blocked.value) {
    action = "retry";
  } else if (playing.value) {
    action = "pause";
  }

  return t(`flows.sequence_stage.${action}_audio_preview`, { track: trackLabel.value });
});

function normalizedVolume(volume: number | null | undefined): number {
  if (typeof volume !== "number" || Number.isNaN(volume)) return 1;
  return Math.min(1, Math.max(0, volume));
}

function playTrack(): void {
  const element = audioElement.value;
  if (!element) return;

  element.volume = normalizedVolume(track.volume);
  const attempt = ++playAttempt;

  try {
    const result = element.play();

    if (result && typeof result.then === "function") {
      void result
        .then(() => {
          if (attempt === playAttempt && audioElement.value === element) {
            blocked.value = false;
            playing.value = true;
          }
        })
        .catch(() => {
          if (attempt === playAttempt && audioElement.value === element) {
            blocked.value = true;
            playing.value = false;
          }
        });
    } else {
      blocked.value = false;
      playing.value = true;
    }
  } catch {
    if (attempt === playAttempt && audioElement.value === element) {
      blocked.value = true;
      playing.value = false;
    }
  }
}

function pauseTrack(): void {
  playAttempt += 1;
  audioElement.value?.pause();
  playing.value = false;
}

function stopTrack(): void {
  pauseTrack();

  if (audioElement.value) audioElement.value.currentTime = 0;
  blocked.value = false;
}

function togglePlayback(): void {
  if (playing.value) {
    pauseTrack();
  } else {
    playTrack();
  }
}

watch([() => track.continuityKey ?? track.continuity_key ?? track.id, () => track.url], stopTrack);

watch(
  () => track.volume,
  (volume) => {
    if (audioElement.value) audioElement.value.volume = normalizedVolume(volume);
  },
);

onUnmounted(stopTrack);
</script>

<template>
  <span class="inline-flex">
    <Button
      type="button"
      variant="outline"
      size="xs"
      class="max-w-32 gap-1.5"
      :title="actionLabel"
      :aria-label="actionLabel"
      :data-track-key="track.trackKey ?? track.track_key ?? track.id"
      :data-audio-preview-state="state"
      data-sequence-audio-preview
      @click="togglePlayback"
    >
      <RefreshCw v-if="blocked" class="size-3" aria-hidden="true" />
      <Pause v-else-if="playing" class="size-3" aria-hidden="true" />
      <Music v-else-if="track.kind === 'music'" class="size-3" aria-hidden="true" />
      <Volume2 v-else class="size-3" aria-hidden="true" />
      <span class="truncate">{{ trackLabel }}</span>
      <Play v-if="!playing && !blocked" class="size-2.5 opacity-60" aria-hidden="true" />
    </Button>
    <audio
      ref="audioElement"
      class="absolute size-px overflow-hidden opacity-0 pointer-events-none"
      aria-hidden="true"
      :src="track.url"
      :data-preview-track-key="track.trackKey ?? track.track_key ?? track.id"
      loop
      preload="metadata"
      @play="playing = true"
      @pause="playing = false"
      @ended="playing = false"
    />
  </span>
</template>
