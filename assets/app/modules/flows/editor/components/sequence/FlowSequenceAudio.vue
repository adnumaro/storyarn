<script setup lang="ts">
import { computed, ref } from "vue";
import { RotateCcw, Play, Pause, RefreshCw } from "@lucide/vue";
import { Button } from "@components/ui/button";
import { useLive } from "@shared/composables/useLive";
import DialogueVoice from "@modules/flows/player/components/DialogueVoice.vue";
import type {
  SequenceConfigPanelData,
  SequenceDialogueVoice,
  SequenceAudioTrackRecord,
} from "@modules/flows/sequence/types";
import FlowSequenceAudioSlot from "./FlowSequenceAudioSlot.vue";

const {
  ownerId,
  data,
  voice = null,
  canEdit = false,
} = defineProps<{
  ownerId: string | number;
  data: SequenceConfigPanelData;
  voice?: SequenceDialogueVoice | null;
  canEdit?: boolean;
}>();
const live = useLive();
const slots = computed(() => {
  const tracks = data.tracks ?? [];
  return ["music", "ambience", "sfx"].flatMap<{
    kind: string;
    track: SequenceAudioTrackRecord | null;
  }>((kind) => {
    const matching = tracks.filter((t) => t.kind === kind);
    return matching.length ? matching.map((track) => ({ kind, track })) : [{ kind, track: null }];
  });
});
const voicePlayer = ref<InstanceType<typeof DialogueVoice> | null>(null);
const previews = ref<InstanceType<typeof FlowSequenceAudioSlot>[]>([]);
const voicePlaying = ref(false);
const voiceBlocked = ref(false);
function key(track: SequenceAudioTrackRecord) {
  return track.trackKey ?? track.track_key ?? track.id;
}
function send(event: string, params: Record<string, unknown>) {
  if (canEdit) live.pushEvent(event, { id: ownerId, ...params });
}
function update(
  kind: string,
  track: SequenceAudioTrackRecord | null,
  attrs: { asset_id?: string | number; volume?: number },
) {
  if (track && String(track.sequenceId ?? track.sequence_id) !== String(ownerId)) {
    send("override_sequence_track", { track_key: key(track), ...attrs });
  } else send("upsert_sequence_track", { kind, ...attrs });
}
function stopVoicePreview() {
  voicePlayer.value?.stop();
}
function pausePreviews() {
  voicePlayer.value?.pause();
  for (const p of previews.value) p.pause();
}
function stopPreviews() {
  stopVoicePreview();
  for (const p of previews.value) p.stop();
}
defineExpose({ stopVoicePreview, pausePreviews, stopPreviews });
</script>

<template>
  <section class="space-y-3" data-sequence-audio>
    <p class="text-xs text-muted-foreground">{{ $t("flows.sequence_audio.hint") }}</p>
    <FlowSequenceAudioSlot
      ref="previews"
      v-for="slot in slots"
      :key="`${ownerId}:${slot.track ? key(slot.track) : slot.kind}`"
      :kind="slot.kind"
      :track="slot.track"
      :assets="data.audio_assets"
      :can-edit="canEdit"
      :inherited="
        !!slot.track && String(slot.track.sequenceId ?? slot.track.sequence_id) !== String(ownerId)
      "
      @select="update(slot.kind, slot.track, { asset_id: $event })"
      @volume="update(slot.kind, slot.track, { volume: $event })"
      @remove="slot.track && send('remove_sequence_track', { track_key: key(slot.track) })"
      @revert="
        slot.track &&
        send('revert_sequence_track', {
          track_key: key(slot.track),
          fields: slot.track.overridden_fields,
        })
      "
    />
    <details v-if="data.removed_tracks?.length" class="text-xs">
      <summary class="cursor-pointer text-muted-foreground">
        {{ $t("flows.sequence_audio.removed") }}
      </summary>
      <div
        v-for="track in data.removed_tracks"
        :key="String(key(track))"
        class="mt-2 flex items-center gap-2"
      >
        <span class="min-w-0 flex-1 truncate">{{
          track.filename || $t(`flows.sequences.tracks.${track.kind}`)
        }}</span>
        <Button
          variant="ghost"
          size="icon-xs"
          :disabled="!canEdit"
          :aria-label="$t('flows.sequences.config_panel.restore')"
          @click="send('restore_sequence_track', { track_key: key(track) })"
          ><RotateCcw class="size-3.5"
        /></Button>
      </div>
    </details>
    <div class="space-y-2 border-t border-border pt-3">
      <p class="text-xs font-medium">{{ $t("flows.sequence_playback.voice") }}</p>
      <p class="text-xs text-muted-foreground">{{ $t("flows.sequence_audio.voice_hint") }}</p>
      <DialogueVoice
        ref="voicePlayer"
        :voice="voice"
        :autoplay="false"
        @playing-change="voicePlaying = $event"
        @blocked-change="voiceBlocked = $event"
      />
      <Button
        v-if="voice?.available && voice.url"
        variant="outline"
        size="xs"
        @click="voicePlaying ? voicePlayer?.pause() : voicePlayer?.play()"
        ><RefreshCw v-if="voiceBlocked" class="size-3" /><Pause
          v-else-if="voicePlaying"
          class="size-3"
        /><Play v-else class="size-3" />{{
          $t(voicePlaying ? "common.assets.audio.pause" : "common.assets.audio.play")
        }}</Button
      >
      <p v-else class="text-xs text-muted-foreground">{{ $t("flows.sequence_audio.no_voice") }}</p>
    </div>
  </section>
</template>
