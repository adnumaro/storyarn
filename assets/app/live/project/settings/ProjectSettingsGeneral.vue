<script setup lang="ts">
import { AlertTriangle, FileUp, Languages, Wrench } from "lucide-vue-next";
import { computed, ref, watch } from "vue";
import ColorPickerPopover from "@components/forms/ColorPickerPopover.vue";
import ConfirmDialog from "@components/ConfirmDialog.vue";
import LanguagePicker from "@components/language/LanguagePicker.vue";
import type { LanguagePickerOption } from "@components/language/types";
import ThemeSelector from "@components/ThemeSelector.vue";
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
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@components/ui/select";
import { Separator } from "@components/ui/separator";
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

interface ProjectTemplatePublication {
  id: number;
  name: string;
  description: string;
  current_version_number?: number | null;
}

interface ProjectTemplatePublicationStatus {
  id: number;
  mode: "new" | "update";
  status: "queued" | "running" | "retrying" | "published" | "failed";
  template_id?: number | null;
  template_version_id?: number | null;
  name: string;
  description: string;
  version_notes?: string;
  error_message?: string | null;
  inserted_at?: string | null;
  completed_at?: string | null;
}

const {
  projectDetails = { name: "", description: "", type: "", subtype: "", typeOther: "" },
  projectMetricsOptions = { project_types: [], project_subtypes: {} },
  sourceLanguage = null,
  sourceLanguageOptions = [],
  themePrimary = "#00D4CC",
  themeAccent = "#E8922F",
  hasCustomTheme = false,
  projectTemplates = [],
  projectTemplatePublications = [],
} = defineProps<{
  projectDetails?: ProjectDetails;
  projectMetricsOptions?: ProjectMetricsOptions;
  sourceLanguage?: SourceLanguage | null;
  sourceLanguageOptions?: LanguagePickerOption[];
  themePrimary?: string;
  themeAccent?: string;
  hasCustomTheme?: boolean;
  projectTemplates?: ProjectTemplatePublication[];
  projectTemplatePublications?: ProjectTemplatePublicationStatus[];
}>();

const live = useLive();
const sourceChangeDialogOpen = ref(false);
const pendingSourceLanguage = ref<LanguagePickerOption | null>(null);

function requestSourceLanguage(option: LanguagePickerOption): void {
  pendingSourceLanguage.value = option;
  sourceChangeDialogOpen.value = true;
}

function confirmSourceLanguage(): void {
  if (pendingSourceLanguage.value) {
    live.pushEvent("change_source_language", {
      locale_code: pendingSourceLanguage.value.value,
      reset_translations: true,
    });
  }

  pendingSourceLanguage.value = null;
}

// Project Details
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

const projectSubtypeOptions = computed(() => {
  return projectMetricsOptions.project_subtypes[projectTypeLocal.value] || [];
});
const requiresSubtype = computed(() => projectSubtypeOptions.value.length > 0);
const requiresOtherType = computed(() => projectTypeLocal.value === "other");
const canSaveProject = computed(() => {
  const hasName = projectNameLocal.value.trim().length > 0;
  const hasType = projectTypeLocal.value.length > 0;
  const hasSubtype = !requiresSubtype.value || projectSubtypeLocal.value.length > 0;
  const hasOtherType = !requiresOtherType.value || projectTypeOtherLocal.value.trim().length > 0;

  return hasName && hasType && hasSubtype && hasOtherType;
});

function updateProjectType(value: string | string[]) {
  projectTypeLocal.value = Array.isArray(value) ? value[0] || "" : value;
  projectSubtypeLocal.value = "";
  projectTypeOtherLocal.value = "";
}

function updateProjectSubtype(value: string | string[]) {
  projectSubtypeLocal.value = Array.isArray(value) ? value[0] || "" : value;
}

function projectMetricLabel(group: string, value: string) {
  return `workspace.new_project.fields.${group}.options.${value}`;
}

