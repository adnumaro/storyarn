<script setup lang="ts">
import { ArrowLeft, Sparkles } from "lucide-vue-next";
import { ref } from "vue";
import { useI18n } from "vue-i18n";
import { Badge } from "@components/ui/badge";
import { Button } from "@components/ui/button";
import { Label } from "@components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@components/ui/select";
import { Textarea } from "@components/ui/textarea";
import { useLive } from "@composables/useLive";

const { t } = useI18n();

interface LocalizedText {
  source_type: string;
  source_field: string;
  source_text: string;
  translated_text?: string;
  status?: string;
  translator_notes?: string;
  locale_code: string;
  word_count?: number;
  machine_translated?: boolean;
  last_translated_at?: string;
}

interface TranslationFormParams {
  translated_text?: string;
  status?: string;
  translator_notes?: string;
}

interface TranslationForm {
  params?: TranslationFormParams;
}

const {
  text,
  form,
  hasProvider = false,
  canEdit = false,
  backUrl,
} = defineProps<{
  text: LocalizedText;
  form: TranslationForm;
  hasProvider?: boolean;
  canEdit?: boolean;
  backUrl: string;
}>();

const live = useLive();

const translatedText = ref(form.params?.translated_text || text.translated_text || "");
const status = ref(form.params?.status || text.status || "pending");
const translatorNotes = ref(form.params?.translator_notes || text.translator_notes || "");
const saving = ref(false);
const translating = ref(false);

const statusOptions = [
  { key: "pending", label: t("localization.edit.status_pending") },
  { key: "draft", label: t("localization.edit.status_draft") },
  { key: "in_progress", label: t("localization.edit.status_in_progress") },
  { key: "review", label: t("localization.edit.status_review") },
  { key: "final", label: t("localization.edit.status_final") },
];

function saveTranslation() {
  saving.value = true;
  live.pushEvent(
    "save_translation",
    {
      localized_text: {
        translated_text: translatedText.value,
        status: status.value,
        translator_notes: translatorNotes.value,
      },
    },
    () => {
      saving.value = false;
    },
  );
}

function translateWithDeepL() {
  translating.value = true;
  live.pushEvent("translate_with_deepl", {}, () => {
    translating.value = false;
  });
}

live.handleEvent("text_updated", (payload) => {
  if (payload.translated_text !== undefined)
    translatedText.value = payload.translated_text as string;
  if (payload.status !== undefined) status.value = payload.status as string;
  if (payload.translator_notes !== undefined)
    translatorNotes.value = payload.translator_notes as string;
});

function formatDateTime(datetime: string | undefined) {
  if (!datetime) return "";
  const d = new Date(datetime);
  return d.toISOString().slice(0, 16).replace("T", " ");
}
</script>

<template>
  <div class="max-w-4xl mx-auto">
    <div class="flex items-center justify-between mb-6">
      <div>
        <h1 class="text-2xl font-bold tracking-tight">{{ $t("localization.edit.title") }}</h1>
        <p class="text-sm text-muted-foreground mt-1">
          <span class="font-mono">{{ text.source_type }}/{{ text.source_field }}</span>
        </p>
      </div>
      <a
        :href="backUrl"
        data-phx-link="redirect"
        data-phx-link-state="push"
        class="inline-flex items-center justify-center h-9 px-4 text-sm rounded-md text-muted-foreground hover:text-foreground hover:bg-accent transition-colors"
      >
        <ArrowLeft class="size-4 mr-1" />
        {{ $t("localization.edit.back") }}
      </a>
    </div>

    <div class="grid grid-cols-2 gap-6 mt-6">
      <!-- Source text -->
      <div>
        <h4 class="font-medium text-sm mb-2 text-muted-foreground">{{ $t("localization.edit.source") }}</h4>
        <div class="bg-muted rounded-lg p-4 min-h-32">
          <div class="prose prose-sm" v-html="text.source_text || ''"></div>
        </div>
        <div class="text-xs text-muted-foreground mt-1">{{ $t("localization.edit.word_count", text.word_count || 0) }}</div>
      </div>

      <!-- Translation -->
      <div>
        <h4 class="font-medium text-sm mb-2 text-muted-foreground">
          {{ $t("localization.edit.translation_label", { locale: text.locale_code }) }}
        </h4>

        <div class="space-y-3">
          <Textarea v-model="translatedText" :rows="6" :placeholder="$t('localization.edit.translation_placeholder')" />

          <div class="space-y-1.5">
            <Label>{{ $t("localization.edit.status") }}</Label>
            <Select v-model="status">
              <SelectTrigger>
                <SelectValue :placeholder="$t('localization.edit.select_status')" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem v-for="opt in statusOptions" :key="opt.key" :value="opt.key">
                  {{ opt.label }}
                </SelectItem>
              </SelectContent>
            </Select>
          </div>

          <div class="space-y-1.5">
            <Label>{{ $t("localization.edit.translator_notes") }}</Label>
            <Textarea
              v-model="translatorNotes"
              :rows="2"
              :placeholder="$t('localization.edit.notes_placeholder')"
            />
          </div>

          <div class="flex items-center gap-3">
            <Button @click="saveTranslation" :disabled="saving">
              {{ saving ? $t("localization.edit.saving") : $t("localization.edit.save") }}
            </Button>
            <Button
              v-if="hasProvider"
              variant="outline"
              @click="translateWithDeepL"
              :disabled="translating"
            >
              <Sparkles class="size-4 mr-1" />
              {{ translating ? $t("localization.edit.translating") : $t("localization.edit.translate_deepl") }}
            </Button>
          </div>
        </div>
      </div>
    </div>

    <!-- Metadata -->
    <div class="mt-6 text-sm text-muted-foreground flex items-center gap-2">
      <Badge v-if="text.machine_translated" variant="outline">{{ $t("localization.edit.machine_translated") }}</Badge>
      <span v-if="text.last_translated_at">
        {{ $t("localization.edit.last_translated", { date: formatDateTime(text.last_translated_at) }) }}
      </span>
    </div>
  </div>
</template>
