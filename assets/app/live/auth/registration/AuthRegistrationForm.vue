<script setup lang="ts">
import { useLiveForm, type Form } from "live_vue";
import { computed, onMounted, ref } from "vue";
import PasswordInput from "@components/forms/PasswordInput.vue";
import LiveLink from "@components/navigation/LiveLink.vue";
import { Button } from "@components/ui/button/index.ts";
import { Input } from "@components/ui/input/index.ts";
import { Label } from "@components/ui/label/index.ts";

interface SignUpFormValues {
  email: string;
  password: string;
  password_confirmation: string;
}

type SignUpForm = Form<SignUpFormValues> & { action?: string };

const {
  form: formProp,
  userEmail,
  invited = false,
} = defineProps<{
  form: SignUpForm;
  loginUrl: string;
  userEmail?: string | null;
  invited?: boolean;
}>();

const form = useLiveForm(() => formProp, {
  changeEvent: "validate",
  submitEvent: "save",
  debounceInMiliseconds: 300,
});

const email = form.field("email");
const password = form.field("password");
const passwordConfirmation = form.field("password_confirmation");
const emailInput = ref<{ focus: () => void } | null>(null);

const emailValue = computed({
  get: () => String(email.value.value || ""),
  set: (value: string) => {
    email.value.value = value;
  },
});

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

const showEmailError = computed(
  () =>
    !invited &&
    Boolean(email.errorMessage.value) &&
    (formProp.action === "insert" || email.isDirty.value || email.isTouched.value),
);

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

function updateEmail(value: string | number): void {
  emailValue.value = String(value);
}

function updatePassword(value: string | number): void {
  passwordValue.value = String(value);
}

function updatePasswordConfirmation(value: string | number): void {
  passwordConfirmationValue.value = String(value);
}

onMounted(() => {
  emailInput.value?.focus();
});
</script>

<template>
  <div class="mx-auto max-w-sm space-y-4">
    <div class="text-center space-y-2">
      <h1 class="text-2xl font-bold tracking-tight">
        {{ $t(invited ? "auth.sign_up.invited_title" : "auth.sign_up.title") }}
      </h1>
      <p class="text-sm text-muted-foreground">
        {{ $t(invited ? "auth.sign_up.invited_subtitle" : "auth.sign_up.subtitle") }}
      </p>
    </div>

    <form id="registration-form" class="space-y-4" novalidate @submit.prevent="form.submit()">
      <div class="space-y-1.5">
        <Label for="register-email">
          {{ $t("auth.email") }}
        </Label>
        <Input
          v-if="invited"
          id="register-email"
          ref="emailInput"
          :model-value="userEmail || ''"
          type="email"
          readonly
          class="bg-muted text-muted-foreground cursor-not-allowed"
        />
        <Input
          v-else
          v-bind="emailInputAttrs"
          id="register-email"
          ref="emailInput"
          :model-value="emailValue"
          type="email"
          autocomplete="email"
          required
          @update:model-value="updateEmail"
        />
        <p
          v-if="showEmailError"
          id="registration-email-error"
          role="alert"
          class="mt-1 text-sm text-destructive"
        >
          {{ email.errorMessage.value }}
        </p>
      </div>

      <div class="space-y-1.5">
        <Label for="register-password">
          {{ $t("auth.password") }}
        </Label>
        <PasswordInput
          v-bind="passwordInputAttrs"
          id="register-password"
          :model-value="passwordValue"
          autocomplete="new-password"
          required
          @update:model-value="updatePassword"
        />
        <p
          v-if="showPasswordError"
          id="registration-password-error"
          role="alert"
          class="text-sm text-destructive mt-1"
        >
          {{ password.errorMessage.value }}
        </p>
      </div>

      <div class="space-y-1.5">
        <Label for="register-password-confirmation">{{
          $t("auth.sign_up.confirm_password")
        }}</Label>
        <PasswordInput
          v-bind="passwordConfirmationInputAttrs"
          id="register-password-confirmation"
          :model-value="passwordConfirmationValue"
          autocomplete="new-password"
          required
          @update:model-value="updatePasswordConfirmation"
        />
        <p
          v-if="showPasswordConfirmationError"
          id="registration-password-confirmation-error"
          role="alert"
          class="text-sm text-destructive mt-1"
        >
          {{ passwordConfirmation.errorMessage.value }}
        </p>
      </div>

      <Button id="registration-submit" type="submit" class="w-full">
        {{ $t("auth.sign_up.submit") }}
      </Button>
    </form>

    <p class="text-center text-sm text-muted-foreground">
      {{ $t("auth.sign_up.has_account") }}
      <LiveLink :to="loginUrl" class="font-semibold text-primary transition hover:text-primary/80">
        {{ $t("auth.sign_up.log_in") }}
      </LiveLink>
    </p>
  </div>
</template>
