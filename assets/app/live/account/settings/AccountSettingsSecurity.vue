<script setup lang="ts">
import { useLiveForm, type Form } from "live_vue";
import { computed, nextTick, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import PasswordInput from "@components/forms/PasswordInput.vue";
import {
  SettingsPage,
  SettingsReauthBanner,
  SettingsRow,
  SettingsSection,
  type SettingsReauthState,
} from "@components/settings";
import { Button } from "@components/ui/button";
import { Label } from "@components/ui/label";

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
  sudoGrant = null,
  sudoActive = true,
  reauth,
} = defineProps<{
  passwordForm: Form<PasswordFormValues>;
  currentEmail: string;
  triggerSubmit?: boolean;
  passwordAction: string;
  sudoGrant?: string | null;
  sudoActive?: boolean;
  reauth: SettingsReauthState;
}>();

const { t } = useI18n();

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

const showPasswordError = computed(
  () => password.errorMessage.value && (password.isDirty.value || password.isTouched.value),
);

const showPasswordConfirmationError = computed(
  () =>
    passwordConfirmation.errorMessage.value &&
    (passwordConfirmation.isDirty.value || passwordConfirmation.isTouched.value),
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

const editingPassword = ref(false);

// The password change is a native POST so the session cookie rotates; the
// LiveView validates first and flips `triggerSubmit` when the form is valid.
const hiddenFormRef = ref<HTMLFormElement | null>(null);

watch(
  () => triggerSubmit,
  async (value) => {
    if (value && hiddenFormRef.value) {
      await nextTick();
      hiddenFormRef.value.submit();
    }
  },
  { flush: "post" },
);
</script>

<template>
  <SettingsPage :title="t('settings.security.title')">
    <SettingsReauthBanner v-if="!sudoActive" :state="reauth" />

    <form ref="hiddenFormRef" :action="passwordAction" method="post" class="hidden">
      <input type="hidden" name="_csrf_token" :value="reauth.csrfToken" />
      <input v-if="sudoGrant" type="hidden" name="sudo_grant" :value="sudoGrant" />
      <input name="user[email]" type="hidden" autocomplete="username" :value="currentEmail" />
      <input name="user[password]" type="hidden" :value="passwordValue" />
      <input name="user[password_confirmation]" type="hidden" :value="passwordConfirmationValue" />
    </form>

    <SettingsSection
      :title="t('settings.security.password_section')"
      :locked="!sudoActive"
      :locked-label="t('settings.reauth.locked')"
    >
      <SettingsRow
        :label="t('settings.security.change_password')"
        :hint="t('settings.security.change_password_description')"
      >
        <Button
          v-if="!editingPassword"
          id="security-change-password"
          variant="outline"
          size="sm"
          :disabled="!sudoActive"
          @click="editingPassword = true"
        >
          {{ t("settings.security.change_password") }}
        </Button>
        <Button v-else variant="ghost" size="sm" @click="editingPassword = false">
          {{ t("settings.security.cancel") }}
        </Button>
      </SettingsRow>

      <form
        v-if="editingPassword"
        class="flex flex-col gap-4 px-4 py-3.5"
        @submit.prevent="passwordForm.submit()"
      >
        <input type="hidden" autocomplete="username" :value="currentEmail" />

        <div class="flex flex-col gap-1.5">
          <Label for="security-password">{{ t("settings.security.new_password") }}</Label>
          <PasswordInput
            v-bind="passwordInputAttrs"
            id="security-password"
            :model-value="passwordValue"
            autocomplete="new-password"
            required
            @update:model-value="updatePassword"
          />
          <p v-if="showPasswordError" class="text-[13px] text-destructive">
            {{ password.errorMessage.value }}
          </p>
        </div>

        <div class="flex flex-col gap-1.5">
          <Label for="security-password-confirmation">
            {{ t("settings.security.confirm_password") }}
          </Label>
          <PasswordInput
            v-bind="passwordConfirmationInputAttrs"
            id="security-password-confirmation"
            :model-value="passwordConfirmationValue"
            autocomplete="new-password"
            @update:model-value="updatePasswordConfirmation"
          />
          <p v-if="showPasswordConfirmationError" class="text-[13px] text-destructive">
            {{ passwordConfirmation.errorMessage.value }}
          </p>
        </div>

        <div class="flex justify-end">
          <Button type="submit" size="sm">{{ t("settings.security.update_password") }}</Button>
        </div>
      </form>
    </SettingsSection>
  </SettingsPage>
</template>
