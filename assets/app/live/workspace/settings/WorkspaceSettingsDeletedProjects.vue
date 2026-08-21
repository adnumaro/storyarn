<script setup lang="ts">
import { FileUp, Folder, Trash2 } from "@lucide/vue";
import LiveLink from "@components/navigation/LiveLink.vue";

interface DeletedProject {
  id: number;
  name: string;
  deleted_time_ago: string;
  deleted_by_text?: string;
}

defineProps<{
  deletedProjects: DeletedProject[];
  importsPath: string;
}>();
</script>

<template>
  <div class="space-y-6">
    <div class="space-y-1.5">
      <h1 class="text-2xl font-bold tracking-tight text-foreground">
        {{ $t("settings.workspace.deleted_projects.title") }}
      </h1>
      <p class="text-base text-muted-foreground">
        {{ $t("settings.workspace.deleted_projects.subtitle") }}
      </p>
    </div>

    <section
      class="flex gap-3 rounded-xl border border-primary/20 bg-primary/5 p-4"
      aria-labelledby="deleted-project-recovery-status"
    >
      <FileUp class="mt-0.5 size-5 shrink-0 text-primary" />
      <div class="space-y-2">
        <h2 id="deleted-project-recovery-status" class="text-sm font-semibold text-foreground">
          {{ $t("settings.workspace.deleted_projects.recovery.title") }}
        </h2>
        <p class="text-sm leading-relaxed text-muted-foreground">
          {{ $t("settings.workspace.deleted_projects.recovery.description") }}
        </p>
        <LiveLink
          :to="importsPath"
          class="inline-flex text-sm font-medium text-primary underline-offset-4 hover:underline"
          data-testid="open-workspace-imports"
        >
          {{ $t("settings.workspace.deleted_projects.recovery.action") }}
        </LiveLink>
      </div>
    </section>

    <div v-if="deletedProjects.length === 0" class="py-12 text-center">
      <Trash2 class="mx-auto mb-4 size-12 text-muted-foreground/30" />
      <h3 class="mb-1 text-lg font-semibold">
        {{ $t("settings.workspace.deleted_projects.empty.title") }}
      </h3>
      <p class="text-sm text-muted-foreground">
        {{ $t("settings.workspace.deleted_projects.empty.description") }}
      </p>
    </div>

    <ul v-else class="grid gap-3" :aria-label="$t('settings.workspace.deleted_projects.title')">
      <li
        v-for="project in deletedProjects"
        :key="project.id"
        class="flex items-center gap-3 rounded-xl border border-border bg-card p-4 shadow-sm"
      >
        <span class="grid size-10 shrink-0 place-items-center rounded-lg bg-muted">
          <Folder class="size-5 text-muted-foreground" aria-hidden="true" />
        </span>
        <div class="min-w-0">
          <div class="truncate font-medium text-foreground">{{ project.name }}</div>
          <div class="text-sm text-muted-foreground">
            {{ project.deleted_time_ago }}
            <span v-if="project.deleted_by_text">{{ project.deleted_by_text }}</span>
          </div>
        </div>
      </li>
    </ul>
  </div>
</template>
