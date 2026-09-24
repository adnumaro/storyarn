<script setup lang="ts">
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import { Button } from "@components/ui/button";
import { Input } from "@components/ui/input";
import { validTaskUrl } from "./decisionTask";

/** Links a task by its address, or corrects one; the title is optional. */
const {
  idPrefix,
  initialUrl = "",
  initialTitle = "",
  confirmLabel,
  pending = false,
} = defineProps<{
  idPrefix: string;
  initialUrl?: string;
  initialTitle?: string;
  confirmLabel: string;
  pending?: boolean;
}>();
const emit = defineEmits<{ confirm: [url: string, title: string | null]; cancel: [] }>();
const { t } = useI18n();
const url = ref(initialUrl);
const title = ref(initialTitle);
const touched = ref(false);
const valid = computed(() => validTaskUrl(url.value));

function submit() {
  touched.value = true;
  if (!valid.value || pending) return;
  emit("confirm", url.value.trim(), title.value.trim() || null);
}
</script>
<template>
  <form :id="`${idPrefix}-form`" class="flex flex-col gap-2" novalidate @submit.prevent="submit">
    <label :for="`${idPrefix}-url`" class="text-xs text-muted-foreground">{{
      t("brainstormingDecisions.tasks.url")
    }}</label>
    <Input
      :id="`${idPrefix}-url`"
      v-model="url"
      type="url"
      inputmode="url"
      autocomplete="off"
      placeholder="https://"
      class="h-8 text-sm"
      :maxlength="2048"
      :aria-invalid="touched && !valid"
      :aria-describedby="touched && !valid ? `${idPrefix}-url-error` : undefined"
      @blur="touched = true"
    />
    <p v-if="touched && !valid" :id="`${idPrefix}-url-error`" class="text-xs text-destructive">
      {{ t("brainstormingDecisions.tasks.invalidUrl") }}
    </p>
    <label :for="`${idPrefix}-title`" class="mt-1 text-xs text-muted-foreground">{{
      t("brainstormingDecisions.tasks.titleOptional")
    }}</label>
    <Input :id="`${idPrefix}-title`" v-model="title" class="h-8 text-sm" :maxlength="160" />
    <p class="text-xs text-muted-foreground">{{ t("brainstormingDecisions.tasks.manualHint") }}</p>
    <div class="mt-1 flex justify-end gap-1.5">
      <Button type="button" variant="ghost" size="sm" @click="emit('cancel')">{{
        t("brainstormingDecisions.cancel")
      }}</Button>
      <Button :id="`${idPrefix}-confirm`" type="submit" size="sm" :disabled="pending">{{
        confirmLabel
      }}</Button>
    </div>
  </form>
</template>
