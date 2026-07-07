<script setup lang="ts">
import { useLiveForm, type Form } from "live_vue";
import { computed, onMounted, ref } from "vue";
import PasswordInput from "@components/forms/PasswordInput.vue";
import { Button } from "@components/ui/button/index.ts";
import { Input } from "@components/ui/input/index.ts";
import { Label } from "@components/ui/label/index.ts";

interface SignUpFormValues {
  email: string;
  password: string;
  password_confirmation: string;
}

const { form: formProp, userEmail } = defineProps<{
  form: Form<SignUpFormValues>;
  loginUrl?: string;
  userEmail: string;
}>();

const form = useLiveForm(() => formProp, {
  changeEvent: "validate",
  submitEvent: "save",
  debounceInMiliseconds: 300,
});

const password = form.field("password");
const passwordConfirmation = form.field("password_confirmation");
const emailInput = ref<{ focus: () => void } | null>(null);
const emailVal = ref(userEmail);

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
        {{ $t("auth.sign_up.title") }}
      </h1>
      <p class="text-sm text-muted-foreground">
        {{ $t("auth.sign_up.subtitle") }}
      </p>
    </div>

    <div class="space-y-4">
      <div class="space-y-1.5 hidden">
        <input type="hidden" name="user[email]" :value="userEmail" />
      </div>
      <div class="space-y-1.5">
        <Label for="register-email">
          {{ $t("auth.email") }}
        </Label>
        <Input
          id="register-email"
          ref="emailInput"
          :model-value="emailVal"
          type="email"
          readonly
          class="bg-muted text-muted-foreground cursor-not-allowed"
        />
      </div>

      <div class="space-y-1.5">
        <Label for="register-password">
          {{ $t("auth.password") }}
        </Label>
        <PasswordInput
          v-bind="password.inputAttrs.value"
          id="register-password"
          :model-value="passwordValue"
          autocomplete="new-password"
          required
          @update:model-value="updatePassword"
        />
        <p
          v-if="password.errorMessage.value && password.isTouched.value"
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
          v-bind="passwordConfirmation.inputAttrs.value"
          id="register-password-confirmation"
          :model-value="passwordConfirmationValue"
          autocomplete="new-password"
          required
          @update:model-value="updatePasswordConfirmation"
        />
        <p
          v-if="passwordConfirmation.errorMessage.value && passwordConfirmation.isTouched.value"
          class="text-sm text-destructive mt-1"
        >
          {{ passwordConfirmation.errorMessage.value }}
        </p>
      </div>

      <Button class="w-full" @click="form.submit()">
        {{ $t("auth.sign_up.submit") }}
      </Button>
    </div>
  </div>
</template>
