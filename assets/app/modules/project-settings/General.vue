<script setup lang="ts">
import { AlertTriangle, Monitor, Moon, Sun, Wrench } from "lucide-vue-next";
import { ref, watch, onMounted, onUnmounted } from "vue";
import ColorPickerPopover from "@components/ColorPickerPopover.vue";
import { Button } from "@components/ui/button/index.ts";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@components/ui/dialog/index.ts";
import { Input } from "@components/ui/input/index.ts";
import { Label } from "@components/ui/label/index.ts";
import { Separator } from "@components/ui/separator/index.ts";
import { Textarea } from "@components/ui/textarea/index.ts";
import { useLive } from "@composables/useLive";

interface SourceLanguage {
  localeCode: string;
}

const {
  projectName = "",
  projectDescription = "",
  sourceLanguage = null,
  sourceLanguageName = "",
  themePrimary = "#00D4CC",
  themeAccent = "#E8922F",
  hasCustomTheme = false,
} = defineProps<{
  projectName?: string;
  projectDescription?: string;
  sourceLanguage?: SourceLanguage | null;
  sourceLanguageName?: string;
  themePrimary?: string;
  themeAccent?: string;
  hasCustomTheme?: boolean;
}>();

const live = useLive();

// Project Details
const projectNameLocal = ref(projectName);
const projectDescLocal = ref(projectDescription);

watch(
  () => projectName,
  (v) => {
    projectNameLocal.value = v;
  },
);
watch(
  () => projectDescription,
  (v) => {
    projectDescLocal.value = v;
  },
);

function saveProject() {
  live.pushEvent("update_project", {
    project: {
      name: projectNameLocal.value,
      description: projectDescLocal.value,
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

// Theme toggle
const currentTheme = ref("system");

function updateThemeRef() {
  currentTheme.value = localStorage.getItem("phx:theme") || "system";
}

onMounted(() => {
  updateThemeRef();
  window.addEventListener("phx:set-theme", updateThemeRef);
});

onUnmounted(() => {
  window.removeEventListener("phx:set-theme", updateThemeRef);
});

function setTheme(theme: string) {
  if (theme === "system") {
    localStorage.removeItem("phx:theme");
  } else {
    localStorage.setItem("phx:theme", theme);
  }
  window.dispatchEvent(new CustomEvent("phx:set-theme"));
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
          <Button type="submit">{{ $t("project_settings.general.save_changes") }}</Button>
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
      <div class="flex items-center gap-1 rounded-full border border-border bg-muted p-0.5 w-fit">
        <button
          :class="[
            'flex items-center justify-center size-8 rounded-full transition-colors',
            currentTheme === 'system'
              ? 'bg-background text-foreground shadow-sm'
              : 'text-muted-foreground hover:bg-accent hover:text-accent-foreground',
          ]"
          :title="$t('project_settings.general.theme_system')"
          @click="setTheme('system')"
        >
          <Monitor class="size-4" :class="{ 'opacity-75': currentTheme !== 'system' }" />
        </button>
        <button
          :class="[
            'flex items-center justify-center size-8 rounded-full transition-colors',
            currentTheme === 'light'
              ? 'bg-background text-foreground shadow-sm'
              : 'text-muted-foreground hover:bg-accent hover:text-accent-foreground',
          ]"
          :title="$t('project_settings.general.theme_light')"
          @click="setTheme('light')"
        >
          <Sun class="size-4" :class="{ 'opacity-75': currentTheme !== 'light' }" />
        </button>
        <button
          :class="[
            'flex items-center justify-center size-8 rounded-full transition-colors',
            currentTheme === 'dark'
              ? 'bg-background text-foreground shadow-sm'
              : 'text-muted-foreground hover:bg-accent hover:text-accent-foreground',
          ]"
          :title="$t('project_settings.general.theme_dark')"
          @click="setTheme('dark')"
        >
          <Moon class="size-4" :class="{ 'opacity-75': currentTheme !== 'dark' }" />
        </button>
      </div>
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