function saveProject() {
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

function validateProject() {
  live.pushEvent("validate_project", {
    project: {
      name: projectNameLocal.value,
      description: projectDescLocal.value,
    },
  });
}

// Templates
const showTemplateDialog = ref(false);
const templateMode = ref<"new" | "update">("new");
const selectedTemplateId = ref<number | null>(null);
const templateName = ref(projectDetails.name);
const templateDescription = ref(projectDetails.description);
const templateVersionNotes = ref("");
const activePublicationStatuses = new Set(["queued", "running", "retrying"]);

const selectedTemplate = computed(() => {
  return projectTemplates.find((template) => template.id === selectedTemplateId.value) || null;
});

const recentTemplatePublications = computed(() => projectTemplatePublications.slice(0, 5));

const hasActiveTemplatePublication = computed(() => {
  return projectTemplatePublications.some((publication) =>
    activePublicationStatuses.has(publication.status),
  );
});

const activePublicationForSelection = computed(() => {
  return projectTemplatePublications.some((publication) => {
    if (!activePublicationStatuses.has(publication.status)) return false;

    if (templateMode.value === "new") {
      return publication.mode === "new";
    }

    return publication.template_id === selectedTemplateId.value;
  });
});

const canPublishTemplate = computed(() => {
  if (templateName.value.trim().length === 0) return false;
  if (activePublicationForSelection.value) return false;
  if (templateMode.value === "update") return !!selectedTemplate.value;

  return true;
});

function openTemplateDialog() {
  const [firstTemplate] = projectTemplates;
  templateMode.value = firstTemplate ? "update" : "new";
  syncTemplateFields(firstTemplate || null);
  showTemplateDialog.value = true;
}

function updateTemplateMode(mode: "new" | "update") {
  templateMode.value = mode;
  syncTemplateFields(mode === "update" ? projectTemplates[0] || null : null);
}

function updateSelectedTemplate(value: string | string[]) {
  const rawValue = Array.isArray(value) ? value[0] || "" : value;
  const id = Number(rawValue);
  const template = projectTemplates.find((candidate) => candidate.id === id) || null;
  syncTemplateFields(template);
}

function syncTemplateFields(template: ProjectTemplatePublication | null) {
  selectedTemplateId.value = template?.id || null;
  templateName.value = template?.name || projectDetails.name;
  templateDescription.value = template?.description || projectDetails.description;
  templateVersionNotes.value = "";
}

function publishTemplate() {
  if (!canPublishTemplate.value) return;

  live.pushEvent("publish_template", {
    template: {
      mode: templateMode.value,
      template_id: selectedTemplateId.value,
      name: templateName.value.trim(),
      description: templateDescription.value,
      version_notes: templateVersionNotes.value,
    },
  });

  showTemplateDialog.value = false;
}

function publicationStatusLabel(status: ProjectTemplatePublicationStatus["status"]) {
  return `project_settings.general.template_publication_status.${status}`;
}

function publicationDescription(publication: ProjectTemplatePublicationStatus) {
  if (publication.status === "failed" && publication.error_message) {
    return publication.error_message;
  }

  return publication.mode === "new"
    ? "project_settings.general.template_publication_new"
    : "project_settings.general.template_publication_update";
}

function publicationStatusClass(status: ProjectTemplatePublicationStatus["status"]) {
  if (status === "published") return "border-emerald-500/30 bg-emerald-500/10 text-emerald-700";
  if (status === "failed") return "border-destructive/30 bg-destructive/10 text-destructive";
  if (status === "retrying") return "border-amber-500/30 bg-amber-500/10 text-amber-700";
  return "border-sky-500/30 bg-sky-500/10 text-sky-700";
}

// Theme
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

function onPrimaryChange(hex: string) {
  localPrimary.value = hex;
  live.pushEvent("update_theme_primary", { color: hex });
}

function onAccentChange(hex: string) {
  localAccent.value = hex;
  live.pushEvent("update_theme_accent", { color: hex });
}

function saveTheme() {
  live.pushEvent("save_theme", {});
}

function resetTheme() {
  live.pushEvent("reset_theme", {});
}

// Repair
const showRepairConfirm = ref(false);

function confirmRepair() {
  showRepairConfirm.value = false;
  live.pushEvent("repair_variable_references", {});
}

// Delete project
const showDeleteConfirm = ref(false);

function confirmDeleteProject() {
  showDeleteConfirm.value = false;
  live.pushEvent("delete_project", {});
}
</script>

<template>
  <div class="space-y-8">
    <!-- Project Details -->
    <section>
      <form @submit.prevent="saveProject" class="space-y-4">
        <div class="space-y-1.5">
          <Label for="project-name">{{ $t("project_settings.general.project_name") }}</Label>
          <Input id="project-name" v-model="projectNameLocal" required @blur="validateProject" />
        </div>

        <div class="grid gap-3 sm:grid-cols-2">
          <div class="space-y-1.5">
            <Label for="project-type">{{ $t("project_settings.general.project_type") }}</Label>
            <Select
              :model-value="projectTypeLocal"
              required
              @update:model-value="updateProjectType"
            >
              <SelectTrigger id="project-type" class="w-full">
                <SelectValue
                  :placeholder="$t('project_settings.general.project_type_placeholder')"
                />
              </SelectTrigger>
              <SelectContent>
                <SelectItem
                  v-for="option in projectMetricsOptions.project_types"
                  :key="option"
                  :value="option"
                >
                  {{ $t(projectMetricLabel("project_type", option)) }}
                </SelectItem>
              </SelectContent>
            </Select>
          </div>

          <div v-if="requiresSubtype" class="space-y-1.5">
            <Label for="project-subtype">{{
              $t("project_settings.general.project_subtype")
            }}</Label>
            <Select
              :model-value="projectSubtypeLocal"
              required
              @update:model-value="updateProjectSubtype"
            >
              <SelectTrigger id="project-subtype" class="w-full">
                <SelectValue
                  :placeholder="$t('project_settings.general.project_subtype_placeholder')"
                />
              </SelectTrigger>
              <SelectContent>
                <SelectItem v-for="option in projectSubtypeOptions" :key="option" :value="option">
                  {{ $t(projectMetricLabel(`project_subtype.${projectTypeLocal}`, option)) }}
                </SelectItem>
              </SelectContent>
            </Select>
          </div>

          <div v-if="requiresOtherType" class="space-y-1.5">
            <Label for="project-type-other">{{
              $t("project_settings.general.project_type_other")
            }}</Label>
            <Input
              id="project-type-other"
              v-model="projectTypeOtherLocal"
              maxlength="120"
              required
              :placeholder="$t('project_settings.general.project_type_other_placeholder')"
            />
          </div>
        </div>

        <div class="space-y-1.5">
          <Label for="project-description">{{ $t("project_settings.general.description") }}</Label>
          <Textarea
            id="project-description"
            v-model="projectDescLocal"
            :rows="3"
            @blur="validateProject"
          />
        </div>
        <div class="flex justify-end gap-3 pt-1">
          <Button type="submit" :disabled="!canSaveProject">
            {{ $t("project_settings.general.save_changes") }}
          </Button>
        </div>
      </form>
    </section>

    <Separator />

    <!-- Templates -->
    <section>
      <div
        class="flex flex-col gap-4 rounded-lg border border-border bg-muted/30 p-4 sm:flex-row sm:items-center sm:justify-between"
      >
        <div class="min-w-0">
          <h3 class="text-lg font-semibold mb-1">{{ $t("project_settings.general.templates") }}</h3>
          <p class="text-sm text-muted-foreground">
            {{ $t("project_settings.general.templates_description") }}
          </p>

          <div v-if="recentTemplatePublications.length > 0" class="mt-3 space-y-2">
            <div
              v-for="publication in recentTemplatePublications"
              :key="publication.id"
              class="flex flex-wrap items-center gap-2 text-xs text-muted-foreground"
              :data-testid="`template-publication-${publication.id}`"
            >
              <span
                class="inline-flex items-center rounded-full border px-2 py-0.5 font-medium"
                :class="publicationStatusClass(publication.status)"
              >
                {{ $t(publicationStatusLabel(publication.status)) }}
              </span>
              <span class="truncate font-medium text-foreground">{{ publication.name }}</span>
              <span>{{ $t(publicationDescription(publication)) }}</span>
            </div>
          </div>
        </div>
        <Button
          type="button"
          class="shrink-0"
          data-testid="open-template-publication-dialog"
          :disabled="hasActiveTemplatePublication"
          @click="openTemplateDialog"
        >
          <FileUp class="size-4 mr-1.5" />
          {{
            hasActiveTemplatePublication
              ? $t("project_settings.general.template_publication_active")
              : $t("project_settings.general.publish_template")
          }}
        </Button>
      </div>
    </section>

    <Separator />

    <!-- Source Language -->
    <section class="space-y-4" v-if="sourceLanguage">
      <div>
        <h3 class="text-lg font-semibold mb-1">
          {{ $t("project_settings.general.source_language") }}
        </h3>
        <p class="text-sm text-muted-foreground">
          {{ $t("project_settings.general.source_language_description") }}
        </p>
      </div>

      <div class="max-w-xl rounded-lg border border-border bg-muted/30 p-4 space-y-4">
        <LanguagePicker
          id="project-source-language-picker"
          :model-value="sourceLanguage.value"
          :selected-option="sourceLanguage"
          :options="sourceLanguageOptions"
          :label="$t('project_settings.general.source_language')"
          :text="{
            searchPlaceholder: $t('localization.sidebar.search_languages'),
            emptyLabel: $t('localization.sidebar.no_matches'),
          }"
          :appearance="{ triggerClass: 'w-full' }"
          @select="requestSourceLanguage"
        />

        <p class="text-xs text-muted-foreground">
          {{ $t("project_settings.general.source_language_hint") }}
        </p>
      </div>
    </section>

    <Separator />

    <!-- Appearance -->
    <section>
      <h3 class="text-lg font-semibold mb-4">{{ $t("project_settings.general.appearance") }}</h3>
      <ThemeSelector
        :labels="{
          system: $t('project_settings.general.theme_system'),
          light: $t('project_settings.general.theme_light'),
          dark: $t('project_settings.general.theme_dark'),
        }"
      />
    </section>

    <Separator />

    <!-- Theme -->
    <section>
      <h3 class="text-lg font-semibold mb-4">{{ $t("project_settings.general.project_theme") }}</h3>
      <div class="rounded-lg border border-border bg-muted/30 p-4">
        <div class="flex gap-8 items-start">
          <div>
            <Label class="mb-2 block">{{ $t("project_settings.general.primary") }}</Label>
            <div class="flex items-center gap-3">
              <ColorPickerPopover :color="localPrimary" @update:color="onPrimaryChange" />
              <code class="text-xs text-muted-foreground">{{ localPrimary }}</code>
            </div>
          </div>
          <div>
            <Label class="mb-2 block">{{ $t("project_settings.general.accent") }}</Label>
            <div class="flex items-center gap-3">
              <ColorPickerPopover :color="localAccent" @update:color="onAccentChange" />
              <code class="text-xs text-muted-foreground">{{ localAccent }}</code>
            </div>
          </div>
        </div>
        <div class="flex justify-end gap-3 pt-4">
          <Button v-if="hasCustomTheme" variant="outline" @click="resetTheme">
            {{ $t("project_settings.general.reset_theme") }}
          </Button>
          <Button @click="saveTheme">{{ $t("project_settings.general.apply_theme") }}</Button>
        </div>
      </div>
    </section>

    <Separator />

    <!-- Maintenance -->
    <section>
      <h3 class="text-lg font-semibold mb-4">{{ $t("project_settings.general.maintenance") }}</h3>
      <div class="rounded-lg border border-border bg-muted/30 p-4">
        <p class="text-sm text-muted-foreground mb-3">
          {{ $t("project_settings.general.repair_description") }}
        </p>
        <div class="flex justify-end gap-3">
          <Button @click="showRepairConfirm = true">
            <Wrench class="size-4 mr-1.5" />
            {{ $t("project_settings.general.repair_button") }}
          </Button>
        </div>
      </div>
    </section>

    <Separator />

    <!-- Danger Zone -->
    <section>
      <h3 class="text-lg font-semibold mb-4 text-destructive">
        {{ $t("project_settings.general.danger_zone") }}
      </h3>
      <div class="border border-destructive/30 rounded-lg p-4">
        <p class="text-sm text-muted-foreground mb-4">
          {{ $t("project_settings.general.delete_description") }}
        </p>
        <div class="flex justify-end gap-3">
          <Button variant="destructive" @click="showDeleteConfirm = true">{{
            $t("project_settings.general.delete_button")
          }}</Button>
        </div>
      </div>
    </section>

    <!-- Template Publish Dialog -->
    <Dialog v-model:open="showTemplateDialog">
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{{ $t("project_settings.general.template_dialog_title") }}</DialogTitle>
          <DialogDescription>
            {{ $t("project_settings.general.template_dialog_description") }}
          </DialogDescription>
        </DialogHeader>

        <div class="space-y-4">
          <div class="grid grid-cols-2 gap-2 rounded-lg border border-border bg-muted/30 p-1">
            <button
              type="button"
              data-testid="template-mode-new"
              :class="[
                'min-h-10 rounded-md px-3 text-sm font-medium transition',
                templateMode === 'new'
                  ? 'bg-background text-foreground shadow-sm'
                  : 'text-muted-foreground hover:text-foreground',
              ]"
              @click="updateTemplateMode('new')"
            >
              {{ $t("project_settings.general.template_new") }}
            </button>
            <button
              type="button"
              data-testid="template-mode-update"
              :disabled="projectTemplates.length === 0"
              :class="[
                'min-h-10 rounded-md px-3 text-sm font-medium transition disabled:opacity-40',
                templateMode === 'update'
                  ? 'bg-background text-foreground shadow-sm'
                  : 'text-muted-foreground hover:text-foreground',
              ]"
              @click="updateTemplateMode('update')"
            >
              {{ $t("project_settings.general.template_update") }}
            </button>
          </div>

          <div v-if="templateMode === 'update'" class="space-y-1.5">
            <Label for="template-publication-select">
              {{ $t("project_settings.general.template_existing") }}
            </Label>
            <Select
              :model-value="selectedTemplateId ? String(selectedTemplateId) : ''"
              @update:model-value="updateSelectedTemplate"
            >
              <SelectTrigger id="template-publication-select" class="w-full">
                <SelectValue
                  :placeholder="$t('project_settings.general.template_existing_placeholder')"
                />
              </SelectTrigger>
              <SelectContent>
                <SelectItem
                  v-for="template in projectTemplates"
                  :key="template.id"
                  :value="String(template.id)"
                >
                  {{
                    $t("project_settings.general.template_existing_option", {
                      name: template.name,
                      version: template.current_version_number || "-",
                    })
                  }}
                </SelectItem>
              </SelectContent>
            </Select>
          </div>

          <div class="space-y-1.5">
            <Label for="template-name">{{ $t("project_settings.general.template_name") }}</Label>
            <Input id="template-name" v-model="templateName" maxlength="100" />
          </div>

          <div class="space-y-1.5">
            <Label for="template-description">{{
              $t("project_settings.general.template_description")
            }}</Label>
            <Textarea id="template-description" v-model="templateDescription" :rows="3" />
          </div>

          <div class="space-y-1.5">
            <Label for="template-version-notes">{{
              $t("project_settings.general.template_version_notes")
            }}</Label>
            <Textarea
              id="template-version-notes"
              v-model="templateVersionNotes"
              :rows="3"
              maxlength="2000"
            />
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" @click="showTemplateDialog = false">
            {{ $t("project_settings.general.cancel") }}
          </Button>
          <Button
            data-testid="publish-template-submit"
            :disabled="!canPublishTemplate"
            @click="publishTemplate"
          >
            {{
              activePublicationForSelection
                ? $t("project_settings.general.template_publication_active")
                : $t("project_settings.general.publish_template")
            }}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>

    <!-- Repair Confirm Dialog -->
    <Dialog v-model:open="showRepairConfirm">
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{{ $t("project_settings.general.repair_confirm_title") }}</DialogTitle>
          <DialogDescription>
            {{ $t("project_settings.general.repair_confirm_description") }}
          </DialogDescription>
        </DialogHeader>
        <DialogFooter>
          <Button variant="outline" @click="showRepairConfirm = false">{{
            $t("project_settings.general.cancel")
          }}</Button>
          <Button @click="confirmRepair">{{ $t("project_settings.general.continue") }}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>

    <ConfirmDialog
      v-model:open="sourceChangeDialogOpen"
      :title="$t('localization.sidebar.source_change_confirm_title')"
      :description="
        $t('localization.sidebar.source_change_confirm_description', {
          name: pendingSourceLanguage?.label ?? '',
        })
      "
      :confirm-text="$t('localization.sidebar.source_change_confirm_button')"
      variant="destructive"
      :icon="Languages"
      @confirm="confirmSourceLanguage"
    />

    <!-- Delete Confirm Dialog -->
    <Dialog v-model:open="showDeleteConfirm">
      <DialogContent>
        <DialogHeader>
          <div class="flex items-center gap-2">
            <AlertTriangle class="size-5 text-destructive" />
            <DialogTitle>{{ $t("project_settings.general.delete_confirm_title") }}</DialogTitle>
          </div>
          <DialogDescription>{{
            $t("project_settings.general.delete_confirm_description")
          }}</DialogDescription>
        </DialogHeader>
        <DialogFooter>
          <Button variant="outline" @click="showDeleteConfirm = false">{{
            $t("project_settings.general.cancel")
          }}</Button>
          <Button variant="destructive" @click="confirmDeleteProject">{{
            $t("project_settings.general.delete")
          }}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  </div>
</template>
