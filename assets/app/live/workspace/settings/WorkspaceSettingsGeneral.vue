<script setup lang="ts">
import { ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import LanguagePicker from "@components/language/LanguagePicker.vue";
import type { LanguagePickerOption } from "@components/language/types";
import SaveIndicator from "@components/SaveIndicator.vue";
import {
  SettingsDeleteDialog,
  SettingsPage,
  SettingsRow,
  SettingsSection,
} from "@components/settings";
import { Button } from "@components/ui/button";
import { Input } from "@components/ui/input";
import { Textarea } from "@components/ui/textarea";
import { useLive } from "@shared/composables/useLive";

const {
  workspaceName = "",
  workspaceDescription = "",
  workspaceBannerUrl = "",
  sourceLocale = "",
  languageOptions = [],
  isOwner,
  canEditWorkspace,
  saveStatus = "idle",
} = defineProps<{
  workspaceName?: string;
  workspaceDescription?: string;
  workspaceBannerUrl?: string;
  sourceLocale?: string;
  languageOptions?: LanguagePickerOption[];
  isOwner: boolean;
  canEditWorkspace: boolean;
  saveStatus?: "idle" | "saving" | "saved";
}>();

const { t } = useI18n();
const live = useLive();

const localName = ref(workspaceName);
const localDescription = ref(workspaceDescription);
const localBannerUrl = ref(workspaceBannerUrl);
const localSourceLocale = ref(sourceLocale.toLowerCase());

watch(
  () => workspaceName,
  (value) => {
    localName.value = value;
  },
);
watch(
  () => workspaceDescription,
  (value) => {
    localDescription.value = value;
  },
);
watch(
  () => workspaceBannerUrl,
  (value) => {
    localBannerUrl.value = value;
  },
);
watch(
  () => sourceLocale,
  (value) => {
    localSourceLocale.value = value.toLowerCase();
  },
);

function saveWorkspace(): void {
  if (!canEditWorkspace) return;

  live.pushEvent("save", {
    workspace: {
      name: localName.value,
      description: localDescription.value,
      banner_url: localBannerUrl.value,
      source_locale: localSourceLocale.value,
    },
  });
}

// Text fields save when they lose focus, only if something changed.
function saveName(): void {
  if (localName.value !== workspaceName) saveWorkspace();
}

function saveDescription(): void {
  if (localDescription.value !== workspaceDescription) saveWorkspace();
}

function updateSourceLocale(value: string): void {
  localSourceLocale.value = value;
  saveWorkspace();
}

// Banner upload
function triggerBannerUpload(): void {
  if (!canEditWorkspace) return;

  const input = document.createElement("input");
  input.type = "file";
  input.accept = "image/*";
  input.onchange = (event) => uploadBanner((event.target as HTMLInputElement).files![0]);
  input.click();
}

function uploadBanner(file: File | undefined): void {
  if (!canEditWorkspace || !file) return;

  const reader = new FileReader();
  reader.onload = () => {
    if (!canEditWorkspace) return;

    live.pushEvent("upload_workspace_banner", {
      filename: file.name,
      content_type: file.type,
      data: reader.result,
    });
  };
  reader.readAsDataURL(file);
}

function removeBanner(): void {
  if (!canEditWorkspace) return;

  localBannerUrl.value = "";
  live.pushEvent("remove_workspace_banner", {});
}

// Delete workspace
const showDeleteConfirm = ref(false);

function deleteWorkspace(): void {
  if (!isOwner) {
    showDeleteConfirm.value = false;
    return;
  }

  live.pushEvent("delete", {});
}

watch(
  () => isOwner,
  (owner) => {
    if (!owner) showDeleteConfirm.value = false;
  },
);
</script>

<template>
  <SettingsPage :title="t('settings.workspace.general.page_title')">
    <template #actions>
      <SaveIndicator :status="saveStatus" />
    </template>

    <form id="workspace-settings-form" @submit.prevent="saveWorkspace">
      <SettingsSection
        :title="t('settings.workspace.general.details')"
        :locked="!canEditWorkspace"
        :locked-label="t('settings.workspace.general.owner_only')"
      >
        <SettingsRow
          :label="t('settings.workspace.general.fields.name')"
          control="input"
          html-for="workspace-name"
        >
          <Input
            id="workspace-name"
            v-model="localName"
            required
            :disabled="!canEditWorkspace"
            @blur="saveName"
            @keydown.enter.prevent="saveName"
          />
        </SettingsRow>

        <SettingsRow
          :label="t('settings.workspace.general.fields.description')"
          stacked
          html-for="workspace-description"
        >
          <Textarea
            id="workspace-description"
            v-model="localDescription"
            :disabled="!canEditWorkspace"
            :rows="2"
            :placeholder="t('settings.workspace.general.fields.description_placeholder')"
            @blur="saveDescription"
          />
        </SettingsRow>

        <SettingsRow
          :label="t('settings.workspace.general.fields.banner')"
          :hint="t('settings.workspace.general.fields.banner_hint')"
        >
          <template v-if="localBannerUrl">
            <Button
              id="change-workspace-banner"
              type="button"
              variant="outline"
              size="sm"
              :disabled="!canEditWorkspace"
              @click="triggerBannerUpload"
            >
              {{ t("settings.workspace.general.fields.change") }}
            </Button>
            <Button
              type="button"
              variant="ghost"
              size="sm"
              :disabled="!canEditWorkspace"
              @click="removeBanner"
            >
              {{ t("settings.workspace.general.fields.remove") }}
            </Button>
          </template>
          <Button
            v-else
            id="upload-workspace-banner"
            type="button"
            variant="outline"
            size="sm"
            :disabled="!canEditWorkspace"
            @click="triggerBannerUpload"
          >
            {{ t("settings.workspace.general.fields.upload") }}
          </Button>
        </SettingsRow>

        <div v-if="localBannerUrl" class="px-4 pb-3.5">
          <img
            :src="localBannerUrl"
            :alt="t('settings.workspace.general.fields.banner')"
            class="h-24 w-full rounded-md border border-border object-cover"
          />
        </div>

        <SettingsRow
          :label="t('settings.workspace.general.fields.source_language')"
          :hint="t('settings.workspace.general.fields.source_language_hint')"
        >
          <LanguagePicker
            id="source-locale"
            :model-value="localSourceLocale"
            :options="languageOptions"
            :label="t('settings.workspace.general.fields.source_language')"
            :text="{
              placeholder: t('settings.workspace.general.fields.select_language'),
              searchPlaceholder: t('localization.sidebar.search_languages'),
              emptyLabel: t('localization.sidebar.no_matches'),
            }"
            :appearance="{ triggerClass: 'w-44' }"
            :disabled="!canEditWorkspace"
            @update:model-value="updateSourceLocale"
          />
        </SettingsRow>
      </SettingsSection>
    </form>

    <SettingsSection
      v-if="isOwner"
      :title="t('settings.workspace.danger_zone.title')"
      tone="danger"
    >
      <SettingsRow
        :label="t('settings.workspace.danger_zone.delete_workspace')"
        :hint="t('settings.workspace.danger_zone.delete_description')"
      >
        <Button
          id="delete-workspace-button"
          type="button"
          variant="destructive"
          size="sm"
          @click="showDeleteConfirm = true"
        >
          {{ t("settings.workspace.danger_zone.delete_button") }}
        </Button>
      </SettingsRow>
    </SettingsSection>

    <SettingsDeleteDialog
      v-if="isOwner"
      v-model:open="showDeleteConfirm"
      :title="t('settings.workspace.delete_modal.title')"
      :description="t('settings.workspace.delete_modal.description')"
      :confirmation-value="workspaceName"
      :confirmation-label="t('settings.workspace.delete_modal.type_name')"
      :confirm-text="t('settings.workspace.delete_modal.delete')"
      :cancel-text="t('settings.workspace.delete_modal.cancel')"
      confirm-id="confirm-delete-workspace"
      @confirm="deleteWorkspace"
    />
  </SettingsPage>
</template>
