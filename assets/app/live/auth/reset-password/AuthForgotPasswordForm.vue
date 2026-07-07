<script setup lang="ts">
import { useLiveForm, useLiveVue, type Form } from "live_vue";
import { AlertCircle, ArrowLeft, ArrowRight, MailCheck } from "lucide-vue-next";
import { computed, onMounted, ref, watch } from "vue";
import { Button } from "@components/ui/button/index.ts";
import { Input } from "@components/ui/input/index.ts";
import { Label } from "@components/ui/label/index.ts";

interface PasswordResetRequestValues {
  email: string;
}

type PasswordResetRequestForm = Form<PasswordResetRequestValues> & { action?: string };

const {
  form: formProp,
  loginUrl = "/users/log-in",
  instructionsSent = false,
  requestError = null,
} = defineProps<{
  form: PasswordResetRequestForm;
  loginUrl?: string;
  instructionsSent?: boolean;
  requestError?: string | null;
}>();

const live = useLiveVue();
const form = useLiveForm(() => formProp, {
  changeEvent: "validate",
  submitEvent: "send_instructions",
  debounceInMiliseconds: 300,
});

const email = form.field("email");
const emailInput = ref<InstanceType<typeof Input> | null>(null);

const emailValue = computed({
  get: () => String(email.value.value || ""),
  set: (value: string) => {
    email.value.value = value;
  },
});

const showEmailError = computed(
  () =>
    Boolean(email.errorMessage.value) &&
    (formProp.action === "insert" || email.isDirty.value || email.isTouched.value),
);

const emailInputAttrs = computed(() => {
  const {
    value: _value,
    onInput: _onInput,
    "aria-invalid": _ariaInvalid,
    "aria-describedby": ariaDescribedBy,
    ...attrs
  } = email.inputAttrs.value;

  return {
    ...attrs,
    "aria-invalid": showEmailError.value ? true : undefined,
    "aria-describedby": showEmailError.value ? ariaDescribedBy : undefined,
  };
});

function updateEmail(value: string | number): void {
  emailValue.value = String(value);
}

function requestAnotherEmail(): void {
  live.pushEvent("reset_request_form", {});
}

onMounted(() => {
  if (!instructionsSent) {
    emailInput.value?.focus();
  }
});

watch(
  () => instructionsSent,
  (sent) => {
    if (!sent) {
      requestAnimationFrame(() => emailInput.value?.focus());
    }
  },
  { flush: "post" },
);
</script>

<template>
  <div v-if="instructionsSent" id="forgot-password-confirmation" class="mx-auto max-w-sm space-y-6">
    <div class="space-y-4 text-center">
      <div class="flex justify-center">
        <div class="rounded-full bg-primary/10 p-3">
          <MailCheck class="size-8 text-primary" />
        </div>
      </div>
      <div class="space-y-2">
        <h1 class="text-2xl font-bold tracking-tight">
          {{ $t("auth.reset_request.sent_title") }}
        </h1>
        <p class="text-sm text-muted-foreground">
          {{ $t("auth.reset_request.sent_description") }}
        </p>
      </div>
    </div>

    <div class="space-y-3">
      <Button
        as="a"
        :href="loginUrl"
        data-phx-link="redirect"
        data-phx-link-state="push"
        class="w-full"
      >
        {{ $t("auth.reset_request.back_to_login") }}
        <ArrowRight class="ml-1" />
      </Button>
      <Button
        id="forgot-password-try-another"
        type="button"
        variant="ghost"
        class="w-full"
        @click="requestAnotherEmail"
      >
        {{ $t("auth.reset_request.try_another_email") }}
      </Button>
    </div>
  </div>

  <div v-else class="mx-auto max-w-sm space-y-6">
    <div class="text-center space-y-2">
      <h1 class="text-2xl font-bold tracking-tight">
        {{ $t("auth.reset_request.title") }}
      </h1>
      <p class="text-sm text-muted-foreground">
        {{ $t("auth.reset_request.subtitle") }}
      </p>
    </div>

    <div
      v-if="requestError"
      id="forgot-password-request-error"
      role="alert"
      class="flex items-start gap-3 rounded-lg border border-destructive/40 bg-destructive/10 p-3 text-sm text-destructive"
    >
      <AlertCircle class="mt-0.5 size-4 shrink-0" />
      <p>{{ requestError }}</p>
    </div>

    <form id="forgot-password-form" novalidate @submit.prevent="form.submit()">
      <div class="mb-6 space-y-1.5">
        <Label for="forgot-password-email">{{ $t("auth.email") }}</Label>
        <Input
          v-bind="emailInputAttrs"
          id="forgot-password-email"
          ref="emailInput"
          :model-value="emailValue"
          type="email"
          name="password_reset[email]"
          autocomplete="email"
          required
          @update:model-value="updateEmail"
        />
        <p
          v-if="showEmailError"
          id="forgot-password-email-error"
          role="alert"
          class="text-sm font-medium text-destructive"
        >
          {{ email.errorMessage.value }}
        </p>
      </div>

      <Button id="forgot-password-submit" type="submit" class="w-full">
        {{ $t("auth.reset_request.submit") }}
        <ArrowRight class="ml-1" />
      </Button>
    </form>

    <div class="text-center">
      <a
        :href="loginUrl"
        data-phx-link="redirect"
        data-phx-link-state="push"
        class="inline-flex items-center gap-1.5 text-sm font-medium text-muted-foreground transition hover:text-foreground"
      >
        <ArrowLeft class="size-4" />
        {{ $t("auth.reset_request.back_to_login") }}
      </a>
    </div>
  </div>
</template>
