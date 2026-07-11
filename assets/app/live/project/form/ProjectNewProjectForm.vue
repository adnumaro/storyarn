<script setup lang="ts">
import { useLiveForm, type Form, type FormField } from "live_vue";
import { computed } from "vue";
import { Button } from "@components/ui/button";
import { Input } from "@components/ui/input";
import { Label } from "@components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@components/ui/select";
import { Textarea } from "@components/ui/textarea";

interface ProjectFormValues {
  name: string;
  description: string;
  project_type: string;
  project_subtype: string;
  project_type_other: string;
}

interface ProjectMetricsOptions {
  project_types: string[];
  project_subtypes: Record<string, string[]>;
}

type ProjectForm = Form<ProjectFormValues>;

const {
  form: formProp,
  title = null,
  submitLabel = null,
  metricsOptions = { project_types: [], project_subtypes: {} },
} = defineProps<{
  form: ProjectForm;
  title?: string | null;
  submitLabel?: string | null;
  metricsOptions?: ProjectMetricsOptions;
}>();

const emit = defineEmits<{
  cancel: [];
}>();

const form = useLiveForm(() => formProp, {
  submitEvent: "create_project",
});

const name = form.field("name");
const description = form.field("description");
const projectType = form.field("project_type");
const projectSubtype = form.field("project_subtype");
const projectTypeOther = form.field("project_type_other");

const selectedProjectType = computed(() => String(projectType.value.value || ""));
const availableSubtypes = computed(() => {
  return metricsOptions.project_subtypes[selectedProjectType.value] || [];
});

const requiresSubtype = computed(() => availableSubtypes.value.length > 0);
const requiresOtherType = computed(() => selectedProjectType.value === "other");
const nameValue = computed(() => String(name.value.value || ""));
const descriptionValue = computed(() => String(description.value.value || ""));
const subtypeValue = computed(() => String(projectSubtype.value.value || ""));
const projectTypeOtherValue = computed(() => String(projectTypeOther.value.value || ""));
const isNameLocallyInvalid = computed(() => {
  const value = nameValue.value.trim();
  return value.length === 0 || value.length > 100;
});
const isDescriptionLocallyInvalid = computed(() => descriptionValue.value.length > 1000);
const isProjectTypeLocallyInvalid = computed(() => selectedProjectType.value.length === 0);
const isProjectSubtypeLocallyInvalid = computed(() => {
  return requiresSubtype.value && subtypeValue.value.length === 0;
});
const isProjectTypeOtherLocallyInvalid = computed(() => {
  if (!requiresOtherType.value) return false;

  const value = projectTypeOtherValue.value.trim();
  return value.length === 0 || value.length > 120;
});
const canSubmit = computed(() => {
  return (
    !isNameLocallyInvalid.value &&
    !isDescriptionLocallyInvalid.value &&
    !isProjectTypeLocallyInvalid.value &&
    !isProjectSubtypeLocallyInvalid.value &&
    !isProjectTypeOtherLocallyInvalid.value
  );
});

// Server errors are returned on submit. Local guards keep the submit action
// disabled while the user edits, without remounting the modal on every change.
const showNameError = computed(() => {
  return name.isTouched.value && isNameLocallyInvalid.value && name.errorMessage.value;
});

const showDescriptionError = computed(() => {
  return (
    description.isTouched.value &&
    isDescriptionLocallyInvalid.value &&
    description.errorMessage.value
  );
});

const showProjectTypeError = computed(() => {
  return (
    projectType.isTouched.value &&
    isProjectTypeLocallyInvalid.value &&
    projectType.errorMessage.value
  );
});

const showProjectSubtypeError = computed(() => {
  return (
    projectSubtype.isTouched.value &&
    isProjectSubtypeLocallyInvalid.value &&
    projectSubtype.errorMessage.value
  );
});

const showProjectTypeOtherError = computed(() => {
  return (
    projectTypeOther.isTouched.value &&
    isProjectTypeOtherLocallyInvalid.value &&
    projectTypeOther.errorMessage.value
  );
});

function updateField(field: FormField<string>, val: string | number) {
  field.value.value = String(val);
}

function touchField(field: FormField<string>) {
  field.blur();
}

function updateSelectField(field: FormField<string>, val: string | string[]) {
  updateField(field, Array.isArray(val) ? val[0] || "" : val);
  field.blur();
}

function updateProjectType(val: string | string[]) {
  updateSelectField(projectType, val);
  updateField(projectSubtype, "");
  updateField(projectTypeOther, "");
}

function projectMetricLabel(group: string, value: string) {
  return `workspace.new_project.fields.${group}.options.${value}`;
}
</script>

