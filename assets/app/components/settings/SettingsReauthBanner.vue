<script setup lang="ts">
import { Shield } from "@lucide/vue";
import { nextTick, onBeforeUnmount, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import PasswordInput from "@components/forms/PasswordInput.vue";
import { Button } from "@components/ui/button";
import { useLive } from "@shared/composables/useLive";

/**
 * "Confirm it's you": re-authenticates in place. The LiveView answers the
 * `confirm_access` event with a signed handoff; the hidden form exchanges it
 * through the authenticated POST that rotates the session and returns here.
 */
export interface SettingsReauthState {
  confirmAction: string;
  csrfToken: string;
  returnTo: string;
  sudoHandoff: string | null;
  triggerSubmit: boolean;
}

const { state } = defineProps<{ state: SettingsReauthState }>();

const errorCodes = ["invalid_password", "rate_limited", "session_expired"] as const;
type ErrorCode = (typeof errorCodes)[number];

const { t } = useI18n();
const live = useLive();
const password = ref("");
const errorCode = ref<ErrorCode | null>(null);
const submitting = ref(false);
const hiddenFormRef = ref<HTMLFormElement | null>(null);
const confirmationTimeoutMs = 10_000;
let confirmationTimeout: ReturnType<typeof setTimeout> | undefined;
let nextAttemptId = 0;
let activeAttemptId: number | null = null;

watch(password, () => {
  errorCode.value = null;
});

watch(
  () => state.triggerSubmit,
  async (value) => {
    if (value && state.sudoHandoff && hiddenFormRef.value) {
      await nextTick();
      hiddenFormRef.value.submit();
    }
  },
  { flush: "post" },
);

function replyError(reply: unknown): ErrorCode | null {
  if (reply === null || typeof reply !== "object") return null;

  const error = (reply as { error?: unknown }).error;
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

function confirm(): void {
  if (submitting.value || password.value.length === 0) return;

  const attemptId = ++nextAttemptId;
  activeAttemptId = attemptId;
  submitting.value = true;
  errorCode.value = null;
  confirmationTimeout = setTimeout(() => {
    finishSubmission(attemptId, "session_expired");
  }, confirmationTimeoutMs);

  live.pushEvent(
    "confirm_access",
    { password: password.value },
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
  <div
    class="grid grid-cols-1 items-center gap-x-6 gap-y-3 rounded-lg border border-primary/35 bg-primary/[0.08] px-4 py-3.5 sm:grid-cols-[minmax(0,1fr)_auto]"
    data-testid="settings-reauth"
  >
    <div class="flex min-w-0 gap-3">
      <Shield class="mt-0.5 size-[18px] shrink-0 text-primary" />
      <div>
        <div class="font-medium">{{ t("settings.reauth.title") }}</div>
        <div class="text-[13px] text-muted-foreground">{{ t("settings.reauth.description") }}</div>
      </div>
    </div>

    <form class="flex items-center justify-end gap-2" @submit.prevent="confirm">
      <div class="w-[200px] max-w-full">
        <PasswordInput
          id="settings-reauth-password"
          v-model="password"
          autocomplete="current-password"
          :placeholder="t('settings.reauth.password')"
          :aria-label="t('settings.reauth.password')"
          :aria-invalid="errorCode ? true : undefined"
          :aria-describedby="errorCode ? 'settings-reauth-error' : undefined"
          :disabled="submitting"
        />
      </div>
      <Button type="submit" :disabled="submitting || password.length === 0">
        {{ t("settings.reauth.confirm") }}
      </Button>
    </form>

    <p
      v-if="errorCode"
      id="settings-reauth-error"
      class="text-[13px] text-destructive sm:col-span-2"
      role="alert"
    >
      {{ t(`auth.confirm_access.errors.${errorCode}`) }}
    </p>

    <form ref="hiddenFormRef" :action="state.confirmAction" method="post" class="hidden">
      <input type="hidden" name="_csrf_token" :value="state.csrfToken" />
      <input type="hidden" name="sudo_handoff" :value="state.sudoHandoff ?? ''" />
      <input type="hidden" name="return_to" :value="state.returnTo" />
    </form>
  </div>
</template>
