<script setup lang="ts">
import { ArrowRight, LoaderCircle, Shield } from "lucide-vue-next";
import { nextTick, onBeforeUnmount, ref, watch } from "vue";
import PasswordInput from "@components/forms/PasswordInput.vue";
import { Button } from "@components/ui/button/index.ts";
import { Input } from "@components/ui/input/index.ts";
import { Label } from "@components/ui/label/index.ts";
import { useLive } from "@shared/composables/useLive.ts";

const {
  email,
  backUrl,
  confirmAction,
  csrfToken,
  returnTo,
  sudoHandoff = null,
  triggerSubmit = false,
} = defineProps<{
  email: string;
  backUrl: string;
  confirmAction: string;
  csrfToken: string;
  returnTo: string;
  sudoHandoff?: string | null;
  triggerSubmit?: boolean;
}>();

const errorCodes = ["invalid_password", "rate_limited", "session_expired"] as const;
type ErrorCode = (typeof errorCodes)[number];

const live = useLive();
const passwordValue = ref("");
const errorCode = ref<ErrorCode | null>(null);
const submitting = ref(false);
const hiddenFormRef = ref<HTMLFormElement | null>(null);
const confirmationTimeoutMs = 10_000;
let confirmationTimeout: ReturnType<typeof setTimeout> | undefined;
let nextAttemptId = 0;
let activeAttemptId: number | null = null;

watch(passwordValue, () => {
  errorCode.value = null;
});

watch(
  () => triggerSubmit,
  async (value) => {
    if (value && sudoHandoff && hiddenFormRef.value) {
      await nextTick();
      hiddenFormRef.value.submit();
    }
  },
  { flush: "post" },
);

function replyError(reply: unknown): ErrorCode | null {
  if (reply === null || typeof reply !== "object") return null;

  const error = (reply as Record<string, unknown>).error;
  return typeof error === "string" && errorCodes.includes(error as ErrorCode)
    ? (error as ErrorCode)
    : null;
}

function finishSubmission(attemptId: number, error: ErrorCode | null): void {
  if (activeAttemptId !== attemptId) return;

  if (confirmationTimeout !== undefined) clearTimeout(confirmationTimeout);
  confirmationTimeout = undefined;
  activeAttemptId = null;
  submitting.value = false;
  errorCode.value = error;
}

onBeforeUnmount(() => {
  if (confirmationTimeout !== undefined) clearTimeout(confirmationTimeout);
  confirmationTimeout = undefined;
  activeAttemptId = null;
});

function confirmAccess(): void {
  if (submitting.value || passwordValue.value.length === 0) return;

  const attemptId = ++nextAttemptId;
  activeAttemptId = attemptId;
  submitting.value = true;
  errorCode.value = null;
  confirmationTimeout = setTimeout(() => {
    finishSubmission(attemptId, "session_expired");
  }, confirmationTimeoutMs);

  live.pushEvent(
    "confirm_access",
    { password: passwordValue.value },
    (reply) => {
      finishSubmission(attemptId, replyError(reply));
    },
    () => {
      finishSubmission(attemptId, "session_expired");
    },
  );
}
</script>

<template>
  <div class="mx-auto max-w-sm space-y-6">
    <form ref="hiddenFormRef" :action="confirmAction" method="post" class="hidden">
      <input type="hidden" name="_csrf_token" :value="csrfToken" />
      <input type="hidden" name="sudo_handoff" :value="sudoHandoff || ''" />
      <input type="hidden" name="return_to" :value="returnTo" />
    </form>

    <div class="text-center space-y-3">
      <div class="flex justify-center">
        <div class="rounded-full bg-yellow-500/10 p-3">
          <Shield class="size-8 text-yellow-500" />
        </div>
      </div>
      <div>
        <h1 class="text-2xl font-bold tracking-tight">
          {{ $t("auth.confirm_access.title") }}
        </h1>
        <p class="text-sm text-muted-foreground mt-2">
          {{ $t("auth.confirm_access.subtitle") }}
        </p>
      </div>
    </div>

    <form id="confirm-access-form" :aria-busy="submitting" @submit.prevent="confirmAccess">
      <div class="space-y-1.5 mb-4">
        <Label for="confirm-email">{{ $t("auth.email") }}</Label>
        <Input
          id="confirm-email"
          :model-value="email"
          type="email"
          name="user[email]"
          autocomplete="email"
          readonly
          required
        />
      </div>
      <div class="space-y-1.5 mb-4">
        <Label for="confirm-password">{{ $t("auth.password") }}</Label>
        <PasswordInput
          id="confirm-password"
          v-model="passwordValue"
          name="user[password]"
          autocomplete="current-password"
          :aria-invalid="Boolean(errorCode)"
          :aria-describedby="errorCode ? 'confirm-password-error' : undefined"
          required
          autofocus
        />
        <p
          v-if="errorCode"
          id="confirm-password-error"
          role="alert"
          class="text-sm font-medium text-destructive"
        >
          {{ $t(`auth.confirm_access.errors.${errorCode}`) }}
        </p>
      </div>
      <Button type="submit" class="w-full" :disabled="submitting">
        {{ $t("auth.confirm_access.submit") }}
        <LoaderCircle v-if="submitting" class="ml-1 size-4 animate-spin" />
        <ArrowRight v-else class="ml-1 size-4" />
      </Button>
    </form>

    <div class="text-center">
      <a
        id="confirm-access-back-link"
        :href="backUrl"
        data-phx-link="redirect"
        data-phx-link-state="push"
        class="text-sm text-muted-foreground hover:text-foreground transition-colors"
      >
        {{ $t("auth.confirm_access.go_back") }}
      </a>
    </div>
  </div>
</template>
