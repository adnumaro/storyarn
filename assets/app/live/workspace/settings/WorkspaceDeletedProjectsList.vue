<script setup lang="ts">
import { Folder, Trash2 } from "@lucide/vue";
import { useI18n } from "vue-i18n";
import { SettingsEmptyState, SettingsRow, SettingsSection } from "@components/settings";

export interface DeletedProject {
  id: number;
  name: string;
  deletedTimeAgo: string;
  deletedByText?: string | null;
}

/**
 * Read-only inventory of the projects retained in the workspace trash. There
 * is deliberately no per-project recovery action: a project comes back only
 * by importing a downloaded snapshot.
 */
const { deletedProjects = [] } = defineProps<{ deletedProjects?: DeletedProject[] }>();

const { t } = useI18n();
</script>

<template>
  <SettingsSection :title="t('settings.workspace.deleted_projects.title')">
    <SettingsEmptyState
      v-if="deletedProjects.length === 0"
      :icon="Trash2"
      :title="t('settings.workspace.deleted_projects.empty.title')"
      :text="t('settings.workspace.projects.deleted_empty_text')"
    />

    <SettingsRow
      v-for="project in deletedProjects"
      :key="project.id"
      :data-testid="`workspace-deleted-project-${project.id}`"
      :label="project.name"
    >
      <template #leading>
        <Folder class="size-[18px] shrink-0 text-muted-foreground" aria-hidden="true" />
      </template>
      <template #hint>
        {{ project.deletedTimeAgo }}
        <span v-if="project.deletedByText">{{ project.deletedByText }}</span>
      </template>
    </SettingsRow>

    <template #footer>{{ t("settings.workspace.deleted_projects.recovery.description") }}</template>
  </SettingsSection>
</template>
