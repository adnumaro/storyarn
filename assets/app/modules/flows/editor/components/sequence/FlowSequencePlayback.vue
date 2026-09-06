<script setup lang="ts">
import { computed, onUnmounted, ref } from "vue";
import { useElementSize } from "@vueuse/core";
import { ArrowLeft, ArrowRight, RotateCcw } from "@lucide/vue";
import { Button } from "@components/ui/button";
import { Avatar, AvatarFallback, AvatarImage } from "@components/ui/avatar";
import SequenceVisualLayers from "@modules/flows/sequence/components/SequenceVisualLayers.vue";
import PlayerAudioTracks from "@modules/flows/player/components/PlayerAudioTracks.vue";
import type { SequencePlaybackAction, SequencePlaybackState } from "./sequence-playback";

const { state, pending = false } = defineProps<{
  state: SequencePlaybackState;
  pending?: boolean;
}>();
const emit = defineEmits<{ action: [action: SequencePlaybackAction, responseId?: string] }>();
const container = ref<HTMLElement | null>(null);
const { width, height } = useElementSize(container);
const frameWidth = computed(() =>
  Math.max(1, Math.min(width.value - 32, ((height.value - 32) * 16) / 9)),
);
const responses = computed(() =>
  (state.slide.responses ?? []).filter((response) => response.valid),
);
const finished = computed(() => state.isFinished || state.slide.type === "outcome");
let voiceElement: HTMLAudioElement | null = null;
function setVoiceElement(element: unknown) {
  if (voiceElement && voiceElement !== element) voiceElement.pause();
  voiceElement = element instanceof HTMLAudioElement ? element : null;
}
onUnmounted(() => voiceElement?.pause());

function keydown(event: KeyboardEvent) {
  if (event.target !== event.currentTarget || pending) return;
  if ([" ", "Enter", "ArrowRight"].includes(event.key) && state.showContinue && !finished.value) {
    event.preventDefault();
    emit("action", "continue");
  }
}
</script>

<template>
  <section class="flex min-h-0 flex-1 flex-col bg-muted/30" data-sequence-playback>
    <div class="flex shrink-0 items-center gap-2 border-b border-border px-3 py-1.5">
      <Button
        variant="ghost"
        size="xs"
        :disabled="pending || !state.canGoBack"
        data-playback-back
        @click="emit('action', 'back')"
      >
        <ArrowLeft class="size-3.5" />{{ $t("flows.player.back") }}
      </Button>
      <span class="flex-1 text-center text-xs text-muted-foreground">{{
        $t("flows.sequence_playback.title")
      }}</span>
      <Button
        variant="ghost"
        size="xs"
        :disabled="pending"
        data-playback-restart
        @click="emit('action', 'restart')"
      >
        <RotateCcw class="size-3.5" />{{ $t("flows.player.restart") }}
      </Button>
    </div>
    <p v-if="state.error" class="shrink-0 px-4 py-2 text-sm text-destructive" role="alert">
      {{ $t("flows.sequence_playback.error") }}
    </p>
    <div
      ref="container"
      class="grid min-h-0 flex-1 place-items-center overflow-hidden"
      tabindex="0"
      :aria-label="$t('flows.sequence_playback.title')"
      @keydown="keydown"
    >
      <div
        class="relative isolate aspect-video overflow-hidden border border-border bg-background shadow-md"
        :style="{ width: width > 0 ? `${frameWidth}px` : '80%' }"
        data-playback-frame
      >
        <SequenceVisualLayers :layers="state.visualLayers" />
        <PlayerAudioTracks :tracks="finished ? [] : state.audioTracks" />
        <div
          v-if="finished"
          class="absolute inset-0 z-10 grid place-content-center gap-3 bg-background/75 px-4 text-center"
        >
          <h2 class="text-lg font-semibold">
            {{ state.slide.label || $t("flows.sequence_playback.finished") }}
          </h2>
          <Button :disabled="pending" data-playback-play-again @click="emit('action', 'restart')"
            ><RotateCcw class="size-4" />{{ $t("flows.player.play_again") }}</Button
          >
        </div>
        <div
          v-else-if="state.slide.type === 'dialogue'"
          class="absolute inset-x-0 bottom-0 z-10 max-h-[75%] overflow-y-auto border-t border-white/15 bg-slate-950/90 p-4 text-slate-100 backdrop-blur-sm"
          data-playback-dialogue
        >
          <div class="mx-auto flex max-w-3xl items-start gap-3">
            <Avatar class="size-9 shrink-0 border border-white/15">
              <AvatarImage
                v-if="state.slide.speaker_avatar_url"
                :src="state.slide.speaker_avatar_url"
              />
              <AvatarFallback
                class="text-xs text-white"
                :style="{ backgroundColor: state.slide.speaker_color || '#8b5cf6' }"
                >{{ state.slide.speaker_initials || "?" }}</AvatarFallback
              >
            </Avatar>
            <div class="min-w-0 flex-1 space-y-2">
              <p class="text-sm font-medium">
                {{ state.slide.speaker_name || $t("flows.preview.narrator") }}
              </p>
              <!-- eslint-disable-next-line vue/no-v-html -->
              <div
                class="prose prose-sm prose-invert max-w-none text-sm"
                v-html="state.slide.text"
              />
              <p
                v-if="state.slide.stage_directions"
                class="text-xs italic text-slate-300"
                data-playback-stage-directions
              >
                {{ state.slide.stage_directions }}
              </p>
              <audio
                v-if="state.voice"
                :key="state.voice.key"
                :ref="setVoiceElement"
                :src="state.voice.url"
                controls
                autoplay
                class="h-8 max-w-full"
                :aria-label="$t('flows.sequence_playback.voice')"
              />
              <div class="flex flex-col gap-1.5">
                <Button
                  v-for="response in responses"
                  :key="response.id"
                  variant="outline"
                  size="sm"
                  class="h-auto justify-start whitespace-normal border-white/20 bg-white/5 py-2 text-left text-white hover:bg-white/15 hover:text-white"
                  :disabled="pending"
                  :data-playback-response="response.id"
                  @click="emit('action', 'choose', response.id)"
                  >{{ response.text }}</Button
                >
                <Button
                  v-if="state.showContinue"
                  size="sm"
                  class="self-end"
                  :disabled="pending"
                  data-playback-continue
                  @click="emit('action', 'continue')"
                  >{{ $t("flows.player.continue") }}<ArrowRight class="size-4"
                /></Button>
              </div>
            </div>
          </div>
        </div>
        <div
          v-else
          class="absolute inset-0 grid place-items-center p-4 text-sm text-muted-foreground"
        >
          {{ $t("flows.player.no_content") }}
        </div>
      </div>
    </div>
  </section>
</template>
