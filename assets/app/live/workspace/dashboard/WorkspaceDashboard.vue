<script setup lang="ts">
import {
  ArrowUpRight,
  CircleAlert,
  FilePlus2,
  FolderKanban,
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
  <div class="mx-auto flex min-h-full w-full max-w-7xl flex-col gap-6 pb-8">
    <header
      class="relative isolate min-h-72 overflow-hidden rounded-3xl border border-border/70 bg-card shadow-[0_24px_70px_-38px_rgba(0,0,0,0.55)]"
    >
      <div
        :class="[
          'absolute inset-0',
          !workspace.banner_url && 'bg-linear-to-br from-primary via-primary/80 to-project-accent',
        ]"
      >
        <img
          v-if="workspace.banner_url"
          :src="workspace.banner_url"
          alt=""
          class="h-full w-full object-cover"
        />
      </div>

      <div
        aria-hidden="true"
        class="absolute inset-0 bg-linear-to-t from-slate-950/90 via-slate-950/35 to-slate-950/15"
      />
      <div
        aria-hidden="true"
        class="absolute inset-0 opacity-25 [background-image:radial-gradient(circle_at_1px_1px,rgba(255,255,255,0.38)_1px,transparent_0)] [background-size:22px_22px]"
      />

      <div class="relative flex min-h-72 flex-col justify-between p-5 sm:p-7">
        <div class="flex justify-end">
          <Button
            v-if="canManage && settingsUrl"
            as="a"
            variant="ghost"
            size="icon"
            :href="settingsUrl"
            :aria-label="$t('workspace.dashboard.settings')"
            :title="$t('workspace.dashboard.settings')"
            class="border border-white/15 bg-black/15 text-white backdrop-blur-md hover:bg-white/15 hover:text-white"
            data-phx-link="redirect"
            data-phx-link-state="push"
          >
            <Settings class="size-4" />
          </Button>
        </div>

        <div class="max-w-3xl">
          <div
            class="mb-4 grid size-11 place-items-center rounded-2xl border border-white/15 bg-white/10 text-white backdrop-blur-md"
          >
            <FolderKanban class="size-5" aria-hidden="true" />
          </div>
          <h1 class="text-3xl font-bold tracking-tight text-white sm:text-4xl">
            {{ workspace.name }}
          </h1>
          <p
            v-if="workspace.description"
            class="mt-2 max-w-2xl text-sm leading-6 text-slate-200 sm:text-base"
          >
            {{ workspace.description }}
          </p>
        </div>
      </div>
    </header>

    <div
      class="flex flex-col gap-3 rounded-2xl border border-border/70 bg-card/80 p-3 shadow-sm backdrop-blur-sm sm:flex-row sm:items-center sm:justify-between"
    >
      <div class="relative w-full sm:max-w-sm">
        <Search class="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
        <Input
          v-model="localSearch"
          type="search"
          :placeholder="$t('workspace.dashboard.search_placeholder')"
          class="h-10 w-full border-border/70 bg-background/70 pl-9 shadow-none"
        />
      </div>

      <Button
        v-if="canCreate && canCreateProject && newProjectForm"
        data-testid="new-project-open"
        class="shadow-sm"
        @click="setNewProjectModalOpen(true)"
      >
        <Plus class="mr-1 size-4" />
        {{ $t("workspace.dashboard.new_project") }}
      </Button>
      <div v-else-if="canCreate && !canCreateProject" class="group relative">
        <Button disabled>
          <Plus class="mr-1 size-4" />
          {{ $t("workspace.dashboard.new_project") }}
        </Button>
        <div
          class="pointer-events-none absolute right-0 top-full z-10 mt-1 whitespace-nowrap rounded-lg border border-border bg-popover px-2.5 py-1.5 text-xs opacity-0 shadow-md transition-opacity group-hover:opacity-100"
        >
          {{ $t("workspace.dashboard.limit_reached") }}
        </div>
      </div>
    </div>

    <div class="flex-1">
      <div
        v-if="
          filteredProjects.length === 0 &&
          filteredTemplateInstallations.length === 0 &&
          !localSearch
        "
        class="relative flex min-h-80 flex-col items-center justify-center overflow-hidden rounded-3xl border border-dashed border-border bg-card/60 px-6 py-16 text-center"
      >
        <div
          aria-hidden="true"
          class="absolute -top-16 size-56 rounded-full bg-primary/[0.07] blur-3xl"
        />
        <span
          class="relative mb-5 grid size-16 place-items-center rounded-2xl border border-primary/15 bg-primary/[0.08] text-primary"
        >
          <FolderOpen class="size-7" />
        </span>
        <h3 class="relative text-lg font-semibold">
          {{ $t("workspace.dashboard.empty_projects.title") }}
        </h3>
        <p class="relative mt-1 max-w-md text-sm leading-6 text-muted-foreground">
          {{ $t("workspace.dashboard.empty_projects.description") }}
        </p>
      </div>

      <div
        v-else-if="
          filteredProjects.length === 0 && filteredTemplateInstallations.length === 0 && localSearch
        "
        class="relative flex min-h-80 flex-col items-center justify-center overflow-hidden rounded-3xl border border-dashed border-border bg-card/60 px-6 py-16 text-center"
      >
        <span
          class="mb-5 grid size-16 place-items-center rounded-2xl border border-primary/15 bg-primary/[0.08] text-primary"
        >
          <Search class="size-7" />
        </span>
        <h3 class="text-lg font-semibold">{{ $t("workspace.dashboard.empty_search.title") }}</h3>
        <p class="mt-1 max-w-md text-sm leading-6 text-muted-foreground">
          {{ $t("workspace.dashboard.empty_search.description") }}
        </p>
      </div>

      <div v-else class="grid grid-cols-1 gap-5 md:grid-cols-2 xl:grid-cols-3">
        <article
          v-for="installation in filteredTemplateInstallations"
          :key="`template-installation-${installation.id}`"
          :data-testid="`template-installation-${installation.id}`"
          class="relative flex min-h-48 flex-col overflow-hidden rounded-2xl border border-primary/30 bg-card/85 p-5 shadow-sm"
          aria-live="polite"
        >
          <div class="absolute inset-x-0 top-0 h-0.5 overflow-hidden bg-primary/10">
            <div
              class="h-full w-1/2 animate-pulse rounded-full bg-linear-to-r from-primary to-project-accent"
            />
          </div>
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <p class="text-xs font-semibold uppercase tracking-[0.16em] text-primary">
                {{ $t("workspace.new_project.templates.installing") }}
              </p>
              <h3 class="mt-2 truncate text-lg font-semibold">{{ installation.project_name }}</h3>
            </div>
            <span
              class="grid size-9 shrink-0 place-items-center rounded-xl bg-primary/10 text-primary"
            >
              <Loader2 class="size-4.5 animate-spin" aria-hidden="true" />
            </span>
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
          :data-testid="`project-card-${projectData.project.id}`"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="group relative flex min-h-48 flex-col overflow-hidden rounded-2xl border border-border/70 bg-card/85 text-card-foreground shadow-[0_1px_2px_rgba(0,0,0,0.04)] transition-all duration-200 hover:-translate-y-1 hover:border-primary/35 hover:shadow-xl focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/50"
        >
          <div
            aria-hidden="true"
            class="absolute inset-x-0 top-0 h-0.5 bg-linear-to-r from-primary via-primary/75 to-project-accent opacity-80"
          />
          <div
            aria-hidden="true"
            class="absolute -right-12 -top-12 size-36 rounded-full bg-primary/[0.055] blur-3xl transition-transform duration-300 group-hover:scale-125"
          />

          <div class="relative flex flex-1 flex-col p-5">
            <div class="flex items-start justify-between gap-4">
              <span
                class="grid size-10 shrink-0 place-items-center rounded-xl border border-primary/15 bg-primary/[0.08] text-primary"
              >
                <FolderKanban class="size-4.5" />
              </span>
              <ArrowUpRight
                class="size-4 text-muted-foreground/35 transition-all duration-200 group-hover:-translate-y-0.5 group-hover:translate-x-0.5 group-hover:text-primary"
              />
            </div>

            <div class="mt-5">
              <h3
                class="truncate text-lg font-semibold tracking-tight transition-colors group-hover:text-primary"
              >
                {{ projectData.project.name }}
              </h3>
              <p class="mt-2 line-clamp-2 min-h-10 text-sm leading-5 text-muted-foreground">
                <template v-if="projectData.project.description">
                  {{ projectData.project.description }}
                </template>
                <template v-else>
                  <span class="italic opacity-60">{{
                    $t("workspace.dashboard.no_description")
                  }}</span>
                </template>
              </p>
            </div>

            <div
              class="mt-auto flex items-center justify-between gap-3 border-t border-border/50 pt-4"
            >
              <span
                class="rounded-lg bg-muted/70 px-2.5 py-1 text-xs font-medium text-muted-foreground"
              >
                {{ projectData.project.inserted_at_formatted }}
              </span>
              <span class="truncate text-xs font-medium text-muted-foreground">
                {{
                  $t("workspace.dashboard.updated_at", {
                    time: formatRelativeTime(projectData.project.updated_at).toLowerCase(),
                  })
                }}
              </span>
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
