<script setup lang="ts">
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import { Button } from "@components/ui/button";
import { Label } from "@components/ui/label";
import { RadioGroup, RadioGroupItem } from "@components/ui/radio-group";
import { Textarea } from "@components/ui/textarea";

const {
  reasonCodes = [],
  maxNoteLength = 2000,
  error = null,
} = defineProps<{
  reasonCodes?: string[];
  maxNoteLength?: number;
  error?: string | null;
}>();

const emit = defineEmits<{
  submit: [reasonCode: string, note: string];
  cancel: [];
}>();

const { t } = useI18n();

const reasonCode = ref("");
const note = ref("");

const noteRequired = computed(() => reasonCode.value === "other");
const canSubmit = computed(
  () => reasonCode.value !== "" && (!noteRequired.value || note.value.trim() !== ""),
);

function submit(): void {
  if (!canSubmit.value) return;
  emit("submit", reasonCode.value, note.value.trim());
}
</script>

<template>
  <div class="space-y-2" data-testid="analysis-dismiss-form">
    <p class="text-xs font-medium">{{ t("flows.analysis.dismiss_reason_label") }}</p>
    <RadioGroup v-model="reasonCode" class="gap-1">
      <Label
        v-for="code in reasonCodes"
        :key="code"
        class="flex cursor-pointer items-center gap-2 rounded-md border px-2 py-1.5 text-xs font-normal"
        :class="
          reasonCode === code ? 'border-primary bg-primary/10' : 'border-border hover:bg-muted'
        "
      >
        <RadioGroupItem :value="code" class="size-3.5" />
        {{ t(`flows.analysis.reasons.${code}`) }}
      </Label>
    </RadioGroup>
    <Label class="block text-xs font-medium">
      {{ noteRequired ? t("flows.analysis.note_required_label") : t("flows.analysis.note_label") }}
      <Textarea v-model="note" :rows="2" :maxlength="maxNoteLength" class="mt-1 text-xs" />
    </Label>
    <p v-if="error" role="alert" class="text-xs text-destructive">{{ error }}</p>
    <div class="flex gap-2">
      <Button
        size="sm"
        class="text-xs"
        :disabled="!canSubmit"
        data-testid="analysis-dismiss-confirm"
        @click="submit"
      >
        {{ t("flows.analysis.dismiss_confirm") }}
      </Button>
      <Button variant="outline" size="sm" class="text-xs" @click="emit('cancel')">
        {{ t("flows.analysis.dismiss_cancel") }}
      </Button>
    </div>
  </div>
</template>
