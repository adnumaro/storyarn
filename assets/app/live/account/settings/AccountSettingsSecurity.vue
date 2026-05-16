<script setup lang="ts">
import { useLiveForm, type Form } from "live_vue";
import { Info } from "lucide-vue-next";
import { computed, ref, watch } from "vue";
import { Button } from "@components/ui/button";
import { Input } from "@components/ui/input";
import { Label } from "@components/ui/label";
import { Separator } from "@components/ui/separator";

interface PasswordFormValues {
  email: string;
  password: string;
  password_confirmation: string;
}

const {
  passwordForm: passwordFormProp,
  currentEmail,
  triggerSubmit = false,
  passwordAction,
} = defineProps<{
  passwordForm: Form<PasswordFormValues>;
  currentEmail: string;
  triggerSubmit?: boolean;
  passwordAction: string;
}>();

const passwordForm = useLiveForm(() => passwordFormProp, {
  changeEvent: "validate_password",
  submitEvent: "update_password",
  debounceInMiliseconds: 300,
});

const password = passwordForm.field("password");
const passwordConfirmation = passwordForm.field("password_confirmation");

const passwordValue = computed({
  get: () => password.value.value ?? "",
  set: (value: string) => {
    password.value.value = value;
  },
});

const passwordConfirmationValue = computed({
  get: () => passwordConfirmation.value.value ?? "",
  set: (value: string) => {
    passwordConfirmation.value.value = value;
  },
});

const passwordInputAttrs = computed(() => {
  const { value: _value, onInput: _onInput, ...attrs } = password.inputAttrs.value;
  return attrs;
});

const passwordConfirmationInputAttrs = computed(() => {
  const { value: _value, onInput: _onInput, ...attrs } = passwordConfirmation.inputAttrs.value;
  return attrs;
});

const showPasswordError = computed(
  () => password.errorMessage.value && (password.isDirty.value || password.isTouched.value),
);

const showPasswordConfirmationError = computed(
  () =>
    passwordConfirmation.errorMessage.value &&
    (passwordConfirmation.isDirty.value || passwordConfirmation.isTouched.value),
);

function updatePassword(value: string | number): void {
  passwordValue.value = String(value);
}

function updatePasswordConfirmation(value: string | number): void {
  passwordConfirmationValue.value = String(value);
}

// For the form action POST, we use a hidden form that triggers on valid submit
const hiddenFormRef = ref<HTMLFormElement | null>(null);
const csrfToken = ref(
  document.querySelector("meta[name=csrf-token]")?.getAttribute("content") ?? "",
);

watch(
  () => triggerSubmit,
  (val) => {
    if (val && hiddenFormRef.value) {
      hiddenFormRef.value.submit();
    }
  },
);
</script>

<template>
  <div class="space-y-8">
    <div class="space-y-1.5">
      <h1 class="text-2xl font-bold tracking-tight text-foreground">
        {{ $t("settings.security.title") }}
      </h1>
      <p class="text-base text-muted-foreground">{{ $t("settings.security.subtitle") }}</p>
    </div>

    <!-- Hidden form for password action POST -->
    <form ref="hiddenFormRef" :action="passwordAction" method="post" class="hidden">
      <input type="hidden" name="_csrf_token" :value="csrfToken" />
      <input type="hidden" name="_method" value="put" />
      <input
        :name="passwordForm.field('email')?.inputAttrs?.value?.name || 'user[email]'"
        type="hidden"
        autocomplete="username"
        :value="currentEmail"
      />
      <input :name="password.inputAttrs.value.name" type="hidden" :value="passwordValue" />
      <input
        :name="passwordConfirmation.inputAttrs.value.name"
        type="hidden"
        :value="passwordConfirmationValue"
      />
    </form>

    <!-- Password Section -->
    <section>
      <h3 class="text-lg font-semibold mb-4">{{ $t("settings.security.change_password") }}</h3>
      <p class="text-sm text-muted-foreground mb-4">
        {{ $t("settings.security.change_password_description") }}
      </p>

      <div class="space-y-4">
        <input type="hidden" autocomplete="username" :value="currentEmail" />

        <div class="space-y-1.5">
          <Label for="security-password">{{ $t("settings.security.new_password") }}</Label>
          <Input
            v-bind="passwordInputAttrs"
            id="security-password"
            :model-value="passwordValue"
            type="password"
            autocomplete="new-password"
            required
            @update:model-value="updatePassword"
          />
          <p v-if="showPasswordError" class="text-sm text-destructive mt-1">
            {{ password.errorMessage.value }}
          </p>
        </div>

        <div class="space-y-1.5">
          <Label for="security-password-confirmation">{{
            $t("settings.security.confirm_password")
          }}</Label>
          <Input
            v-bind="passwordConfirmationInputAttrs"
            id="security-password-confirmation"
            :model-value="passwordConfirmationValue"
            type="password"
            autocomplete="new-password"
            @update:model-value="updatePasswordConfirmation"
          />
          <p v-if="showPasswordConfirmationError" class="text-sm text-destructive mt-1">
            {{ passwordConfirmation.errorMessage.value }}
          </p>
        </div>

        <div class="flex justify-end gap-3">
          <Button @click="passwordForm.submit()">
            {{ $t("settings.security.update_password") }}
          </Button>
        </div>
      </div>
    </section>

    <Separator />

    <!-- Sessions Section (future) -->
    <section>
      <h3 class="text-lg font-semibold mb-4">
        {{ $t("settings.security.active_sessions.title") }}
      </h3>
      <p class="text-sm text-muted-foreground mb-4">
        {{ $t("settings.security.active_sessions.description") }}
      </p>
      <div
        class="flex items-center gap-2 rounded-md border border-border bg-muted/50 p-3 text-sm text-muted-foreground"
      >
        <Info class="size-5 shrink-0" />
        <span>{{ $t("settings.security.active_sessions.coming_soon") }}</span>
      </div>
    </section>
  </div>
</template>
