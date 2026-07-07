<script setup lang="ts">
import { useLiveForm, type Form } from "live_vue";
import { ArrowLeft, ArrowRight, CheckCircle2 } from "lucide-vue-next";
import { computed, onMounted, ref } from "vue";
import PasswordInput from "@components/forms/PasswordInput.vue";
import LiveLink from "@components/navigation/LiveLink.vue";
import { Button } from "@components/ui/button/index.ts";
import { Label } from "@components/ui/label/index.ts";

interface ResetPasswordValues {
  password: string;
  password_confirmation: string;
}

type ResetPasswordForm = Form<ResetPasswordValues> & { action?: string };

const {
  form: formProp,
  loginUrl = "/users/log-in",
  resetComplete = false,
} = defineProps<{
  form: ResetPasswordForm;
  loginUrl?: string;
  resetComplete?: boolean;
}>();

const form = useLiveForm(() => formProp, {
  changeEvent: "validate",
  submitEvent: "reset_password",
  debounceInMiliseconds: 300,
});

const password = form.field("password");
const passwordConfirmation = form.field("password_confirmation");
const passwordInput = ref<InstanceType<typeof PasswordInput> | null>(null);

const passwordValue = computed({
  get: () => String(password.value.value || ""),
  set: (value: string) => {
    password.value.value = value;
  },
});

const passwordConfirmationValue = computed({
  get: () => String(passwordConfirmation.value.value || ""),
  set: (value: string) => {
    passwordConfirmation.value.value = value;
  },
});

const showPasswordError = computed(
  () =>
    Boolean(password.errorMessage.value) &&
    (formProp.action === "insert" || password.isDirty.value || password.isTouched.value),
);

const showPasswordConfirmationError = computed(
  () =>
    Boolean(passwordConfirmation.errorMessage.value) &&
    (formProp.action === "insert" ||
      passwordConfirmation.isDirty.value ||
      passwordConfirmation.isTouched.value),
);

const passwordInputAttrs = computed(() => {
  const {
    value: _value,
    onInput: _onInput,
    "aria-invalid": _ariaInvalid,
    "aria-describedby": ariaDescribedBy,
    ...attrs
  } = password.inputAttrs.value;

  return {
    ...attrs,
    "aria-invalid": showPasswordError.value ? true : undefined,
    "aria-describedby": showPasswordError.value ? ariaDescribedBy : undefined,
  };
});

const passwordConfirmationInputAttrs = computed(() => {
  const {
    value: _value,
    onInput: _onInput,
    "aria-invalid": _ariaInvalid,
    "aria-describedby": ariaDescribedBy,
    ...attrs
  } = passwordConfirmation.inputAttrs.value;

  return {
    ...attrs,
    "aria-invalid": showPasswordConfirmationError.value ? true : undefined,
    "aria-describedby": showPasswordConfirmationError.value ? ariaDescribedBy : undefined,
  };
});

function updatePassword(value: string | number): void {
  passwordValue.value = String(value);
}

function updatePasswordConfirmation(value: string | number): void {
  passwordConfirmationValue.value = String(value);
}

onMounted(() => {
  if (!resetComplete) {
    passwordInput.value?.focus();
  }
});
</script>

<template>
  <div v-if="resetComplete" id="reset-password-complete" class="mx-auto max-w-sm space-y-6">
    <div class="space-y-4 text-center">
      <div class="flex justify-center">
        <div class="rounded-full bg-primary/10 p-3">
          <CheckCircle2 class="size-8 text-primary" />
        </div>
      </div>
      <div class="space-y-2">
        <h1 class="text-2xl font-bold tracking-tight">
          {{ $t("auth.reset_password.complete_title") }}
        </h1>
        <p class="text-sm text-muted-foreground">
          {{ $t("auth.reset_password.complete_description") }}
        </p>
      </div>
    </div>

    <Button
      as="a"
      :href="loginUrl"
      data-phx-link="redirect"
      data-phx-link-state="push"
      class="w-full"
    >
      {{ $t("auth.reset_password.continue_to_login") }}
      <ArrowRight class="ml-1" />
    </Button>
  </div>

  <div v-else class="mx-auto max-w-sm space-y-6">
    <div class="text-center space-y-2">
      <h1 class="text-2xl font-bold tracking-tight">
        {{ $t("auth.reset_password.title") }}
      </h1>
      <p class="text-sm text-muted-foreground">
        {{ $t("auth.reset_password.subtitle") }}
      </p>
    </div>

    <form id="reset-password-form" novalidate @submit.prevent="form.submit()">
      <div class="mb-4 space-y-1.5">
        <Label for="reset-password">{{ $t("auth.reset_password.new_password") }}</Label>
        <PasswordInput
          v-bind="passwordInputAttrs"
          id="reset-password"
          ref="passwordInput"
          :model-value="passwordValue"
          name="user[password]"
          autocomplete="new-password"
          required
          @update:model-value="updatePassword"
        />
        <p
          v-if="showPasswordError"
          id="reset-password-error"
          role="alert"
          class="text-sm font-medium text-destructive"
        >
          {{ password.errorMessage.value }}
        </p>
      </div>

      <div class="mb-6 space-y-1.5">
        <Label for="reset-password-confirmation">
          {{ $t("auth.reset_password.confirm_password") }}
        </Label>
        <PasswordInput
          v-bind="passwordConfirmationInputAttrs"
          id="reset-password-confirmation"
          :model-value="passwordConfirmationValue"
          name="user[password_confirmation]"
          autocomplete="new-password"
          required
          @update:model-value="updatePasswordConfirmation"
        />
        <p
          v-if="showPasswordConfirmationError"
          id="reset-password-confirmation-error"
          role="alert"
          class="text-sm font-medium text-destructive"
        >
          {{ passwordConfirmation.errorMessage.value }}
        </p>
      </div>

      <Button id="reset-password-submit" type="submit" class="w-full">
        {{ $t("auth.reset_password.submit") }}
        <ArrowRight class="ml-1" />
      </Button>
    </form>

    <div class="text-center">
      <LiveLink
        :to="loginUrl"
        class="inline-flex items-center gap-1.5 text-sm font-medium text-muted-foreground transition hover:text-foreground"
      >
        <ArrowLeft class="size-4" />
        {{ $t("auth.reset_password.back_to_login") }}
      </LiveLink>
    </div>
  </div>
</template>
