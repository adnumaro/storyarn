<script setup lang="ts">
import { ChevronDown, ChevronUp, Folder, RotateCcw, Trash2 } from "lucide-vue-next";
import { computed, ref } from "vue";
import { Badge } from "@components/ui/badge/index.ts";
import { Button } from "@components/ui/button/index.ts";
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@components/ui/dialog/index.ts";
import { useLive } from "@composables/useLive";

interface DeletedProject {
  id: number;
  name: string;
  deleted_time_ago: string;
  deleted_by_text?: string;
  snapshot_count: number;
}

interface ProjectSnapshot {
  id: number;
  title?: string;
  version_number: number;
  formatted_date: string;
  entity_counts?: Record<string, number>;
}

const { deletedProjects, expandedProjectId = null, snapshots = [], recovering = false } = defineProps<{
  deletedProjects: DeletedProject[];
  expandedProjectId?: number | null;
  snapshots?: ProjectSnapshot[];
  recovering?: boolean;
}>();

const live = useLive();

const recoverDialogOpen = ref(false);
const recoverSnapshot = ref<ProjectSnapshot | null>(null);
const recoverProjectId = ref<number | null>(null);

function toggleProject(projectId: number) {
  live.pushEvent("toggle_project", { id: String(projectId) });
}

function openRecoverDialog(snapshot: ProjectSnapshot, projectId: number) {
  recoverSnapshot.value = snapshot;
  recoverProjectId.value = projectId;
  recoverDialogOpen.value = true;
}

function confirmRecover() {
  if (recoverSnapshot.value && recoverProjectId.value) {
    live.pushEvent("recover_project", {
      snapshot_id: recoverSnapshot.value.id,
      project_id: recoverProjectId.value,
    });
  }
  recoverDialogOpen.value = false;
}

// Remove useI18n

function formatEntityCounts(counts: Record<string, number> | undefined) {
  if (!counts) return "";
  const parts = [];
  if (counts.sheets && counts.sheets > 0) {
    parts.push(`${counts.sheets} ${counts.sheets === 1 ? "sheet" : "sheets"}`);
  }
  if (counts.flows && counts.flows > 0) {
    parts.push(`${counts.flows} ${counts.flows === 1 ? "flow" : "flows"}`);
  }
  if (counts.scenes && counts.scenes > 0) {
    parts.push(`${counts.scenes} ${counts.scenes === 1 ? "scene" : "scenes"}`);
  }
  return parts.join(", ");
}
</script>

<template>
  <div class="space-y-4">
    <div class="space-y-1.5 mb-8">
      <h1 class="text-2xl font-bold tracking-tight text-foreground">
        {{ $t("settings.workspace.deleted_projects.title") }}
      </h1>
      <p class="text-base text-muted-foreground">
        {{ $t("settings.workspace.deleted_projects.subtitle") }}
      </p>
    </div>

    <!-- Empty state -->
    <div v-if="deletedProjects.length === 0" class="py-12 text-center">
      <Trash2 class="size-12 text-muted-foreground/30 mx-auto mb-4" />
      <h3 class="text-lg font-semibold mb-1">
        {{ $t("settings.workspace.deleted_projects.empty.title") }}
      </h3>
      <p class="text-sm text-muted-foreground">
        {{ $t("settings.workspace.deleted_projects.empty.description") }}
      </p>
    </div>

    <!-- Project list -->
    <div
      v-for="project in deletedProjects"
      :key="project.id"
      class="border border-border rounded-lg"
    >
      <button
        type="button"
        class="w-full flex items-center justify-between p-4 hover:bg-accent/50 transition-colors"
        @click="toggleProject(project.id)"
      >
        <div class="flex items-center gap-3">
          <Folder class="size-5 text-muted-foreground" />
          <div class="text-left">
            <div class="font-medium">{{ project.name }}</div>
            <div class="text-sm text-muted-foreground">
              {{ project.deleted_time_ago }}
              <span v-if="project.deleted_by_text">
                {{ project.deleted_by_text }}
              </span>
            </div>
          </div>
        </div>
        <div class="flex items-center gap-3">
          <Badge variant="secondary">
            {{ project.snapshot_count }}
            {{
              project.snapshot_count === 1
                ? $t("settings.workspace.deleted_projects.snapshot")
                : $t("settings.workspace.deleted_projects.snapshots")
            }}
          </Badge>
          <ChevronUp v-if="expandedProjectId === project.id" class="size-4 text-muted-foreground" />
          <ChevronDown v-else class="size-4 text-muted-foreground" />
        </div>
      </button>

      <!-- Expanded snapshots -->
      <div v-if="expandedProjectId === project.id" class="border-t border-border p-4 space-y-3">
        <div v-if="snapshots.length === 0" class="text-sm text-muted-foreground py-4 text-center">
          {{ $t("settings.workspace.deleted_projects.no_snapshots") }}
        </div>

        <div
          v-for="snapshot in snapshots"
          :key="snapshot.id"
          class="flex items-center justify-between p-3 bg-muted/50 rounded-lg"
        >
          <div>
            <div class="font-medium text-sm">
              {{
                snapshot.title ||
                `${$t("settings.workspace.deleted_projects.snapshot_prefix")}${snapshot.version_number}`
              }}
            </div>
            <div class="text-xs text-muted-foreground mt-0.5">
              {{ snapshot.formatted_date }}
              <span v-if="snapshot.entity_counts">
                &mdash; {{ formatEntityCounts(snapshot.entity_counts) }}
              </span>
            </div>
          </div>
          <Button size="sm" :disabled="recovering" @click="openRecoverDialog(snapshot, project.id)">
            <RotateCcw class="size-3.5" />
            {{ $t("settings.workspace.deleted_projects.recover") }}
          </Button>
        </div>
      </div>
    </div>

    <!-- Recover Confirmation Dialog -->
    <Dialog v-model:open="recoverDialogOpen">
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{{
            $t("settings.workspace.deleted_projects.recover_modal.title")
          }}</DialogTitle>
          <DialogDescription>
            {{
              $t("settings.workspace.deleted_projects.recover_modal.description").replace(
                "{number}",
                String(recoverSnapshot?.version_number ?? ""),
              )
            }}
          </DialogDescription>
        </DialogHeader>
        <DialogFooter>
          <DialogClose as-child>
            <Button variant="outline">{{
              $t("settings.workspace.deleted_projects.recover_modal.cancel")
            }}</Button>
          </DialogClose>
          <Button @click="confirmRecover">
            {{ $t("settings.workspace.deleted_projects.recover") }}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  </div>
</template>
