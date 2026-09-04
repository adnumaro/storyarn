<script setup lang="ts">
import { useLiveForm, type Form } from "live_vue";
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import LiveLink from "@components/navigation/LiveLink.vue";
import SaveIndicator from "@components/SaveIndicator.vue";
import UserAvatar from "@components/UserAvatar.vue";
import {
  SettingsPage,
  SettingsReauthBanner,
  SettingsRow,
  SettingsSection,
  type SettingsReauthState,
} from "@components/settings";
import { Button } from "@components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@components/ui/dialog";
import { Input } from "@components/ui/input";
import { Label } from "@components/ui/label";
import { useLive } from "@shared/composables/useLive";

interface ProfileFormValues {
  display_name: string;
  locale: string | null;
}

const {
  profileForm: profileFormProp,
  email,
  saveStatus = "idle",
  sudoActive = true,
  reauth,
} = defineProps<{
  profileForm: Form<ProfileFormValues>;
  email: string;
  saveStatus?: "idle" | "saving" | "saved";
  sudoActive?: boolean;
  reauth: SettingsReauthState;
}>();

const { t } = useI18n();
const live = useLive();

const profileForm = useLiveForm(() => profileFormProp, {
  changeEvent: "validate_profile",
  submitEvent: "update_profile",
  debounceInMiliseconds: 300,
});

const displayName = profileForm.field("display_name");

const displayNameValue = computed({
  get: () => displayName.value.value ?? "",
  set: (value: string) => {
    displayName.value.value = value;
  },
});

const displayNameInputAttrs = computed(() => {
  const { value: _value, onInput: _onInput, ...attrs } = displayName.inputAttrs.value;
  return attrs;
});

function updateDisplayName(value: string | number): void {
  displayNameValue.value = String(value);
}

function saveDisplayName(): void {
  if (!sudoActive || !displayName.isDirty.value) return;
  profileForm.submit();
}

const emailDialogOpen = ref(false);
const newEmail = ref("");
const emailError = ref<string | null>(null);
const sendingEmail = ref(false);
// Each open of the dialog starts a new request generation; replies from a
// request made in a previous generation are ignored.
let emailRequestGeneration = 0;

function openEmailDialog(): void {
  emailRequestGeneration += 1;
  newEmail.value = "";
  emailError.value = null;
  sendingEmail.value = false;
  emailDialogOpen.value = true;
}

function requestEmailChange(): void {
  if (sendingEmail.value || newEmail.value.trim().length === 0) return;

  const generation = emailRequestGeneration;
  sendingEmail.value = true;
  emailError.value = null;

  live.pushEvent(
    "request_email_change",
    { email: newEmail.value.trim() },
    (reply) => {
      if (generation !== emailRequestGeneration) return;

      sendingEmail.value = false;
      const result = reply as { ok?: boolean; error?: string } | null;

      if (result?.ok) {
        emailDialogOpen.value = false;
      } else {
        emailError.value = result?.error ?? t("settings.profile.change_email_dialog.failed");
      }
    },
    () => {
      if (generation !== emailRequestGeneration) return;

      sendingEmail.value = false;
      emailError.value = t("settings.profile.change_email_dialog.failed");
    },
  );
}
</script>

<template>
  <SettingsPage :title="t('settings.profile.title')">
    <template #actions>
      <SaveIndicator :status="saveStatus" />
    </template>

    <SettingsReauthBanner v-if="!sudoActive" :state="reauth" />

    <SettingsSection
      :title="t('settings.profile.identity')"
      :locked="!sudoActive"
      :locked-label="t('settings.reauth.locked')"
    >
      <SettingsRow
        :label="t('settings.profile.display_name')"
        :hint="t('settings.profile.display_name_hint')"
        control="input"
        html-for="profile-display-name"
      >
        <template #leading>
          <UserAvatar :email="email" :display-name="displayNameValue" size="md" />
        </template>
        <div class="flex w-full flex-col gap-1">
          <Input
            v-bind="displayNameInputAttrs"
            id="profile-display-name"
            :model-value="displayNameValue"
            :placeholder="t('settings.profile.display_name_placeholder')"
            :disabled="!sudoActive"
            @update:model-value="updateDisplayName"
            @blur="saveDisplayName"
            @keydown.enter.prevent="saveDisplayName"
          />
          <p v-if="displayName.errorMessage.value" class="text-[13px] text-destructive">
            {{ displayName.errorMessage.value }}
          </p>
        </div>
      </SettingsRow>

      <SettingsRow :label="t('settings.profile.email')">
        <template #hint>{{ email }} · {{ t("settings.profile.email_hint") }}</template>
        <Button
          id="profile-change-email"
          variant="outline"
          size="sm"
          :disabled="!sudoActive"
          @click="openEmailDialog"
        >
          {{ t("settings.profile.change_email") }}
        </Button>
      </SettingsRow>

      <template #footer>
        {{ t("settings.profile.preferences_note") }}
        <LiveLink to="/users/settings/preferences" class="text-primary hover:underline">
          {{ t("settings.nav.items.preferences") }}
        </LiveLink>
      </template>
    </SettingsSection>

    <Dialog v-model:open="emailDialogOpen">
      <DialogContent class="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>{{ t("settings.profile.change_email_dialog.title") }}</DialogTitle>
          <DialogDescription>
            {{ t("settings.profile.change_email_dialog.description") }}
          </DialogDescription>
        </DialogHeader>

        <form
          id="profile-email-form"
          class="flex flex-col gap-2"
          @submit.prevent="requestEmailChange"
        >
          <Label for="profile-new-email">{{
            t("settings.profile.change_email_dialog.new_email")
          }}</Label>
          <Input
            id="profile-new-email"
            v-model="newEmail"
            type="email"
            autocomplete="email"
            required
            :aria-invalid="emailError ? true : undefined"
            :aria-describedby="emailError ? 'profile-new-email-error' : undefined"
          />
          <p
            v-if="emailError"
            id="profile-new-email-error"
            class="text-[13px] text-destructive"
            role="alert"
          >
            {{ emailError }}
          </p>
        </form>

        <DialogFooter>
          <Button type="button" variant="outline" @click="emailDialogOpen = false">
            {{ t("settings.profile.change_email_dialog.cancel") }}
          </Button>
          <Button
            type="submit"
            form="profile-email-form"
            :disabled="sendingEmail || newEmail.trim().length === 0"
          >
            {{ t("settings.profile.change_email_dialog.send") }}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  </SettingsPage>
</template>
