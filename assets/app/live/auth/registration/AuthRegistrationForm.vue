<script setup lang="ts">
import { useLiveForm, type Form } from "live_vue";
import { onMounted, ref } from "vue";
import { Button } from "@components/ui/button/index.ts";
import { Input } from "@components/ui/input/index.ts";
import { Label } from "@components/ui/label/index.ts";
import { Eye, EyeOff } from "lucide-vue-next";

interface SignUpFormValues {
  email: string;
  password: string;
  password_confirmation: string;
}

const { form: formProp, userEmail } = defineProps<{
  form: Form<SignUpFormValues>;
  loginUrl?: string;
  oauthAction?: string;
  userEmail: string;
}>();

const form = useLiveForm(() => formProp, {
  changeEvent: "validate",
  submitEvent: "save",
  debounceInMiliseconds: 300,
});

const password = form.field("password");
const passwordConfirmation = form.field("password_confirmation");
const emailInput = ref<HTMLInputElement | null>(null);
const emailVal = ref(userEmail);
const showPassword = ref(false);
const showPasswordConfirmation = ref(false);

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
        <div class="relative">
          <input
            v-bind="password.inputAttrs.value"
            id="register-password"
            :type="showPassword ? 'text' : 'password'"
            autocomplete="new-password"
            class="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 pr-10 text-sm ring-offset-background file:border-0 file:bg-transparent file:text-sm file:font-medium placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50"
            required
          />
          <button
            type="button"
            class="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground focus:outline-none"
            @click="showPassword = !showPassword"
          >
            <Eye v-if="!showPassword" class="h-4 w-4" />
            <EyeOff v-else class="h-4 w-4" />
          </button>
        </div>
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
        <div class="relative">
          <input
            v-bind="passwordConfirmation.inputAttrs.value"
            id="register-password-confirmation"
            :type="showPasswordConfirmation ? 'text' : 'password'"
            autocomplete="new-password"
            class="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 pr-10 text-sm ring-offset-background file:border-0 file:bg-transparent file:text-sm file:font-medium placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50"
            required
          />
          <button
            type="button"
            class="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground focus:outline-none"
            @click="showPasswordConfirmation = !showPasswordConfirmation"
          >
            <Eye v-if="!showPasswordConfirmation" class="h-4 w-4" />
            <EyeOff v-else class="h-4 w-4" />
          </button>
        </div>
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
