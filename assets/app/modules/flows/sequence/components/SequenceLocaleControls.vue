<script setup lang="ts">
import { computed } from "vue";
import LanguagePicker from "@components/language/LanguagePicker.vue";
import { Badge } from "@components/ui/badge";
import type {
  SequenceDialogueVoice,
  SequenceLanguageOption,
  SequenceLocalizationState,
} from "@modules/flows/sequence/types";

type TranslationDisplayStatus = "source" | "current" | "missing" | "fallback" | "stale";
type VoiceDisplayStatus = "none" | "needed" | "recorded" | "approved" | "stale" | "unavailable";

const {
  id,
  languageOptions = [],
  contentLocale = null,
  localizationStatus = null,
  voice = null,
  tone = "default",
} = defineProps<{
  id: string;
  languageOptions?: SequenceLanguageOption[];
  contentLocale?: string | null;
  localizationStatus?: SequenceLocalizationState | null;
  voice?: SequenceDialogueVoice | null;
  tone?: "default" | "dark";
}>();

const emit = defineEmits<{
  "update:contentLocale": [locale: string];
}>();

const translationDisplayStatus = computed<TranslationDisplayStatus | null>(() => {
  if (!localizationStatus) return null;

  if (localizationStatus.stale) return "stale";
  if (localizationStatus.isSource || localizationStatus.status === "source") return "source";
  if (localizationStatus.fallback) return "fallback";
  if (
    !localizationStatus.status ||
    localizationStatus.status === "missing" ||
    localizationStatus.status === "empty"
  ) {
    return "missing";
  }

  return "current";
});

function voiceUnavailable(candidate: SequenceDialogueVoice): boolean {
  if (candidate.available === false) return true;
  return !candidate.url;
}

const voiceDisplayStatus = computed<VoiceDisplayStatus | null>(() => {
  if (!voice) return null;
  if (voice.stale) return "stale";

  const status = voice.status?.toLowerCase();
  if (status === "none") return "none";
  if (status === "needed") return "needed";
  if (voiceUnavailable(voice)) return "unavailable";
  if (status === "approved") return "approved";

  return "recorded";
});

const pickerAppearance = computed(() => ({
  compact: true,
  searchable: languageOptions.length > 5,
  align: "end" as const,
  triggerSize: "xs" as const,
  triggerClass:
    tone === "dark"
      ? "h-7 border-white/15 bg-black/30 text-white hover:bg-white/10 hover:text-white"
      : "h-7 bg-background/80",
}));

function statusClass(status: TranslationDisplayStatus | VoiceDisplayStatus): string {
  const toneClass =
    tone === "dark" ? "border-white/15 bg-black/30 text-slate-200" : "bg-background/80";

  if (status === "current" || status === "recorded" || status === "approved") {
    return `${toneClass} border-emerald-500/30 text-emerald-700 dark:text-emerald-300`;
  }

  if (status === "source") return `${toneClass} text-muted-foreground`;
  return `${toneClass} border-amber-500/35 text-amber-700 dark:text-amber-300`;
}
</script>

<template>
  <div
    class="flex min-w-0 flex-wrap items-center justify-end gap-1.5"
    data-sequence-locale-controls
  >
    <LanguagePicker
      v-if="languageOptions.length > 0"
      :id="`${id}-language`"
      :model-value="contentLocale"
      :options="languageOptions"
      :label="$t('flows.presentation.content_language')"
      :text="{
        placeholder: $t('flows.presentation.select_language'),
        searchPlaceholder: $t('flows.presentation.search_languages'),
        emptyLabel: $t('flows.presentation.no_languages'),
      }"
      :appearance="pickerAppearance"
      data-sequence-language-picker
      @update:model-value="emit('update:contentLocale', $event)"
    />

    <Badge
      v-if="translationDisplayStatus"
      variant="outline"
      class="h-6 whitespace-nowrap px-2 text-[10px] font-medium"
      :class="statusClass(translationDisplayStatus)"
      :aria-label="
        $t('flows.presentation.translation_status', {
          status: $t(`flows.presentation.translation.${translationDisplayStatus}`),
        })
      "
      :data-translation-status="translationDisplayStatus"
    >
      {{
        $t("flows.presentation.translation_status", {
          status: $t(`flows.presentation.translation.${translationDisplayStatus}`),
        })
      }}
    </Badge>

    <Badge
      v-if="voiceDisplayStatus"
      variant="outline"
      class="h-6 whitespace-nowrap px-2 text-[10px] font-medium"
      :class="statusClass(voiceDisplayStatus)"
      :aria-label="
        $t('flows.presentation.voice_status', {
          status: $t(`flows.presentation.voice.${voiceDisplayStatus}`),
        })
      "
      :data-voice-status="voiceDisplayStatus"
    >
      {{
        $t("flows.presentation.voice_status", {
          status: $t(`flows.presentation.voice.${voiceDisplayStatus}`),
        })
      }}
    </Badge>

    <slot />
  </div>
</template>