<template>
  <div class="space-y-4">
    <h2 class="text-lg font-semibold">{{ title || $t("workspace.new_project.title") }}</h2>

    <div class="space-y-1.5">
      <Label for="project-name">{{ $t("workspace.new_project.fields.name.label") }}</Label>
      <Input
        id="project-name"
        name="project[name]"
        :model-value="name.value.value as string"
        @update:model-value="(v) => updateField(name, v)"
        @blur="touchField(name)"
        :placeholder="$t('workspace.new_project.fields.name.placeholder')"
        required
        :aria-invalid="showNameError ? 'true' : null"
      />
      <p v-if="showNameError" class="text-sm text-destructive flex items-center gap-1 mt-1">
        {{ name.errorMessage.value }}
      </p>
    </div>

    <div class="grid gap-3 sm:grid-cols-2">
      <div class="space-y-1.5">
        <Label for="project-type">{{
          $t("workspace.new_project.fields.project_type.label")
        }}</Label>
        <Select :model-value="selectedProjectType" required @update:model-value="updateProjectType">
          <SelectTrigger
            id="project-type"
            class="w-full"
            :aria-invalid="showProjectTypeError ? 'true' : null"
          >
            <SelectValue
              :placeholder="$t('workspace.new_project.fields.project_type.placeholder')"
            />
          </SelectTrigger>
          <SelectContent>
            <SelectItem
              v-for="option in metricsOptions.project_types"
              :key="option"
              :value="option"
            >
              {{ $t(projectMetricLabel("project_type", option)) }}
            </SelectItem>
          </SelectContent>
        </Select>
        <p
          v-if="showProjectTypeError"
          class="text-sm text-destructive flex items-center gap-1 mt-1"
        >
          {{ projectType.errorMessage.value }}
        </p>
      </div>

      <div v-if="requiresSubtype" class="space-y-1.5">
        <Label for="project-subtype">{{
          $t("workspace.new_project.fields.project_subtype.label")
        }}</Label>
        <Select
          :model-value="String(projectSubtype.value.value || '')"
          required
          @update:model-value="(v) => updateSelectField(projectSubtype, v)"
        >
          <SelectTrigger
            id="project-subtype"
            class="w-full"
            :aria-invalid="showProjectSubtypeError ? 'true' : null"
          >
            <SelectValue
              :placeholder="$t('workspace.new_project.fields.project_subtype.placeholder')"
            />
          </SelectTrigger>
          <SelectContent>
            <SelectItem v-for="option in availableSubtypes" :key="option" :value="option">
              {{ $t(projectMetricLabel(`project_subtype.${selectedProjectType}`, option)) }}
            </SelectItem>
          </SelectContent>
        </Select>
        <p
          v-if="showProjectSubtypeError"
          class="text-sm text-destructive flex items-center gap-1 mt-1"
        >
          {{ projectSubtype.errorMessage.value }}
        </p>
      </div>

      <div v-if="requiresOtherType" class="space-y-1.5">
        <Label for="project-type-other">{{
          $t("workspace.new_project.fields.project_type_other.label")
        }}</Label>
        <Input
          id="project-type-other"
          name="project[project_type_other]"
          :model-value="projectTypeOther.value.value as string"
          @update:model-value="(v) => updateField(projectTypeOther, v)"
          @blur="touchField(projectTypeOther)"
          :placeholder="$t('workspace.new_project.fields.project_type_other.placeholder')"
          maxlength="120"
          required
          :aria-invalid="showProjectTypeOtherError ? 'true' : null"
        />
        <p
          v-if="showProjectTypeOtherError"
          class="text-sm text-destructive flex items-center gap-1 mt-1"
        >
          {{ projectTypeOther.errorMessage.value }}
        </p>
      </div>
    </div>

    <div class="space-y-1.5">
      <Label for="project-description">{{
        $t("workspace.new_project.fields.description.label")
      }}</Label>
      <Textarea
        id="project-description"
        name="project[description]"
        :model-value="description.value.value as string"
        @update:model-value="(v) => updateField(description, v)"
        @blur="touchField(description)"
        :placeholder="$t('workspace.new_project.fields.description.placeholder')"
        :rows="4"
        :aria-invalid="showDescriptionError ? 'true' : null"
      />
      <p v-if="showDescriptionError" class="text-sm text-destructive flex items-center gap-1 mt-1">
        {{ description.errorMessage.value }}
      </p>
    </div>

    <div class="flex justify-end gap-2 pt-2">
      <Button type="button" variant="ghost" @click="$emit('cancel')">
        {{ $t("workspace.new_project.cancel") }}
      </Button>
      <Button @click="form.submit()" :disabled="!canSubmit">
        {{ submitLabel || $t("workspace.new_project.submit") }}
      </Button>
    </div>
  </div>
</template>
