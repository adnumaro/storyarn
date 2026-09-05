<script setup lang="ts">
import { History, Sparkles } from "@lucide/vue";
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import { Label } from "@components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@components/ui/select";
import { Textarea } from "@components/ui/textarea";
import { formatShortDate } from "../../../domain/format";
import { STATUS_I18N, STATUS_KEYS, VO_I18N, VO_STATUS_KEYS } from "../../../domain/status";
import type { EditorHistory } from "./types";

/** Status, voice-over state, translator notes and who translated it when. */
const {
  canEdit = false,
  voEligible = false,
  finalUnavailable = false,
  history,
} = defineProps<{
  canEdit?: boolean;
  voEligible?: boolean;
  finalUnavailable?: boolean;
  history: EditorHistory;
}>();

const status = defineModel<string>("status", { required: true });
const voStatus = defineModel<string>("voStatus", { required: true });
const translatorNotes = defineModel<string>("translatorNotes", { required: true });

const { t, locale } = useI18n();

const statusHint = computed(() =>
  status.value === "pending"
    ? t("localization.editor.status_hint_pending")
    : t("localization.editor.status_hint_final"),
);

const historyLine = computed(() => {
  const date = formatShortDate(history.lastTranslatedAt, locale.value);
  if (!date) return t("localization.editor.history_none");
  if (history.translatedBy) {
    return t("localization.editor.history_translated_by", { name: history.translatedBy, date });
  }
  return t("localization.editor.history_translated", { date });
});
</script>

<template>
  <div class="flex flex-col gap-5">
    <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 sm:gap-x-5">
      <div class="flex flex-col gap-1.5">
        <Label for="localization-status-select" class="text-[13px]">
          {{ $t("localization.editor.status") }}
        </Label>
        <Select v-model="status" :disabled="!canEdit">
          <SelectTrigger id="localization-status-select" class="w-full">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem
              v-for="option in STATUS_KEYS"
              :key="option"
              :value="option"
              :disabled="option === 'final' && finalUnavailable"
            >
              {{ $t(STATUS_I18N[option]) }}
            </SelectItem>
          </SelectContent>
        </Select>
        <span class="text-xs text-muted-foreground">{{ statusHint }}</span>
      </div>

      <div class="flex flex-col gap-1.5">
        <Label for="localization-vo-select" class="text-[13px]">
          {{ $t("localization.editor.voice_over") }}
        </Label>
        <Select v-if="voEligible" v-model="voStatus" :disabled="!canEdit">
          <SelectTrigger id="localization-vo-select" class="w-full">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem v-for="option in VO_STATUS_KEYS" :key="option" :value="option">
              {{ $t(VO_I18N[option]) }}
            </SelectItem>
          </SelectContent>
        </Select>
        <p
          v-else
          id="localization-vo-select"
          class="flex h-9 items-center rounded-md border border-dashed border-border px-3 text-sm text-muted-foreground"
        >
          {{ $t("localization.editor.voice_over_not_applicable") }}
        </p>
        <span class="text-xs text-muted-foreground">
          {{ $t("localization.editor.voice_over_hint") }}
        </span>
      </div>
    </div>

    <div class="flex flex-col gap-1.5">
      <div class="flex items-baseline justify-between">
        <Label for="localization-translator-notes" class="text-[13px]">
          {{ $t("localization.editor.notes") }}
        </Label>
        <span class="text-xs text-muted-foreground">{{
          $t("localization.editor.notes_hint")
        }}</span>
      </div>
      <Textarea
        id="localization-translator-notes"
        v-model="translatorNotes"
        class="min-h-16 resize-y"
        :disabled="!canEdit"
        :placeholder="$t('localization.editor.notes_placeholder')"
      />
    </div>

    <div class="flex flex-wrap items-center gap-3.5 text-xs text-muted-foreground">
      <span class="inline-flex items-center gap-1.5">
        <History class="size-[13px]" aria-hidden="true" />
        {{ historyLine }}
      </span>
      <span v-if="history.machineTranslated" class="inline-flex items-center gap-1.5">
        <Sparkles class="size-[13px]" aria-hidden="true" />
        {{ $t("localization.flags.machine") }}
      </span>
    </div>
  </div>
</template>
