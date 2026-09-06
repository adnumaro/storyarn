<script setup lang="ts">
import { ref, computed } from "vue";
import { Music, Pause, Play, RefreshCw, Volume2 } from "@lucide/vue";
import { Button } from "@components/ui/button";
import DialogueVoice from "@modules/flows/player/components/DialogueVoice.vue";
import type { SequenceAudioTrack } from "@modules/flows/sequence/types";

const { track } = defineProps<{ track: SequenceAudioTrack }>();
const player = ref<InstanceType<typeof DialogueVoice> | null>(null);
const playing = ref(false);
const blocked = ref(false);
const state = computed(() => {
  if (blocked.value) return "blocked";
  return playing.value ? "playing" : "paused";
});
const action = computed(() => {
  if (blocked.value) return "retry";
  return playing.value ? "pause" : "play";
});
function toggle() {
  if (playing.value) player.value?.pause();
  else player.value?.play();
}
defineExpose({ stop: () => player.value?.stop(), pause: () => player.value?.pause() });
</script>

<template>
  <span class="inline-flex">
    <Button
      variant="outline"
      size="xs"
      class="max-w-full gap-1.5"
      :aria-label="
        $t(`flows.sequence_stage.${action}_audio_preview`, {
          track: $t(`flows.sequences.tracks.${track.kind}`),
        })
      "
      :data-track-key="track.trackKey ?? track.track_key ?? track.id"
      :data-audio-preview-state="state"
      data-sequence-audio-preview
      @click="toggle"
    >
      <RefreshCw v-if="blocked" class="size-3" /><Pause v-else-if="playing" class="size-3" />
      <Music v-else-if="track.kind === 'music'" class="size-3" /><Volume2 v-else class="size-3" />
      <span class="truncate">{{ $t(`flows.sequences.tracks.${track.kind}`) }}</span>
      <Play v-if="!playing && !blocked" class="size-2.5 opacity-60" />
    </Button>
    <DialogueVoice
      ref="player"
      :voice="track"
      :autoplay="false"
      :loop="track.kind === 'music' || track.kind === 'ambience'"
      @playing-change="playing = $event"
      @blocked-change="blocked = $event"
    />
  </span>
</template>
