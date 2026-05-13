<script setup lang="ts">
import { nextTick, onMounted, onUnmounted, watch } from "vue";

export interface PlayerAudioTrack {
  id: string | number;
  sequence_id?: string | number;
  sequenceId?: string | number;
  kind: "music" | "ambience" | "sfx" | string;
  position?: number | null;
  url: string;
  volume?: number | null;
  content_type?: string | null;
  contentType?: string | null;
  filename?: string | null;
  depth?: number | null;
}

const { tracks = [] } = defineProps<{
  tracks?: PlayerAudioTrack[];
}>();

const audioElements = new Map<string, HTMLAudioElement>();
const blockedKeys = new Set<string>();

function trackKey(track: PlayerAudioTrack): string {
  return [track.sequence_id ?? track.sequenceId ?? "sequence", track.kind, track.id].join(":");
}

function normalizedVolume(volume: number | null | undefined): number {
  if (typeof volume !== "number" || Number.isNaN(volume)) return 1;
  return Math.min(1, Math.max(0, volume));
}

function setAudioElement(key: string, el: unknown): void {
  if (el instanceof HTMLAudioElement) {
    audioElements.set(key, el);
  } else {
    const existing = audioElements.get(key);
    existing?.pause();
    audioElements.delete(key);
    blockedKeys.delete(key);
  }
}

function syncAudio(): void {
  const activeKeys = new Set(tracks.map(trackKey));

  for (const [key, el] of audioElements) {
    if (!activeKeys.has(key)) {
      el.pause();
      audioElements.delete(key);
      blockedKeys.delete(key);
    }
  }

  for (const track of tracks) {
    const key = trackKey(track);
    const el = audioElements.get(key);
    if (!el) continue;

    el.volume = normalizedVolume(track.volume);

    try {
      const playResult = el.play();
      if (playResult && typeof playResult.catch === "function") {
        void playResult.catch(() => blockedKeys.add(key));
      }
    } catch {
      blockedKeys.add(key);
    }
  }
}

function retryBlockedAudio(): void {
  for (const key of blockedKeys) {
    const el = audioElements.get(key);
    if (!el) {
      blockedKeys.delete(key);
      continue;
    }

    try {
      const playResult = el.play();
      if (playResult && typeof playResult.then === "function") {
        void playResult.then(() => blockedKeys.delete(key)).catch(() => undefined);
      }
    } catch {
      // Keep the key blocked; another user gesture may unlock playback.
    }
  }
}

watch(
  () => tracks,
  () => {
    void nextTick(syncAudio);
  },
  { deep: true, immediate: true },
);

onMounted(() => {
  document.addEventListener("pointerdown", retryBlockedAudio);
  document.addEventListener("keydown", retryBlockedAudio);
});

onUnmounted(() => {
  document.removeEventListener("pointerdown", retryBlockedAudio);
  document.removeEventListener("keydown", retryBlockedAudio);

  for (const el of audioElements.values()) {
    el.pause();
  }
  audioElements.clear();
  blockedKeys.clear();
});
</script>

<template>
  <div class="player-audio-tracks" aria-hidden="true">
    <audio
      v-for="track in tracks"
      :key="trackKey(track)"
      :ref="(el) => setAudioElement(trackKey(track), el)"
      :src="track.url"
      :data-sequence-id="track.sequence_id ?? track.sequenceId"
      :data-kind="track.kind"
      :data-depth="track.depth ?? 0"
      :data-position="track.position ?? 0"
      :data-filename="track.filename || undefined"
      :data-content-type="track.content_type ?? track.contentType ?? undefined"
      loop
      autoplay
      preload="auto"
    />
  </div>
</template>
