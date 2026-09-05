<script setup lang="ts">
import { nextTick, onUnmounted, watch } from "vue";
import type { SequenceAudioTrack } from "@modules/flows/sequence/types";

export type PlayerAudioTrack = SequenceAudioTrack;

const { tracks = [] } = defineProps<{
  tracks?: SequenceAudioTrack[];
}>();

const emit = defineEmits<{
  "blocked-change": [blocked: boolean];
}>();

const audioElements = new Map<string, HTMLAudioElement>();
const sourceUrls = new Map<string, string>();
const blockedKeys = new Set<string>();

function trackIdentity(track: SequenceAudioTrack): string {
  const continuityKey = track.continuityKey ?? track.continuity_key;

  if (continuityKey !== null && continuityKey !== undefined && continuityKey !== "") {
    return String(continuityKey);
  }

  return [track.sequence_id ?? track.sequenceId ?? "sequence", track.kind, track.id].join(":");
}

function normalizedVolume(volume: number | null | undefined): number {
  if (typeof volume !== "number" || Number.isNaN(volume)) return 1;
  return Math.min(1, Math.max(0, volume));
}

function updateBlocked(key: string, blocked: boolean): void {
  const wasBlocked = blockedKeys.size > 0;

  if (blocked) {
    blockedKeys.add(key);
  } else {
    blockedKeys.delete(key);
  }

  const isBlocked = blockedKeys.size > 0;
  if (isBlocked !== wasBlocked) emit("blocked-change", isBlocked);
}

function stopElement(key: string, el: HTMLAudioElement): void {
  el.pause();
  updateBlocked(key, false);
}

function removeElement(key: string): void {
  const el = audioElements.get(key);
  if (el) stopElement(key, el);

  audioElements.delete(key);
  sourceUrls.delete(key);
}

function playElement(key: string, el: HTMLAudioElement): void {
  try {
    const playResult = el.play();

    if (playResult && typeof playResult.then === "function") {
      void playResult
        .then(() => {
          if (audioElements.get(key) === el) updateBlocked(key, false);
        })
        .catch(() => {
          if (audioElements.get(key) === el) updateBlocked(key, true);
        });
    } else {
      updateBlocked(key, false);
    }
  } catch {
    if (audioElements.get(key) === el) updateBlocked(key, true);
  }
}

function activeTrackKeys(): Set<string> {
  return new Set(tracks.map(trackIdentity));
}

function setAudioElement(key: string, el: unknown): void {
  if (el instanceof HTMLAudioElement) {
    const previous = audioElements.get(key);
    if (previous && previous !== el) stopElement(key, previous);

    audioElements.set(key, el);
    void nextTick(syncAudio);
    return;
  }

  // Vue may refresh a function ref while retaining the keyed element. Only
  // stop it when its serialized continuity identity has actually disappeared.
  if (!activeTrackKeys().has(key)) removeElement(key);
}

function syncAudio(): void {
  const activeTracks = new Map(tracks.map((track) => [trackIdentity(track), track]));

  for (const key of audioElements.keys()) {
    if (!activeTracks.has(key)) removeElement(key);
  }

  for (const [key, track] of activeTracks) {
    const el = audioElements.get(key);
    if (!el) continue;

    const previousUrl = sourceUrls.get(key);
    if (previousUrl && previousUrl !== track.url) {
      stopElement(key, el);
      el.currentTime = 0;
      el.load();
    }

    sourceUrls.set(key, track.url);
    el.volume = normalizedVolume(track.volume);
    playElement(key, el);
  }
}

function retryBlockedAudio(): void {
  for (const key of blockedKeys) {
    const el = audioElements.get(key);

    if (el) {
      playElement(key, el);
    } else {
      updateBlocked(key, false);
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

onUnmounted(() => {
  for (const [key, el] of audioElements) stopElement(key, el);

  audioElements.clear();
  sourceUrls.clear();
  blockedKeys.clear();
});

defineExpose({ retryBlockedAudio });
</script>

<template>
  <div class="player-audio-tracks" aria-hidden="true">
    <audio
      v-for="track in tracks"
      :key="trackIdentity(track)"
      :ref="(el) => setAudioElement(trackIdentity(track), el)"
      :src="track.url"
      :data-continuity-key="trackIdentity(track)"
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
