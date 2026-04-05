<script setup>
import { ArrowLeft, Sparkles } from "lucide-vue-next";
import { ref } from "vue";
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

const { text, form, hasProvider, canEdit, backUrl } = defineProps({
  text: { type: Object, required: true },
  form: { type: Object, required: true },
  hasProvider: { type: Boolean, default: false },
  canEdit: { type: Boolean, default: false },
  backUrl: { type: String, required: true },
});

const live = useLive();

const translatedText = ref(form.params?.translated_text || text.translated_text || "");
const status = ref(form.params?.status || text.status || "pending");
const translatorNotes = ref(form.params?.translator_notes || text.translator_notes || "");
const saving = ref(false);
const translating = ref(false);

const statusOptions = [
  { label: "Pending", value: "pending" },
  { label: "Draft", value: "draft" },
  { label: "In Progress", value: "in_progress" },
  { label: "Review", value: "review" },
  { label: "Final", value: "final" },
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

// Update local state when server pushes new text data
live.handleEvent("text_updated", (payload) => {
  if (payload.translated_text !== undefined) translatedText.value = payload.translated_text;
  if (payload.status !== undefined) status.value = payload.status;
  if (payload.translator_notes !== undefined) translatorNotes.value = payload.translator_notes;
});

function formatDateTime(datetime) {
  if (!datetime) return "";
  const d = new Date(datetime);
  return d.toISOString().slice(0, 16).replace("T", " ");
}
</script>

<template>
  <div class="max-w-4xl mx-auto">
    <div class="flex items-center justify-between mb-6">
      <div>
        <h1 class="text-2xl font-bold tracking-tight">Edit Translation</h1>
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
        Back
      </a>
    </div>

    <div class="grid grid-cols-2 gap-6 mt-6">
      <!-- Source text -->
      <div>
        <h4 class="font-medium text-sm mb-2 text-muted-foreground">Source</h4>
        <div class="bg-muted rounded-lg p-4 min-h-32">
          <div class="prose prose-sm" v-html="text.source_text || ''"></div>
        </div>
        <div class="text-xs text-muted-foreground mt-1">{{ text.word_count || 0 }} words</div>
      </div>

      <!-- Translation -->
      <div>
        <h4 class="font-medium text-sm mb-2 text-muted-foreground">
          Translation ({{ text.locale_code }})
        </h4>

        <div class="space-y-3">
          <Textarea v-model="translatedText" :rows="6" placeholder="Enter translation..." />

          <div class="space-y-1.5">
            <Label>Status</Label>
            <Select v-model="status">
              <SelectTrigger>
                <SelectValue placeholder="Select status" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem v-for="opt in statusOptions" :key="opt.value" :value="opt.value">
                  {{ opt.label }}
                </SelectItem>
              </SelectContent>
            </Select>
          </div>

          <div class="space-y-1.5">
            <Label>Translator Notes</Label>
            <Textarea
              v-model="translatorNotes"
              :rows="2"
              placeholder="Add notes for reviewers..."
            />
          </div>

          <div class="flex items-center gap-3">
            <Button @click="saveTranslation" :disabled="saving">
              {{ saving ? "Saving..." : "Save" }}
            </Button>
            <Button
              v-if="hasProvider"
              variant="outline"
              @click="translateWithDeepL"
              :disabled="translating"
            >
              <Sparkles class="size-4 mr-1" />
              {{ translating ? "Translating..." : "Translate with DeepL" }}
            </Button>
          </div>
        </div>
      </div>
    </div>

    <!-- Metadata -->
    <div class="mt-6 text-sm text-muted-foreground flex items-center gap-2">
      <Badge v-if="text.machine_translated" variant="outline"> Machine translated </Badge>
      <span v-if="text.last_translated_at">
        Last translated: {{ formatDateTime(text.last_translated_at) }}
      </span>
    </div>
  </div>
</template>
