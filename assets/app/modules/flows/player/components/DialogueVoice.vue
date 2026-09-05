<script setup lang="ts">
import { computed, nextTick, onUnmounted, watch } from "vue";
import type { SequenceDialogueVoice } from "@modules/flows/sequence/types";

const { voice = null, autoplay = true } = defineProps<{
  voice?: SequenceDialogueVoice | null;
  autoplay?: boolean;
}>();

const emit = defineEmits<{
  "blocked-change": [blocked: boolean];
  "playing-change": [playing: boolean];
}>();

let audioElement: HTMLAudioElement | null = null;
let blocked = false;
let playing = false;
let playAttempt = 0;
let autoplaySchedule = 0;

type PlayableDialogueVoice = SequenceDialogueVoice & { url: string };

const playableVoice = computed<PlayableDialogueVoice | null>(() => {
  if (!voice || voice.available === false || typeof voice.url !== "string" || !voice.url.trim()) {
    return null;
  }

  return { ...voice, url: voice.url };
});

function voiceIdentity(voice: SequenceDialogueVoice): string {
  const continuityKey = voice.continuityKey ?? voice.continuity_key;
  return String(continuityKey ?? voice.id ?? voice.assetId ?? voice.asset_id ?? voice.url);
}

function voiceSignature(voice: SequenceDialogueVoice | null | undefined): string | null {
  return voice ? `${voiceIdentity(voice)}\u0000${voice.url}` : null;
}

function normalizedVolume(volume: number | null | undefined): number {
  if (typeof volume !== "number" || Number.isNaN(volume)) return 1;
  return Math.min(1, Math.max(0, volume));
}

function updateBlocked(nextBlocked: boolean): void {
  if (blocked === nextBlocked) return;

  blocked = nextBlocked;
  emit("blocked-change", blocked);
}

function updatePlaying(nextPlaying: boolean): void {
  if (playing === nextPlaying) return;

  playing = nextPlaying;
  emit("playing-change", playing);
}

function pause(): void {
  playAttempt += 1;
  audioElement?.pause();
  updatePlaying(false);
}

function stop(): void {
  autoplaySchedule += 1;
  pause();

  if (audioElement) {
    audioElement.currentTime = 0;
  }

  updateBlocked(false);
}

function playVoice(): void {
  const el = audioElement;
  const currentVoice = playableVoice.value;
  if (!el || !currentVoice) return;

  el.volume = normalizedVolume(currentVoice.volume);
  const attempt = ++playAttempt;

  try {
    const playResult = el.play();

    if (playResult && typeof playResult.then === "function") {
      void playResult
        .then(() => {
          if (attempt === playAttempt && audioElement === el) {
            updateBlocked(false);
            updatePlaying(true);
          }
        })
        .catch(() => {
          if (attempt === playAttempt && audioElement === el) {
            updateBlocked(true);
            updatePlaying(false);
          }
        });
    } else {
      updateBlocked(false);
      updatePlaying(true);
    }
  } catch {
    if (attempt === playAttempt && audioElement === el) {
      updateBlocked(true);
      updatePlaying(false);
    }
  }
}

function scheduleAutoplay(): void {
  if (!autoplay) return;

  const schedule = ++autoplaySchedule;
  void nextTick(() => {
    if (autoplay && schedule === autoplaySchedule) playVoice();
  });
}

function setAudioElement(el: unknown): void {
  if (el instanceof HTMLAudioElement) {
    if (audioElement && audioElement !== el) stop();
    audioElement = el;
    scheduleAutoplay();
    return;
  }

  if (audioElement) stop();
  audioElement = null;
}

function retryBlockedAudio(): void {
  if (blocked) playVoice();
}

watch(
  () => ({
    signature: voiceSignature(playableVoice.value),
    volume: playableVoice.value?.volume,
  }),
  (nextVoice, previousVoice) => {
    if (previousVoice?.signature && previousVoice.signature !== nextVoice.signature) stop();

    if (audioElement && nextVoice.signature === previousVoice?.signature) {
      audioElement.volume = normalizedVolume(nextVoice.volume);
    }

    scheduleAutoplay();
  },
  { flush: "sync" },
);

onUnmounted(stop);

defineExpose({ pause, play: playVoice, retryBlockedAudio, stop });
</script>

<template>
  <audio
    v-if="playableVoice"
    :key="voiceIdentity(playableVoice)"
    :ref="setAudioElement"
    class="player-dialogue-voice absolute size-px overflow-hidden opacity-0 pointer-events-none"
    aria-hidden="true"
    :src="playableVoice.url"
    :data-continuity-key="voiceIdentity(playableVoice)"
    :data-node-id="playableVoice.node_id ?? playableVoice.nodeId ?? undefined"
    :data-filename="playableVoice.filename || undefined"
    :data-content-type="playableVoice.content_type ?? playableVoice.contentType ?? undefined"
    :autoplay="autoplay || undefined"
    preload="auto"
    @ended="updatePlaying(false)"
    @pause="updatePlaying(false)"
    @play="updatePlaying(true)"
  />
</template>
