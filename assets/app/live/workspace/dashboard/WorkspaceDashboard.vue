<script setup lang="ts">
import {
  CircleAlert,
  FilePlus2,
  FolderOpen,
  Library,
  Loader2,
  Plus,
  Search,
  Settings,
  Sparkles,
} from "lucide-vue-next";
import { computed, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@components/ui/dialog/index.ts";
import { Button } from "@components/ui/button/index.ts";
import { Input } from "@components/ui/input/index.ts";
import { Label } from "@components/ui/label/index.ts";
import { useLiveVue, type Form } from "live_vue";
import NewProjectForm from "../../project/form/ProjectNewProjectForm.vue";
import { formatRelativeTime } from "@shared/utils/date-utils";

interface Workspace {
  name: string;
  description?: string | null;
  banner_url?: string | null;
}

interface Membership {
  role: string;
}

interface Project {
  id: number;
  name: string;
  description?: string | null;
  inserted_at_formatted: string;
  updated_at: string | null;
}

interface ProjectData {
  project: Project;
  href: string;
}

interface NewProjectFormValues {
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

interface ProjectTemplate {
  id: number;
  name: string;
  description?: string | null;
  visibility: "private" | "public" | string;
  version_number?: number | null;
  entity_counts?: Record<string, number>;
  project_type?: string | null;
  project_subtype?: string | null;
}

interface TemplateInstallation {
  id: number;
  project_name: string;
  status: "queued" | "running" | "retrying" | string;
  stage: "queued" | "verifying" | "materializing" | "retrying" | string;
  template_id: number;
  template_version_id: number;
}

interface TemplateInstallationFailure {
  id: number;
  project_name: string;
  error_code?: string | null;
  error_message?: string | null;
}

interface TemplateCreationData {
  templates: ProjectTemplate[];
  installations: TemplateInstallation[];
  failures?: TemplateInstallationFailure[];
}

const {
  workspace,
  membership,
  projects = [],
  searchQuery = "",
  canCreateProject = false,
  newProjectModalOpen = false,
  newProjectForm = null,
  templateCreation = { templates: [], installations: [], failures: [] },
  projectMetricsOptions = { project_types: [], project_subtypes: {} },
  settingsUrl = null,
} = defineProps<{
  workspace: Workspace;
  membership: Membership;
  projects?: ProjectData[];
  searchQuery?: string;
  canCreateProject?: boolean;
  newProjectModalOpen?: boolean;
  newProjectForm?: Form<NewProjectFormValues> | null;
  templateCreation?: TemplateCreationData;
  projectMetricsOptions?: ProjectMetricsOptions;
  settingsUrl?: string | null;
}>();

const live = useLiveVue();
const { t } = useI18n();
const projectTemplates = computed(() => templateCreation.templates);
const templateInstallations = computed(() => templateCreation.installations);
const templateInstallationFailures = computed(() => templateCreation.failures || []);
const localSearch = ref(searchQuery);
const newProjectMode = ref<"blank" | "private" | "public">("blank");
const selectedTemplateId = ref<number | null>(null);
const templateProjectName = ref("");
const templateSubmissionPending = ref(false);
const localNewProjectModalOpen = ref(newProjectModalOpen);
const dismissedTemplateFailureIds = ref<Set<number>>(new Set());

const currentTemplateFailure = computed(
  () =>
    templateInstallationFailures.value.find(
      (failure) => !dismissedTemplateFailureIds.value.has(failure.id),
    ) || null,
);

watch(
  () => newProjectModalOpen,
  (open) => {
    localNewProjectModalOpen.value = open;
  },
);

const filteredProjects = computed(() => {
  const query = localSearch.value.trim().toLowerCase();

  if (!query) return projects;

  return projects.filter(({ project }) => {
    const name = project.name.toLowerCase();
    const description = project.description?.toLowerCase() || "";

    return name.includes(query) || description.includes(query);
  });
});

const filteredTemplateInstallations = computed(() => {
  const query = localSearch.value.trim().toLowerCase();

  if (!query) return templateInstallations.value;

  return templateInstallations.value.filter((installation) =>
    installation.project_name.toLowerCase().includes(query),
  );
});

const canManage = computed(() => ["owner", "admin"].includes(membership.role));

const canCreate = computed(() => ["owner", "admin", "member"].includes(membership.role));

const privateTemplates = computed(() =>
  projectTemplates.value.filter((template) => template.visibility === "private"),
);

const publicTemplates = computed(() =>
  projectTemplates.value.filter((template) => template.visibility === "public"),
);

const activeTemplates = computed(() => {
  if (newProjectMode.value === "private") return privateTemplates.value;
  if (newProjectMode.value === "public") return publicTemplates.value;

  return [];
});

const selectedTemplate = computed(() => {
  return activeTemplates.value.find((template) => template.id === selectedTemplateId.value) || null;
});

const canCreateFromTemplate = computed(() => {
  return (
    !!selectedTemplate.value &&
    templateProjectName.value.trim().length > 0 &&
    !templateSubmissionPending.value
  );
});

const templateNameTouched = ref(false);

const showTemplateNameError = computed(() => {
  return (
    templateNameTouched.value &&
    !!selectedTemplate.value &&
    templateProjectName.value.trim().length === 0
  );
});

function templateMetricKey(group: string, value: string) {
  return `workspace.new_project.fields.${group}.options.${value}`;
}

function setNewProjectModalOpen(open: boolean) {
  localNewProjectModalOpen.value = open;
  live.pushEvent("set_new_project_modal_open", { open });
}

function setNewProjectMode(mode: "blank" | "private" | "public") {
  newProjectMode.value = mode;

  if (mode === "blank") {
    selectedTemplateId.value = null;
    templateProjectName.value = "";
    return;
  }

  const [template] = mode === "private" ? privateTemplates.value : publicTemplates.value;
  selectTemplate(template || null);
}

function selectTemplate(template: ProjectTemplate | null) {
  selectedTemplateId.value = template?.id || null;
  templateProjectName.value = template?.name || "";
}

function createProjectFromTemplate() {
  if (!selectedTemplate.value || !canCreateFromTemplate.value) return;

  templateSubmissionPending.value = true;

  live.pushEvent(
    "create_project_from_template",
    {
      template_id: selectedTemplate.value.id,
      name: templateProjectName.value.trim(),
    },
    (response: { status?: string }) => {
      templateSubmissionPending.value = false;

      if (response.status === "queued") {
        localNewProjectModalOpen.value = false;
      }
    },
  );
}

function installationStageLabel(installation: TemplateInstallation) {
  return t(`workspace.new_project.templates.stages.${installation.stage}`);
}

const localizedTemplateFailureCodes = new Set([
  "archived",
  "asset_copy_failed",
  "checksum_mismatch",
  "incompatible_template_snapshot",
  "limit_reached",
  "missing_asset_manifest",
  "missing_checksum",
  "not_found",
  "unauthorized",
  "unremappable_subflow_exit_pin",
]);

function templateFailureMessage(failure: TemplateInstallationFailure) {
  if (failure.error_code && localizedTemplateFailureCodes.has(failure.error_code)) {
    return t(`workspace.new_project.templates.errors.${failure.error_code}`);
  }

  return t("workspace.new_project.templates.errors.generic");
}

function dismissTemplateFailure() {
  const failure = currentTemplateFailure.value;
  if (!failure || dismissedTemplateFailureIds.value.has(failure.id)) return;

  dismissedTemplateFailureIds.value = new Set([...dismissedTemplateFailureIds.value, failure.id]);

  live.pushEvent(
    "dismiss_template_installation_failure",
    { installation_id: failure.id },
    (response: { status?: string }) => {
      if (response.status === "ok") return;

      const dismissedIds = new Set(dismissedTemplateFailureIds.value);
      dismissedIds.delete(failure.id);
      dismissedTemplateFailureIds.value = dismissedIds;
    },
  );
}

function setTemplateFailureOpen(open: boolean) {
  if (!open) dismissTemplateFailure();
}

function templateCountLabel(template: ProjectTemplate) {
  const counts = template.entity_counts || {};
  const sheets = counts.sheets || 0;
  const flows = counts.flows || 0;
  const scenes = counts.scenes || 0;

  return `${sheets} / ${flows} / ${scenes}`;
}
</script>

<template>
  <div class="h-full w-full flex flex-col">
    <!-- Workspace Banner -->
    <header class="relative">
      <div
        :class="[
          'h-86 overflow-hidden rounded-xl',
          !workspace.banner_url && 'bg-linear-to-r from-primary to-secondary',
        ]"
      >
        <img
          v-if="workspace.banner_url"
          :src="workspace.banner_url"
          alt=""
          class="w-full h-full object-cover"
        />
      </div>

      <div class="absolute top-0 left-0 right-0 p-6">
        <div>
          <div class="flex justify-between items-center">
            <h1 class="text-3xl font-bold">{{ workspace.name }}</h1>
            <Button
              v-if="canManage && settingsUrl"
              as="a"
              variant="ghost"
              size="icon"
              :href="settingsUrl"
              data-phx-link="redirect"
              data-phx-link-state="push"
            >
              <Settings class="size-4" />
            </Button>
          </div>
          <div>
            <p v-if="workspace.description" class="opacity-80 mt-1 max-w-2xl">
              {{ workspace.description }}
            </p>
          </div>
        </div>
      </div>

      <div class="absolute bottom-0 left-0 right-0 px-4 py-2">
        <!-- Toolbar -->
        <div class="pt-4 pb-2 flex items-center justify-between">
          <div class="flex items-center gap-2">
            <div class="relative">
              <Search
                class="absolute left-2.5 top-1/2 -translate-y-1/2 size-4 text-muted-foreground"
              />
              <Input
                v-model="localSearch"
                type="search"
                :placeholder="$t('workspace.dashboard.search_placeholder')"
                class="pl-9 w-64"
              />
            </div>
          </div>

          <Button
            v-if="canCreate && canCreateProject && newProjectForm"
            data-testid="new-project-open"
            size="sm"
            @click="setNewProjectModalOpen(true)"
          >
            <Plus class="size-4 mr-1" />
            {{ $t("workspace.dashboard.new_project") }}
          </Button>
          <div v-else-if="canCreate && !canCreateProject" class="relative group">
            <Button size="sm" disabled>
              <Plus class="size-4 mr-1" />
              {{ $t("workspace.dashboard.new_project") }}
            </Button>
            <div
              class="absolute right-0 top-full mt-1 px-2 py-1 text-xs rounded bg-popover border border-border shadow-md opacity-0 group-hover:opacity-100 transition-opacity whitespace-nowrap pointer-events-none z-10"
            >
              {{ $t("workspace.dashboard.limit_reached") }}
            </div>
          </div>
        </div>
      </div>
    </header>

    <div class="flex-1">
      <!-- Empty states -->
      <div
        v-if="
          filteredProjects.length === 0 &&
          filteredTemplateInstallations.length === 0 &&
          !localSearch
        "
        class="flex flex-col items-center justify-center py-12 text-center h-full"
      >
        <FolderOpen class="size-12 text-muted-foreground/40 mb-4" />
        <h3 class="text-lg font-medium mb-1">
          {{ $t("workspace.dashboard.empty_projects.title") }}
        </h3>
        <p class="text-sm text-muted-foreground">
          {{ $t("workspace.dashboard.empty_projects.description") }}
        </p>
      </div>

      <div
        v-else-if="
          filteredProjects.length === 0 && filteredTemplateInstallations.length === 0 && localSearch
        "
        class="flex flex-col items-center justify-center py-12 text-center h-full"
      >
        <Search class="size-12 text-muted-foreground/40 mb-4" />
        <h3 class="text-lg font-medium mb-1">{{ $t("workspace.dashboard.empty_search.title") }}</h3>
        <p class="text-sm text-muted-foreground">
          {{ $t("workspace.dashboard.empty_search.description") }}
        </p>
      </div>

      <!-- Projects Grid -->
      <div v-else class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5 mt-4">
        <article
          v-for="installation in filteredTemplateInstallations"
          :key="`template-installation-${installation.id}`"
          :data-testid="`template-installation-${installation.id}`"
          class="relative flex min-h-44 flex-col overflow-hidden rounded-xl border border-primary/30 bg-card p-5 shadow-sm"
          aria-live="polite"
        >
          <div class="absolute inset-x-0 top-0 h-0.5 overflow-hidden bg-primary/10">
            <div class="h-full w-1/2 animate-pulse rounded-full bg-primary" />
          </div>
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <p class="text-xs font-medium uppercase tracking-wide text-primary">
                {{ $t("workspace.new_project.templates.installing") }}
              </p>
              <h3 class="mt-1 truncate text-lg font-semibold">{{ installation.project_name }}</h3>
            </div>
            <Loader2 class="size-5 shrink-0 animate-spin text-primary" aria-hidden="true" />
          </div>
          <p class="mt-3 text-sm text-muted-foreground">
            {{ installationStageLabel(installation) }}
          </p>
          <p class="mt-auto pt-5 text-xs text-muted-foreground">
            {{ $t("workspace.new_project.templates.reference", { id: installation.id }) }}
          </p>
        </article>

        <a
          v-for="projectData in filteredProjects"
          :key="projectData.project.id"
          :href="projectData.href"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="group flex flex-col rounded-xl border bg-card text-card-foreground shadow-sm hover:border-primary/40 hover:shadow-md hover:-translate-y-0.5 transition-all cursor-pointer overflow-hidden relative"
        >
          <div class="p-5 flex flex-col flex-1">
            <div>
              <h3 class="text-lg font-semibold truncate group-hover:text-primary transition-colors">
                {{ projectData.project.name }}
              </h3>
              <div class="mt-2 text-sm text-muted-foreground line-clamp-2 min-h-10">
                <template v-if="projectData.project.description">
                  {{ projectData.project.description }}
                </template>
                <template v-else>
                  <span class="italic opacity-50">{{
                    $t("workspace.dashboard.no_description")
                  }}</span>
                </template>
              </div>
            </div>

            <div class="mt-auto pt-5">
              <div class="flex items-center justify-between border-t border-border/50 pt-4">
                <div
                  class="text-xs text-muted-foreground bg-secondary/50 px-2 py-1 rounded-md font-medium"
                >
                  {{ projectData.project.inserted_at_formatted }}
                </div>
                <div class="text-xs font-medium text-muted-foreground/70">
                  {{
                    $t("workspace.dashboard.updated_at", {
                      time: formatRelativeTime(projectData.project.updated_at).toLowerCase(),
                    })
                  }}
                </div>
              </div>
            </div>
          </div>
        </a>
      </div>
    </div>
  </div>

  <Dialog v-if="currentTemplateFailure" :open="true" @update:open="setTemplateFailureOpen">
    <DialogContent data-testid="template-installation-failure-dialog" class="sm:max-w-lg">
      <template v-if="currentTemplateFailure">
        <DialogHeader>
          <div
            class="mb-2 flex size-11 items-center justify-center rounded-full bg-destructive/10 text-destructive"
          >
            <CircleAlert class="size-6" aria-hidden="true" />
          </div>
          <DialogTitle>{{ $t("workspace.new_project.templates.failed") }}</DialogTitle>
          <DialogDescription class="text-base font-medium text-foreground">
            {{ currentTemplateFailure.project_name }}
          </DialogDescription>
        </DialogHeader>

        <p
          data-testid="template-installation-failure-message"
          class="text-sm leading-6 text-muted-foreground"
        >
          {{ templateFailureMessage(currentTemplateFailure) }}
        </p>

        <div class="flex items-center justify-between gap-4 border-t border-border pt-4">
          <span class="text-xs text-muted-foreground">
            {{
              $t("workspace.new_project.templates.reference", {
                id: currentTemplateFailure.id,
              })
            }}
          </span>
          <Button
            type="button"
            data-testid="dismiss-template-installation-failure"
            @click="dismissTemplateFailure"
          >
            {{ $t("workspace.new_project.templates.acknowledge_failure") }}
          </Button>
        </div>
      </template>
    </DialogContent>
  </Dialog>

  <!-- New Project Modal -->
  <Dialog :open="localNewProjectModalOpen" @update:open="setNewProjectModalOpen">
    <DialogContent class="sm:max-w-3xl">
      <DialogHeader class="sr-only">
        <DialogTitle>{{ $t("workspace.dashboard.new_project") }}</DialogTitle>
        <DialogDescription>{{ $t("workspace.new_project.modal_description") }}</DialogDescription>
      </DialogHeader>
      <div class="space-y-5">
        <div class="grid grid-cols-3 gap-2 rounded-lg border border-border bg-muted/30 p-1">
          <button
            type="button"
            data-testid="new-project-mode-blank"
            :class="[
              'flex min-h-10 items-center justify-center gap-2 rounded-md px-3 text-sm font-medium transition',
              newProjectMode === 'blank'
                ? 'bg-background text-foreground shadow-sm'
                : 'text-muted-foreground hover:text-foreground',
            ]"
            @click="setNewProjectMode('blank')"
          >
            <FilePlus2 class="size-4" />
            {{ $t("workspace.new_project.modes.blank") }}
          </button>
          <button
            type="button"
            data-testid="new-project-mode-private"
            :class="[
              'flex min-h-10 items-center justify-center gap-2 rounded-md px-3 text-sm font-medium transition',
              newProjectMode === 'private'
                ? 'bg-background text-foreground shadow-sm'
                : 'text-muted-foreground hover:text-foreground',
            ]"
            @click="setNewProjectMode('private')"
          >
            <Library class="size-4" />
            {{ $t("workspace.new_project.modes.my_templates") }}
          </button>
          <button
            type="button"
            data-testid="new-project-mode-public"
            :class="[
              'flex min-h-10 items-center justify-center gap-2 rounded-md px-3 text-sm font-medium transition',
              newProjectMode === 'public'
                ? 'bg-background text-foreground shadow-sm'
                : 'text-muted-foreground hover:text-foreground',
            ]"
            @click="setNewProjectMode('public')"
          >
            <Sparkles class="size-4" />
            {{ $t("workspace.new_project.modes.storyarn_demos") }}
          </button>
        </div>

        <NewProjectForm
          v-if="newProjectMode === 'blank' && newProjectForm"
          :form="newProjectForm"
          :metrics-options="projectMetricsOptions"
          @cancel="setNewProjectModalOpen(false)"
        />

        <div
          v-if="newProjectMode !== 'blank'"
          class="grid gap-4 md:grid-cols-[minmax(0,1fr)_280px]"
        >
          <section class="min-h-70 rounded-lg border border-border">
            <div v-if="activeTemplates.length > 0" class="divide-y divide-border">
              <button
                v-for="template in activeTemplates"
                :key="template.id"
                type="button"
                :data-testid="`project-template-${template.id}`"
                :class="[
                  'flex w-full flex-col items-start gap-2 p-4 text-left transition hover:bg-muted/50',
                  selectedTemplateId === template.id && 'bg-primary/10',
                ]"
                @click="selectTemplate(template)"
              >
                <span class="flex w-full items-start justify-between gap-3">
                  <span class="min-w-0">
                    <span class="block truncate text-sm font-semibold">{{ template.name }}</span>
                    <span class="mt-1 line-clamp-2 block text-xs text-muted-foreground">
                      {{
                        template.description || $t("workspace.new_project.templates.no_description")
                      }}
                    </span>
                  </span>
                  <span class="rounded-md bg-muted px-2 py-1 text-xs text-muted-foreground">
                    {{
                      $t("workspace.new_project.templates.version", {
                        version: template.version_number || "-",
                      })
                    }}
                  </span>
                </span>
                <span class="flex w-full flex-wrap items-center gap-2">
                  <span
                    v-if="template.project_type"
                    class="rounded-md bg-muted px-2 py-0.5 text-xs text-muted-foreground"
                  >
                    {{ $t(templateMetricKey("project_type", template.project_type)) }}
                  </span>
                  <span
                    v-if="template.project_type && template.project_subtype"
                    class="rounded-md bg-muted px-2 py-0.5 text-xs text-muted-foreground"
                  >
                    {{
                      $t(
                        templateMetricKey(
                          `project_subtype.${template.project_type}`,
                          template.project_subtype,
                        ),
                      )
                    }}
                  </span>
                  <span class="text-xs text-muted-foreground">
                    {{ $t("workspace.new_project.templates.counts") }}:
                    {{ templateCountLabel(template) }}
                  </span>
                </span>
              </button>
            </div>

            <div
              v-else
              class="flex h-full min-h-70 flex-col items-center justify-center p-6 text-center"
            >
              <Library class="mb-3 size-8 text-muted-foreground/50" />
              <p class="text-sm font-medium">
                {{
                  newProjectMode === "private"
                    ? $t("workspace.new_project.templates.empty_private")
                    : $t("workspace.new_project.templates.empty_public")
                }}
              </p>
            </div>
          </section>

          <section class="flex flex-col rounded-lg border border-border bg-muted/30 p-4">
            <h2 class="text-lg font-semibold">{{ $t("workspace.new_project.templates.title") }}</h2>
            <p class="mt-1 text-sm text-muted-foreground">
              {{ $t("workspace.new_project.templates.description") }}
            </p>

            <div class="mt-5 space-y-1.5">
              <Label for="template-project-name">
                {{ $t("workspace.new_project.fields.name.label") }}
              </Label>
              <Input
                id="template-project-name"
                v-model="templateProjectName"
                :disabled="!selectedTemplate || templateSubmissionPending"
                maxlength="100"
                :placeholder="$t('workspace.new_project.fields.name.placeholder')"
                :aria-invalid="showTemplateNameError ? 'true' : null"
                @blur="templateNameTouched = true"
              />
              <p
                v-if="showTemplateNameError"
                class="text-sm text-destructive flex items-center gap-1 mt-1"
              >
                {{ $t("workspace.new_project.fields.name.required") }}
              </p>
            </div>

            <div class="mt-auto flex justify-end gap-2 pt-5">
              <Button
                type="button"
                variant="ghost"
                :disabled="templateSubmissionPending"
                @click="setNewProjectModalOpen(false)"
              >
                {{ $t("workspace.new_project.cancel") }}
              </Button>
              <Button
                type="button"
                data-testid="create-project-from-template"
                :disabled="!canCreateFromTemplate"
                @click="createProjectFromTemplate"
              >
                <Loader2
                  v-if="templateSubmissionPending"
                  class="mr-2 size-4 animate-spin"
                  aria-hidden="true"
                />
                {{
                  templateSubmissionPending
                    ? $t("workspace.new_project.templates.submitting")
                    : $t("workspace.new_project.templates.submit")
                }}
              </Button>
            </div>
          </section>
        </div>
      </div>
    </DialogContent>
  </Dialog>
</template>
