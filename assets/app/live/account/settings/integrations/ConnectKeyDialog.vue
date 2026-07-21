<script setup lang="ts">
import { ExternalLink, KeyRound, LoaderCircle } from "lucide-vue-next";
import { computed, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import PasswordInput from "@components/forms/PasswordInput.vue";
import { Button } from "@components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@components/ui/dialog";
import { Label } from "@components/ui/label";
import type { IntegrationCardData } from "./IntegrationCard.vue";

const {
  open,
  card,
  submitting = false,
} = defineProps<{
  open: boolean;
  card: IntegrationCardData;
  submitting?: boolean;
}>();

const emit = defineEmits<{
  submit: [apiKey: string, onResult: (errorCode: string | null) => void];
  cancel: [];
}>();

const { t } = useI18n();

const apiKey = ref("");
const errorCode = ref<string | null>(null);

const localOpen = computed({
  get: () => open,
  set: (value: boolean) => {
    if (!value) handleCancel();
  },
});

const canSubmit = computed(() => apiKey.value.trim().length > 0 && !submitting);

const errorMessage = computed(() => {
  if (!errorCode.value) return null;
  return t(`integrations.errors.${errorCode.value}`, t("integrations.errors.unknown_error"));
});

watch(
  () => open,
  (isOpen) => {
    if (isOpen) {
      apiKey.value = "";
      errorCode.value = null;
    }
  },
);

function handleSubmit(event: Event): void {
  event.preventDefault();
  if (!canSubmit.value) return;

  errorCode.value = null;
  emit("submit", apiKey.value.trim(), (code) => {
    errorCode.value = code;
  });
}

// While the connect request is in flight the dialog must not be dismissible:
// cancelling would only hide the dialog while the server may still persist
// the key, leaving an integration connected behind the user's back.
function handleCancel(): void {
  if (submitting) return;
  emit("cancel");
}

function blockDismissWhileSubmitting(event: Event): void {
  if (submitting) event.preventDefault();
}
</script>

<template>
  <Dialog v-model:open="localOpen">
    <DialogContent
      class="sm:max-w-md"
      @escape-key-down="blockDismissWhileSubmitting"
      @interact-outside="blockDismissWhileSubmitting"
      @pointer-down-outside="blockDismissWhileSubmitting"
    >
      <DialogHeader>
        <DialogTitle class="flex items-center gap-2">
          <KeyRound class="size-5 shrink-0 text-muted-foreground" />
          {{ t("integrations.connect.title", { name: card.name }) }}
        </DialogTitle>
        <DialogDescription>
          {{ t("integrations.connect.description", { name: card.name }) }}
        </DialogDescription>
      </DialogHeader>

      <form class="space-y-4" @submit="handleSubmit">
        <div class="space-y-2">
          <Label :for="`api-key-${card.provider}`">
            {{ t("integrations.connect.label") }}
          </Label>
          <PasswordInput
            :id="`api-key-${card.provider}`"
            v-model="apiKey"
            :placeholder="card.key_placeholder"
            autocomplete="off"
            spellcheck="false"
            :aria-invalid="!!errorCode"
            :aria-describedby="errorCode ? `api-key-${card.provider}-error` : undefined"
            required
          />
          <a
            :href="card.key_generation_url"
            target="_blank"
            rel="noopener noreferrer"
            data-live-link-exempt="external-provider-console"
            class="inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground hover:underline"
          >
            {{ t("integrations.connect.get_key") }}
            <ExternalLink class="size-3" aria-hidden="true" />
          </a>
        </div>

        <p
          v-if="errorMessage"
          :id="`api-key-${card.provider}-error`"
          role="alert"
          class="rounded-md border border-destructive/40 bg-destructive/5 px-3 py-2 text-sm text-destructive"
        >
          {{ errorMessage }}
        </p>

        <DialogFooter>
          <Button type="button" variant="outline" :disabled="submitting" @click="handleCancel">
            {{ t("integrations.connect.cancel") }}
          </Button>
          <Button type="submit" :disabled="!canSubmit">
            <LoaderCircle v-if="submitting" class="size-4 animate-spin" aria-hidden="true" />
            {{ t("integrations.connect.submit") }}
          </Button>
        </DialogFooter>
      </form>
    </DialogContent>
  </Dialog>
</template>
