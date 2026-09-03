<script setup lang="ts">
import { LayoutTemplate } from "@lucide/vue";
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import {
  SettingsEmptyState,
  SettingsPage,
  SettingsRow,
  SettingsSection,
} from "@components/settings";
import { Badge } from "@components/ui/badge";
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
import { Textarea } from "@components/ui/textarea";
import { useLive } from "@shared/composables/useLive";
import { formatRelativeTime } from "@shared/utils/date-utils";

interface ProjectTemplate {
  id: number;
  name: string;
  description: string;
  current_version_number?: number | null;
}

type PublicationStatus = "queued" | "running" | "retrying" | "published" | "failed";

interface ProjectTemplatePublication {
  id: number;
  mode: "new" | "update";
  status: PublicationStatus;
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
  projectName = "",
  projectDescription = "",
  projectTemplates = [],
  projectTemplatePublications = [],
  canPublish = false,
} = defineProps<{
  projectName?: string;
  projectDescription?: string;
  projectTemplates?: ProjectTemplate[];
  projectTemplatePublications?: ProjectTemplatePublication[];
  canPublish?: boolean;
}>();

const live = useLive();
const { t } = useI18n();

const activeStatuses = new Set<PublicationStatus>(["queued", "running", "retrying"]);

const hasActivePublication = computed(() =>
  projectTemplatePublications.some((publication) => activeStatuses.has(publication.status)),
);

// ---------------------------------------------------------------------------
// Publish dialog
// ---------------------------------------------------------------------------
const showTemplateDialog = ref(false);
const templateMode = ref<"new" | "update">("new");
const selectedTemplateId = ref<number | null>(null);
const templateName = ref(projectName);
const templateDescription = ref(projectDescription);
const templateVersionNotes = ref("");

const selectedTemplate = computed(
  () => projectTemplates.find((template) => template.id === selectedTemplateId.value) || null,
);

const activePublicationForSelection = computed(() =>
  projectTemplatePublications.some((publication) => {
    if (!activeStatuses.has(publication.status)) return false;
    if (templateMode.value === "new") return publication.mode === "new";

    return publication.template_id === selectedTemplateId.value;
  }),
);

const canSubmit = computed(() => {
  if (!canPublish) return false;
  if (templateName.value.trim().length === 0) return false;
  if (activePublicationForSelection.value) return false;
  if (templateMode.value === "update") return selectedTemplate.value !== null;

  return true;
});

function syncTemplateFields(template: ProjectTemplate | null): void {
  selectedTemplateId.value = template?.id || null;
  templateName.value = template?.name || projectName;
  templateDescription.value = template?.description || projectDescription;
  templateVersionNotes.value = "";
}

function openTemplateDialog(): void {
  if (!canPublish || hasActivePublication.value) return;

  const [firstTemplate] = projectTemplates;
  templateMode.value = firstTemplate ? "update" : "new";
  syncTemplateFields(firstTemplate || null);
  showTemplateDialog.value = true;
}

function updateTemplateMode(mode: "new" | "update"): void {
  templateMode.value = mode;
  syncTemplateFields(mode === "update" ? projectTemplates[0] || null : null);
}

function updateSelectedTemplate(value: string | string[]): void {
  const rawValue = Array.isArray(value) ? value[0] || "" : value;
  const id = Number(rawValue);
  syncTemplateFields(projectTemplates.find((candidate) => candidate.id === id) || null);
}

