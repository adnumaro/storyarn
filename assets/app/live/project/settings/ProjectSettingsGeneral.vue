<script setup lang="ts">
import { Languages } from "@lucide/vue";
import { computed, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import ColorPickerPopover from "@components/forms/ColorPickerPopover.vue";
import ConfirmDialog from "@components/ConfirmDialog.vue";
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
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@components/ui/dialog";
import { Input } from "@components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@components/ui/select";
import { Textarea } from "@components/ui/textarea";
import { useLive } from "@shared/composables/useLive";

interface SourceLanguage extends LanguagePickerOption {
  localeCode: string;
}

interface ProjectMetricsOptions {
  project_types: string[];
  project_subtypes: Record<string, string[]>;
}

interface ProjectDetails {
  name: string;
  description: string;
  type: string;
  subtype: string;
  typeOther: string;
}

const {
  projectDetails = { name: "", description: "", type: "", subtype: "", typeOther: "" },
  projectMetricsOptions = { project_types: [], project_subtypes: {} },
  sourceLanguage = null,
  sourceLanguageOptions = [],
  themePrimary = "#00D4CC",
  themeAccent = "#E8922F",
  hasCustomTheme = false,
  canManageProject,
  saveStatus = "idle",
} = defineProps<{
  projectDetails?: ProjectDetails;
  projectMetricsOptions?: ProjectMetricsOptions;
  sourceLanguage?: SourceLanguage | null;
  sourceLanguageOptions?: LanguagePickerOption[];
  themePrimary?: string;
  themeAccent?: string;
  hasCustomTheme?: boolean;
  canManageProject: boolean;
  saveStatus?: "idle" | "saving" | "saved";
}>();

const live = useLive();
const { t } = useI18n();

// ---------------------------------------------------------------------------
// Details: saved on blur or on select change, like the profile page.
// ---------------------------------------------------------------------------
const projectNameLocal = ref(projectDetails.name);
const projectDescLocal = ref(projectDetails.description);
const projectTypeLocal = ref(projectDetails.type);
const projectSubtypeLocal = ref(projectDetails.subtype);
const projectTypeOtherLocal = ref(projectDetails.typeOther);

watch(
  () => projectDetails,
  (v) => {
    projectNameLocal.value = v.name;
    projectDescLocal.value = v.description;
    projectTypeLocal.value = v.type;
    projectSubtypeLocal.value = v.subtype;
    projectTypeOtherLocal.value = v.typeOther;
  },
);

const projectSubtypeOptions = computed(
  () => projectMetricsOptions.project_subtypes[projectTypeLocal.value] || [],
);
const requiresSubtype = computed(() => projectSubtypeOptions.value.length > 0);
const requiresOtherType = computed(() => projectTypeLocal.value === "other");

const detailsComplete = computed(() => {
  const hasName = projectNameLocal.value.trim().length > 0;
  const hasType = projectTypeLocal.value.length > 0;
  const hasSubtype = !requiresSubtype.value || projectSubtypeLocal.value.length > 0;
  const hasOtherType = !requiresOtherType.value || projectTypeOtherLocal.value.trim().length > 0;

  return hasName && hasType && hasSubtype && hasOtherType;
});

const detailsDirty = computed(
  () =>
    projectNameLocal.value !== projectDetails.name ||
    projectDescLocal.value !== projectDetails.description ||
    projectTypeLocal.value !== projectDetails.type ||
    projectSubtypeLocal.value !== projectDetails.subtype ||
    projectTypeOtherLocal.value !== projectDetails.typeOther,
);

function saveProject(): void {
  if (!canManageProject || !detailsComplete.value || !detailsDirty.value) return;

  live.pushEvent("update_project", {
    project: {
      name: projectNameLocal.value,
      description: projectDescLocal.value,
      project_type: projectTypeLocal.value,
      project_subtype: projectSubtypeLocal.value,
      project_type_other: projectTypeOtherLocal.value,
    },
  });
}

function updateProjectType(value: string | string[]): void {
  projectTypeLocal.value = Array.isArray(value) ? value[0] || "" : value;
  projectSubtypeLocal.value = "";
  projectTypeOtherLocal.value = "";
  saveProject();
}

function updateProjectSubtype(value: string | string[]): void {
  projectSubtypeLocal.value = Array.isArray(value) ? value[0] || "" : value;
  saveProject();
}

function projectMetricLabel(group: string, value: string): string {
  return t(`workspace.new_project.fields.${group}.options.${value}`);
}

// ---------------------------------------------------------------------------
// Source language: confirmed because it resets translations.
// ---------------------------------------------------------------------------
const sourceChangeDialogOpen = ref(false);
const pendingSourceLanguage = ref<LanguagePickerOption | null>(null);

function requestSourceLanguage(option: LanguagePickerOption): void {
  if (!canManageProject) return;

  pendingSourceLanguage.value = option;
  sourceChangeDialogOpen.value = true;
}

function confirmSourceLanguage(): void {
  if (!canManageProject) return;

  if (pendingSourceLanguage.value) {
    live.pushEvent("change_source_language", {
      locale_code: pendingSourceLanguage.value.value,
      reset_translations: true,
    });
  }

  pendingSourceLanguage.value = null;
}

// ---------------------------------------------------------------------------
// Theme colors
// ---------------------------------------------------------------------------
const localPrimary = ref(themePrimary);
const localAccent = ref(themeAccent);

watch(
  () => themePrimary,
  (v) => {
    localPrimary.value = v;
  },
);
watch(
  () => themeAccent,
  (v) => {
    localAccent.value = v;
  },
);

function onPrimaryChange(hex: string): void {
  if (!canManageProject) return;

  localPrimary.value = hex;
  live.pushEvent("update_theme_primary", { color: hex });
}

function onAccentChange(hex: string): void {
  if (!canManageProject) return;

  localAccent.value = hex;
  live.pushEvent("update_theme_accent", { color: hex });
}

function saveTheme(): void {
  if (!canManageProject) return;
  live.pushEvent("save_theme", {});
}

function resetTheme(): void {
  if (!canManageProject) return;
  live.pushEvent("reset_theme", {});
}

// ---------------------------------------------------------------------------
// Maintenance and danger zone
// ---------------------------------------------------------------------------
const showRepairConfirm = ref(false);

function confirmRepair(): void {
  if (!canManageProject) return;

  showRepairConfirm.value = false;
  live.pushEvent("repair_variable_references", {});
}

const showDeleteConfirm = ref(false);

function confirmDeleteProject(): void {
  if (!canManageProject) return;

  showDeleteConfirm.value = false;
  live.pushEvent("delete_project", {});
}

watch(
  () => canManageProject,
  (canManage) => {
    if (canManage) return;

    sourceChangeDialogOpen.value = false;
    pendingSourceLanguage.value = null;
    showRepairConfirm.value = false;
    showDeleteConfirm.value = false;
  },
);

const lockedLabel = computed(() =>
  canManageProject ? null : t("project_settings.general.owner_only_label"),
);
</script>

<template>
  <SettingsPage :title="t('project_settings.general.page_title')">
    <template #actions>
      <SaveIndicator :status="saveStatus" />
    </template>

    <div
      v-if="!canManageProject"
      data-testid="project-owner-controls-unavailable"
      role="status"
      class="rounded-lg border border-border bg-muted/40 px-4 py-3 text-sm text-muted-foreground"
    >
      {{ t("project_settings.general.owner_controls_unavailable") }}
    </div>

    <SettingsSection
      :title="t('project_settings.general.details')"
      :locked="!canManageProject"
      :locked-label="lockedLabel"
    >
      <SettingsRow
        :label="t('project_settings.general.project_name')"
        html-for="project-name"
        control="input"
      >
        <Input
          id="project-name"
          v-model="projectNameLocal"
          required
          maxlength="120"
          :disabled="!canManageProject"
          @blur="saveProject"
        />
      </SettingsRow>

      <SettingsRow
        :label="t('project_settings.general.project_type')"
        :hint="t('project_settings.general.type_hint')"
      >
        <div class="flex w-full flex-col gap-2 sm:w-auto sm:flex-row">
          <Select
            :model-value="projectTypeLocal"
            :disabled="!canManageProject"
            @update:model-value="updateProjectType"
          >
            <SelectTrigger id="project-type" class="w-full sm:w-[168px]">
              <SelectValue :placeholder="t('project_settings.general.project_type_placeholder')" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem
                v-for="option in projectMetricsOptions.project_types"
                :key="option"
                :value="option"
              >
                {{ projectMetricLabel("project_type", option) }}
              </SelectItem>
            </SelectContent>
          </Select>

          <Select
            v-if="requiresSubtype"
            :model-value="projectSubtypeLocal"
            :disabled="!canManageProject"
            @update:model-value="updateProjectSubtype"
          >
            <SelectTrigger id="project-subtype" class="w-full sm:w-[168px]">
              <SelectValue
                :placeholder="t('project_settings.general.project_subtype_placeholder')"
              />
            </SelectTrigger>
            <SelectContent>
              <SelectItem v-for="option in projectSubtypeOptions" :key="option" :value="option">
                {{ projectMetricLabel(`project_subtype.${projectTypeLocal}`, option) }}
              </SelectItem>
            </SelectContent>
          </Select>

          <Input
            v-if="requiresOtherType"
            id="project-type-other"
            v-model="projectTypeOtherLocal"
            class="w-full sm:w-[168px]"
            maxlength="120"
            required
            :disabled="!canManageProject"
            :placeholder="t('project_settings.general.project_type_other_placeholder')"
            :aria-label="t('project_settings.general.project_type_other')"
            @blur="saveProject"
          />
        </div>
      </SettingsRow>

      <SettingsRow
        :label="t('project_settings.general.description')"
        :hint="t('project_settings.general.description_hint')"
        html-for="project-description"
        stacked
      >
        <Textarea
          id="project-description"
          v-model="projectDescLocal"
          :rows="3"
          :disabled="!canManageProject"
          @blur="saveProject"
        />
      </SettingsRow>
    </SettingsSection>

    <SettingsSection
      v-if="sourceLanguage"
      :title="t('project_settings.general.language')"
      :locked="!canManageProject"
      :locked-label="lockedLabel"
    >
      <SettingsRow
        :label="t('project_settings.general.source_language')"
        :hint="t('project_settings.general.source_language_row_hint')"
      >
        <LanguagePicker
          id="project-source-language-picker"
          :model-value="sourceLanguage.value"
          :selected-option="sourceLanguage"
          :options="sourceLanguageOptions"
          :label="t('project_settings.general.source_language')"
          :text="{
            searchPlaceholder: t('localization.sidebar.search_languages'),
            emptyLabel: t('localization.sidebar.no_matches'),
          }"
          :appearance="{ triggerClass: 'w-[220px] max-w-full' }"
          @select="requestSourceLanguage"
        />
      </SettingsRow>
    </SettingsSection>

    <SettingsSection
      :title="t('project_settings.general.theme_colors')"
      :hint="t('project_settings.general.theme_colors_hint')"
      :locked="!canManageProject"
      :locked-label="lockedLabel"
    >
      <SettingsRow
        :label="t('project_settings.general.primary')"
        :hint="t('project_settings.general.primary_hint')"
      >
        <code class="text-xs text-muted-foreground">{{ localPrimary }}</code>
        <ColorPickerPopover :color="localPrimary" @update:color="onPrimaryChange" />
      </SettingsRow>
      <SettingsRow
        :label="t('project_settings.general.accent')"
        :hint="t('project_settings.general.accent_hint')"
      >
        <code class="text-xs text-muted-foreground">{{ localAccent }}</code>
        <ColorPickerPopover :color="localAccent" @update:color="onAccentChange" />
      </SettingsRow>

      <SettingsRow
        :label="t('project_settings.general.theme_apply_row')"
        :hint="t('project_settings.general.theme_apply_hint')"
      >
        <Button v-if="hasCustomTheme" variant="ghost" size="sm" @click="resetTheme">
          {{ t("project_settings.general.reset_theme") }}
        </Button>
        <Button size="sm" @click="saveTheme">
          {{ t("project_settings.general.apply_theme") }}
        </Button>
      </SettingsRow>
    </SettingsSection>

    <SettingsSection
      :title="t('project_settings.general.maintenance')"
      :locked="!canManageProject"
      :locked-label="lockedLabel"
    >
      <SettingsRow
        :label="t('project_settings.general.repair_button')"
        :hint="t('project_settings.general.repair_description')"
      >
        <Button
          variant="outline"
          size="sm"
          data-testid="open-project-repair-dialog"
          @click="showRepairConfirm = true"
        >
          {{ t("project_settings.general.repair_action") }}
        </Button>
      </SettingsRow>
    </SettingsSection>

    <SettingsSection
      :title="t('project_settings.general.danger_zone')"
      tone="danger"
      :locked="!canManageProject"
      :locked-label="lockedLabel"
    >
      <SettingsRow
        :label="t('project_settings.general.delete_row')"
        :hint="t('project_settings.general.delete_hint')"
      >
        <Button
          variant="destructive"
          size="sm"
          data-testid="open-project-delete-dialog"
          @click="showDeleteConfirm = true"
        >
          {{ t("project_settings.general.delete_button") }}
        </Button>
      </SettingsRow>
    </SettingsSection>

    <Dialog
      v-if="canManageProject"
      v-model:open="showRepairConfirm"
      data-testid="project-repair-confirm-dialog"
    >
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{{ t("project_settings.general.repair_confirm_title") }}</DialogTitle>
          <DialogDescription>
            {{ t("project_settings.general.repair_confirm_description") }}
          </DialogDescription>
        </DialogHeader>
        <DialogFooter>
          <Button variant="outline" @click="showRepairConfirm = false">
            {{ t("project_settings.general.cancel") }}
          </Button>
          <Button @click="confirmRepair">{{ t("project_settings.general.continue") }}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>

    <ConfirmDialog
      v-if="canManageProject"
      v-model:open="sourceChangeDialogOpen"
      :title="t('localization.sidebar.source_change_confirm_title')"
      :description="
        t('localization.sidebar.source_change_confirm_description', {
          name: pendingSourceLanguage?.label ?? '',
        })
      "
      :confirm-text="t('localization.sidebar.source_change_confirm_button')"
      variant="destructive"
      :icon="Languages"
      @confirm="confirmSourceLanguage"
    />

    <SettingsDeleteDialog
      v-if="canManageProject"
      v-model:open="showDeleteConfirm"
      data-testid="project-delete-confirm-dialog"
      :title="t('project_settings.general.delete_confirm_title')"
      :description="t('project_settings.general.delete_confirm_description')"
      :confirmation-value="projectDetails.name"
      :confirmation-label="t('project_settings.general.delete_type_name')"
      :confirm-text="t('project_settings.general.delete_button')"
      :cancel-text="t('project_settings.general.cancel')"
      confirm-id="confirm-delete-project"
      @confirm="confirmDeleteProject"
    />
  </SettingsPage>
</template>
