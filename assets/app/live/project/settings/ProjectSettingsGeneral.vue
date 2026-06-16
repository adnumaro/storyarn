<script setup lang="ts">
import { AlertTriangle, Wrench } from "lucide-vue-next";
import { computed, ref, watch } from "vue";
import ColorPickerPopover from "@components/forms/ColorPickerPopover.vue";
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

interface SourceLanguage {
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
  sourceLanguageName = "",
  themePrimary = "#00D4CC",
  themeAccent = "#E8922F",
  hasCustomTheme = false,
} = defineProps<{
  projectDetails?: ProjectDetails;
  projectMetricsOptions?: ProjectMetricsOptions;
  sourceLanguage?: SourceLanguage | null;
  sourceLanguageName?: string;
  themePrimary?: string;
  themeAccent?: string;
  hasCustomTheme?: boolean;
}>();

const live = useLive();

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
            <Label for="project-subtype">{{ $t("project_settings.general.project_subtype") }}</Label>
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
                <SelectItem
                  v-for="option in projectSubtypeOptions"
                  :key="option"
                  :value="option"
                >
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

      <div class="rounded-lg border border-border bg-muted/30 p-4 space-y-4">
        <div class="rounded-lg border border-border bg-card p-3">
          <div class="flex items-center gap-3">
            <div
              class="size-8 rounded-md bg-muted flex items-center justify-center text-xs font-bold"
            >
              {{ sourceLanguage.localeCode?.substring(0, 2).toUpperCase() }}
            </div>
            <div class="min-w-0">
              <div class="truncate text-sm font-semibold">{{ sourceLanguageName }}</div>
              <div class="text-xs text-muted-foreground">{{ sourceLanguage.localeCode }}</div>
            </div>
          </div>
        </div>

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
