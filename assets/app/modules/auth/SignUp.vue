<script setup>
import { useLiveForm } from "live_vue";
import { onMounted, ref } from "vue";
import { Button } from "@components/ui/button/index.ts";
import { Input } from "@components/ui/input/index.ts";
import { Label } from "@components/ui/label/index.ts";
import { Separator } from "@components/ui/separator/index.ts";
import { Eye, EyeOff } from "lucide-vue-next";

const {
  form: formProp,
  loginUrl,
  oauthAction,
  userEmail,
} = defineProps({
  form: { type: Object, required: true },
  loginUrl: { type: String, default: "/users/log-in" },
  oauthAction: { type: String, default: "login" },
  userEmail: { type: String, required: true },
});

const form = useLiveForm(() => formProp, {
  changeEvent: "validate",
  submitEvent: "save",
  debounceInMilliseconds: 300,
});

const email = form.field("email");
const password = form.field("password");
const passwordConfirmation = form.field("password_confirmation");
const emailInput = ref(null);
const emailVal = ref(userEmail);
const showPassword = ref(false);
const showPasswordConfirmation = ref(false);

onMounted(() => {
  emailInput.value?.focus();
});

const githubHref = oauthAction === "link" ? "/auth/github/link" : "/auth/github";
const googleHref = oauthAction === "link" ? "/auth/google/link" : "/auth/google";
const discordHref = oauthAction === "link" ? "/auth/discord/link" : "/auth/discord";
</script>

<template>
  <div class="mx-auto max-w-sm space-y-4">
    <div class="text-center space-y-2">
      <h1 class="text-2xl font-bold tracking-tight">Complete your account</h1>
      <p class="text-sm text-muted-foreground">
        Welcome to the beta! Define your password to access your workspace.
      </p>
    </div>

    <div class="space-y-4">
      <div class="space-y-1.5 hidden">
        <!-- We still need to send the email with the form, but we can do it via a hidden input that always has the value -->
        <input type="hidden" name="user[email]" :value="userEmail" />
      </div>
      <div class="space-y-1.5">
        <Label for="register-email">Email</Label>
        <Input
          id="register-email"
          ref="emailInput"
          v-model="emailVal"
          type="email"
          autocomplete="username"
          readonly
          class="bg-muted text-muted-foreground cursor-not-allowed"
          required
        />
      </div>

      <div class="space-y-1.5">
        <Label for="register-password">Password</Label>
        <div class="relative">
          <input
            id="register-password"
            v-bind="password.inputAttrs.value"
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
        <Label for="register-password-confirmation">Confirm Password</Label>
        <div class="relative">
          <input
            id="register-password-confirmation"
            v-bind="passwordConfirmation.inputAttrs.value"
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

      <Button class="w-full" @click="form.submit()"> Create an account </Button>
    </div>
  </div>
</template>