function publishTemplate(): void {
  if (!canSubmit.value) return;

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

// ---------------------------------------------------------------------------
// History
// ---------------------------------------------------------------------------
type BadgeVariant = "default" | "secondary" | "destructive" | "outline";

const statusVariant: Record<PublicationStatus, BadgeVariant> = {
  queued: "outline",
  running: "outline",
  retrying: "default",
  published: "secondary",
  failed: "destructive",
};

function publicationDescription(publication: ProjectTemplatePublication): string {
  if (publication.status === "failed" && publication.error_message) {
    return publication.error_message;
  }

  return publication.mode === "new"
    ? t("project_settings.templates.publication_new")
    : t("project_settings.templates.publication_update");
}

function publicationDate(publication: ProjectTemplatePublication): string | null {
  const iso = publication.completed_at || publication.inserted_at;
  return iso ? formatRelativeTime(iso) : null;
}
</script>

<template>
  <SettingsPage :title="t('project_settings.templates.page_title')">
    <SettingsSection :title="t('project_settings.templates.publish_section')">
      <SettingsRow
        :label="t('project_settings.templates.publish_row')"
        :hint="
          canPublish
            ? t('project_settings.templates.publish_hint')
            : t('project_settings.templates.no_permission')
        "
      >
        <Button
          type="button"
          size="sm"
          data-testid="open-template-publication-dialog"
          :disabled="!canPublish || hasActivePublication"
          @click="openTemplateDialog"
        >
          {{
            hasActivePublication
              ? t("project_settings.templates.publication_active")
              : t("project_settings.templates.publish_template")
          }}
        </Button>
      </SettingsRow>

      <SettingsRow
        v-if="projectTemplates.length > 0"
        :label="t('project_settings.templates.published_templates')"
      >
        <div class="flex flex-wrap items-center justify-end gap-1.5">
          <Badge
            v-for="template in projectTemplates"
            :key="template.id"
            variant="outline"
            :data-testid="`project-template-${template.id}`"
          >
            {{
              t("project_settings.templates.existing_option", {
                name: template.name,
                version: template.current_version_number || "-",
              })
            }}
          </Badge>
        </div>
      </SettingsRow>
    </SettingsSection>

    <SettingsSection
      :title="t('project_settings.templates.history')"
      :hint="t('project_settings.templates.history_hint')"
    >
      <SettingsEmptyState
        v-if="projectTemplatePublications.length === 0"
        :icon="LayoutTemplate"
        :title="t('project_settings.templates.empty_title')"
        :text="t('project_settings.templates.empty_text')"
      />

      <div
        v-for="publication in projectTemplatePublications"
        :key="publication.id"
        :data-testid="`template-publication-${publication.id}`"
        class="grid grid-cols-1 items-center gap-x-6 gap-y-2 px-4 py-3.5 sm:grid-cols-[minmax(0,1fr)_auto]"
      >
        <div class="min-w-0">
          <div class="truncate font-medium">{{ publication.name }}</div>
          <div class="text-[13px] text-muted-foreground">
            {{ publicationDescription(publication) }}
            <template v-if="publicationDate(publication)">
              · {{ publicationDate(publication) }}
            </template>
          </div>
        </div>
        <div class="flex items-center justify-end">
          <Badge :variant="statusVariant[publication.status]">
            {{ t(`project_settings.templates.status.${publication.status}`) }}
          </Badge>
        </div>
      </div>
    </SettingsSection>

    <Dialog v-model:open="showTemplateDialog">
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{{ t("project_settings.templates.dialog_title") }}</DialogTitle>
          <DialogDescription>
            {{ t("project_settings.templates.dialog_description") }}
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
              {{ t("project_settings.templates.mode_new") }}
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
              {{ t("project_settings.templates.mode_update") }}
            </button>
          </div>

          <div v-if="templateMode === 'update'" class="space-y-1.5">
            <Label for="template-publication-select">
              {{ t("project_settings.templates.existing") }}
            </Label>
            <Select
              :model-value="selectedTemplateId ? String(selectedTemplateId) : ''"
              @update:model-value="updateSelectedTemplate"
            >
              <SelectTrigger id="template-publication-select" class="w-full">
                <SelectValue :placeholder="t('project_settings.templates.existing_placeholder')" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem
                  v-for="template in projectTemplates"
                  :key="template.id"
                  :value="String(template.id)"
                >
                  {{
                    t("project_settings.templates.existing_option", {
                      name: template.name,
                      version: template.current_version_number || "-",
                    })
                  }}
                </SelectItem>
              </SelectContent>
            </Select>
          </div>

          <div class="space-y-1.5">
            <Label for="template-name">{{ t("project_settings.templates.name") }}</Label>
            <Input id="template-name" v-model="templateName" maxlength="100" />
          </div>

          <div class="space-y-1.5">
            <Label for="template-description">
              {{ t("project_settings.templates.description") }}
            </Label>
            <Textarea id="template-description" v-model="templateDescription" :rows="3" />
          </div>

          <div class="space-y-1.5">
            <Label for="template-version-notes">
              {{ t("project_settings.templates.version_notes") }}
            </Label>
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
            {{ t("project_settings.templates.cancel") }}
          </Button>
          <Button
            data-testid="publish-template-submit"
            :disabled="!canSubmit"
            @click="publishTemplate"
          >
            {{
              activePublicationForSelection
                ? t("project_settings.templates.publication_active")
                : t("project_settings.templates.publish_template")
            }}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  </SettingsPage>
</template>
