<script setup lang="ts">
import { Volume2 } from "@lucide/vue";
import { computed, nextTick, onMounted, onUnmounted, ref } from "vue";
import { Button } from "@components/ui/button";
import { useLive } from "@shared/composables/useLive";
import PlayerSlide from "@modules/flows/player/components/PlayerSlide.vue";
import PlayerChoices from "@modules/flows/player/components/PlayerChoices.vue";
import PlayerToolbar from "@modules/flows/player/components/PlayerToolbar.vue";
import PlayerOutcome from "@modules/flows/player/components/PlayerOutcome.vue";
import PlayerAudioTracks from "@modules/flows/player/components/PlayerAudioTracks.vue";
import DialogueVoice from "@modules/flows/player/components/DialogueVoice.vue";
import SequenceLocaleControls from "@modules/flows/sequence/components/SequenceLocaleControls.vue";
import SequenceVisualLayers from "@modules/flows/sequence/components/SequenceVisualLayers.vue";
import type { SlideData } from "@modules/flows/player/components/PlayerSlide.vue";
import type { ResponseData } from "@modules/flows/player/components/PlayerChoices.vue";
import type { OutcomeData } from "@modules/flows/player/components/PlayerOutcome.vue";
import type {
  SequenceAudioTrack,
  SequenceDialogueVoice,
  SequenceLanguageOption,
  SequenceLocalizationState,
  SequenceVisualLayer,
} from "@modules/flows/sequence/types";

/* oxlint-disable vue/max-props -- LiveVue sends the player presentation as explicit top-level props. */
const {
  slide,
  playerMode,
  canGoBack,
  showContinue,
  isFinished,
  visualLayers = [],
  audioTracks = [],
  voice = null,
  languageOptions = [],
  contentLocale = null,
  localizationStatus = null,
  editorUrl,
  responses = [],
} = defineProps<{
  slide: SlideData | OutcomeData;
  playerMode: "player" | "analysis";
  canGoBack: boolean;
  showContinue: boolean;
  isFinished: boolean;
  visualLayers?: SequenceVisualLayer[];
  audioTracks?: SequenceAudioTrack[];
  voice?: SequenceDialogueVoice | null;
  languageOptions?: SequenceLanguageOption[];
  contentLocale?: string | null;
  localizationStatus?: SequenceLocalizationState | null;
  editorUrl: string;
  responses: ResponseData[];
}>();
/* oxlint-enable vue/max-props */

const live = useLive();
const ambientAudio = ref<InstanceType<typeof PlayerAudioTracks> | null>(null);
const dialogueVoice = ref<InstanceType<typeof DialogueVoice> | null>(null);
const ambientAudioBlocked = ref(false);
const dialogueVoiceBlocked = ref(false);
let voiceNavigationGeneration = 0;
const audioBlocked = computed(() => ambientAudioBlocked.value || dialogueVoiceBlocked.value);
const showPresentationControls = computed(
  () =>
    languageOptions.length > 0 || localizationStatus != null || voice != null || audioBlocked.value,
);

function dialogueVoiceSignature(
  currentVoice: SequenceDialogueVoice | null | undefined,
): string | null {
  if (
    !currentVoice ||
    currentVoice.available === false ||
    typeof currentVoice.url !== "string" ||
    !currentVoice.url.trim()
  ) {
    return null;
  }

  const identity =
    currentVoice.continuityKey ??
    currentVoice.continuity_key ??
    currentVoice.id ??
    currentVoice.assetId ??
    currentVoice.asset_id ??
    currentVoice.url;

  return `${String(identity)}\u0000${currentVoice.url}`;
}

function stopDialogueVoice(): number {
  voiceNavigationGeneration += 1;
  dialogueVoice.value?.stop();
  return voiceNavigationGeneration;
}

function retryBlockedAudio() {
  ambientAudio.value?.retryBlockedAudio();
  dialogueVoice.value?.retryBlockedAudio();
}

function onContentLocaleChange(locale: string) {
  stopDialogueVoice();
  live.pushEvent("set_sequence_content_locale", { locale });
}

function onChooseResponse(responseId: string) {
  stopDialogueVoice();
  live.pushEvent("choose_response", { id: responseId });
}

function onContinue() {
  stopDialogueVoice();
  live.pushEvent("continue", {});
}

function onGoBack() {
  if (!canGoBack) return;

  stopDialogueVoice();
  live.pushEvent("go_back", {});
}

function onToggleMode() {
  live.pushEvent("toggle_mode", {});
}

function onRestart() {
  const previousVoiceSignature = dialogueVoiceSignature(voice);
  const navigationGeneration = stopDialogueVoice();

  live.pushEvent("restart", {}, () => {
    void nextTick(() => {
      if (
        navigationGeneration === voiceNavigationGeneration &&
        previousVoiceSignature != null &&
        dialogueVoiceSignature(voice) === previousVoiceSignature
      ) {
        dialogueVoice.value?.play();
      }
    });
  });
}

