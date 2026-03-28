<script setup>
import { ref, computed } from "vue";
import { useLive } from "@/vue/composables/useLive";
import { Button } from "@/vue/components/ui/button";
import { Badge } from "@/vue/components/ui/badge";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
  DialogClose,
} from "@/vue/components/ui/dialog";
import { Folder, ChevronUp, ChevronDown, RotateCcw, Trash2 } from "lucide-vue-next";

const props = defineProps({
  deletedProjects: { type: Array, required: true },
  expandedProjectId: { type: [Number, null], default: null },
  snapshots: { type: Array, default: () => [] },
  recovering: { type: Boolean, default: false },
  translations: { type: Object, required: true },
});

const live = useLive();

const recoverDialogOpen = ref(false);
const recoverSnapshot = ref(null);
const recoverProjectId = ref(null);

function toggleProject(projectId) {
  live.pushEvent("toggle_project", { id: String(projectId) });
}

function openRecoverDialog(snapshot, projectId) {
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

function formatEntityCounts(counts) {
  if (!counts) return "";
  const parts = [];
  if (counts.sheets && counts.sheets > 0) {
    parts.push(`${counts.sheets} ${counts.sheets === 1 ? props.translations.sheet : props.translations.sheets}`);
  }
  if (counts.flows && counts.flows > 0) {
    parts.push(`${counts.flows} ${counts.flows === 1 ? props.translations.flow : props.translations.flows}`);
  }
  if (counts.scenes && counts.scenes > 0) {
    parts.push(`${counts.scenes} ${counts.scenes === 1 ? props.translations.scene : props.translations.scenes}`);
  }
  return parts.join(", ");
}
</script>

<template>
  <div class="space-y-4">
    <!-- Empty state -->
    <div v-if="deletedProjects.length === 0" class="py-12 text-center">
      <Trash2 class="size-12 text-muted-foreground/30 mx-auto mb-4" />
      <h3 class="text-lg font-semibold mb-1">{{ translations.noDeletedProjects }}</h3>
      <p class="text-sm text-muted-foreground">
        {{ translations.noDeletedProjectsDescription }}
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
            {{ project.snapshot_count }} {{ project.snapshot_count === 1 ? translations.snapshot : translations.snapshots }}
          </Badge>
          <ChevronUp v-if="expandedProjectId === project.id" class="size-4 text-muted-foreground" />
          <ChevronDown v-else class="size-4 text-muted-foreground" />
        </div>
      </button>

      <!-- Expanded snapshots -->
      <div
        v-if="expandedProjectId === project.id"
        class="border-t border-border p-4 space-y-3"
      >
        <div v-if="snapshots.length === 0" class="text-sm text-muted-foreground py-4 text-center">
          {{ translations.noSnapshots }}
        </div>

        <div
          v-for="snapshot in snapshots"
          :key="snapshot.id"
          class="flex items-center justify-between p-3 bg-muted/50 rounded-lg"
        >
          <div>
            <div class="font-medium text-sm">
              {{ snapshot.title || `${translations.snapshotPrefix} ${snapshot.version_number}` }}
            </div>
            <div class="text-xs text-muted-foreground mt-0.5">
              {{ snapshot.formatted_date }}
              <span v-if="snapshot.entity_counts">
                &mdash; {{ formatEntityCounts(snapshot.entity_counts) }}
              </span>
            </div>
          </div>
          <Button
            size="sm"
            :disabled="recovering"
            @click="openRecoverDialog(snapshot, project.id)"
          >
            <RotateCcw class="size-3.5" />
            {{ translations.recover }}
          </Button>
        </div>
      </div>
    </div>

    <!-- Recover Confirmation Dialog -->
    <Dialog v-model:open="recoverDialogOpen">
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{{ translations.recoverTitle }}</DialogTitle>
          <DialogDescription>
            {{ translations.recoverMessage?.replace('%{number}', recoverSnapshot?.version_number) }}
          </DialogDescription>
        </DialogHeader>
        <DialogFooter>
          <DialogClose as-child>
            <Button variant="outline">{{ translations.cancel }}</Button>
          </DialogClose>
          <Button @click="confirmRecover">
            {{ translations.recover }}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  </div>
</template>