function onExitPlayer() {
  stopDialogueVoice();
  live.pushEvent("exit_player", {});
}

const visibleResponses = computed(() => {
  if (playerMode === "player") {
    return responses.filter((r) => r.valid);
  }
  return responses;
});

const INTERACTIVE_TARGET_SELECTOR = [
  "a[href]",
  "button",
  "input",
  "select",
  "summary",
  "textarea",
  '[contenteditable]:not([contenteditable="false"])',
  '[role="button"]',
  '[role="checkbox"]',
  '[role="combobox"]',
  '[role="link"]',
  '[role="listbox"]',
  '[role="menu"]',
  '[role="menuitem"]',
  '[role="option"]',
  '[role="radio"]',
  '[role="slider"]',
  '[role="spinbutton"]',
  '[role="switch"]',
  '[role="tab"]',
  '[role="textbox"]',
].join(",");

const KEY_ACTIONS: Record<string, () => void> = {
  " ": () => {
    if (showContinue && !isFinished) onContinue();
  },
  Enter: () => {
    if (showContinue && !isFinished) onContinue();
  },
  ArrowRight: () => {
    if (showContinue && !isFinished) onContinue();
  },
  ArrowLeft: () => {
    if (canGoBack) onGoBack();
  },
  Escape: () => onExitPlayer(),
  p: () => onToggleMode(),
  P: () => onToggleMode(),
  r: () => onRestart(),
  R: () => onRestart(),
};

function handleNumberKey(key: string) {
  if (key >= "1" && key <= "9") {
    const resp = visibleResponses.value[parseInt(key) - 1];
    if (resp) onChooseResponse(resp.id);
  }
}

function handleKeydown(e: KeyboardEvent) {
  if (e.target instanceof Element && e.target.closest(INTERACTIVE_TARGET_SELECTOR)) return;

  const action = KEY_ACTIONS[e.key];
  if (action) {
    e.preventDefault();
    action();
  } else {
    handleNumberKey(e.key);
  }
}

onMounted(() => {
  document.addEventListener("keydown", handleKeydown);
});

onUnmounted(() => {
  document.removeEventListener("keydown", handleKeydown);
});
</script>

<template>
  <div class="player-frame">
    <PlayerToolbar
      :can-go-back="canGoBack"
      :player-mode="playerMode"
      :editor-url="editorUrl"
      @go-back="onGoBack"
      @toggle-mode="onToggleMode"
      @restart="onRestart"
      @exit="stopDialogueVoice"
    />

    <div class="player-main">
      <div class="player-stage">
        <SequenceVisualLayers :layers="visualLayers" />
        <PlayerAudioTracks
          ref="ambientAudio"
          :tracks="audioTracks"
          @blocked-change="ambientAudioBlocked = $event"
        />
        <DialogueVoice
          ref="dialogueVoice"
          :voice="voice"
          @blocked-change="dialogueVoiceBlocked = $event"
        />

        <PlayerOutcome
          v-if="slide.type === 'outcome'"
          :slide="slide as OutcomeData"
          :editor-url="editorUrl"
          @restart="onRestart"
        />
      </div>

      <div
        v-if="showPresentationControls"
        class="absolute right-4 top-4 z-[2100] flex max-w-[calc(100%-2rem)] flex-wrap items-center justify-end gap-2 rounded-xl border border-white/10 bg-slate-950/75 p-2 shadow-xl backdrop-blur-md"
        data-player-presentation-controls
      >
        <SequenceLocaleControls
          id="flow-player"
          :language-options="languageOptions"
          :content-locale="contentLocale"
          :localization-status="localizationStatus"
          :voice="voice"
          tone="dark"
          @update:content-locale="onContentLocaleChange"
        />
        <Button
          v-if="audioBlocked"
          type="button"
          variant="secondary"
          size="sm"
          class="gap-2 shadow-lg"
          data-player-audio-retry
          @click="retryBlockedAudio"
        >
          <Volume2 class="size-4" aria-hidden="true" />
          {{ $t("flows.player.enable_audio") }}
        </Button>
      </div>

      <div v-if="slide.type !== 'outcome'" class="player-dialogue-overlay">
        <div class="player-dialogue-panel">
          <PlayerSlide :slide="slide as SlideData" />
          <PlayerChoices
            :responses="responses"
            :player-mode="playerMode"
            :show-continue="showContinue && !isFinished"
            @choose="onChooseResponse"
            @continue="onContinue"
          />
        </div>
      </div>
    </div>
  </div>
</template>
