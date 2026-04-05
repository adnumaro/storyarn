<script setup>
import { Archive, Download, Loader, RotateCcw, Trash2 } from "lucide-vue-next";
import { ref } from "vue";
import { Badge } from "@components/ui/badge/index.js";
import { Button } from "@components/ui/button/index.js";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@components/ui/dialog/index.js";
import { Input } from "@components/ui/input/index.js";
import { Label } from "@components/ui/label/index.js";
import { Separator } from "@components/ui/separator/index.js";
import { Textarea } from "@components/ui/textarea/index.js";
import { useLive } from "@composables/useLive.js";

const { snapshots, canCreateSnapshot, restorationInProgress, workspaceSlug, projectSlug } =
  defineProps({
    snapshots: { type: Array, default: () => [] },
    canCreateSnapshot: { type: Boolean, default: true },
    restorationInProgress: { type: Boolean, default: false },
    workspaceSlug: { type: String, default: "" },
    projectSlug: { type: String, default: "" },
  });

const live = useLive();

const snapshotTitle = ref("");
const snapshotDescription = ref("");
const showRestoreDialog = ref(null);
const showDeleteSnapshotDialog = ref(null);

function createSnapshot() {
  live.pushEvent("create_snapshot", {
    snapshot: {
      title: snapshotTitle.value,
      description: snapshotDescription.value,
    },
  });
  snapshotTitle.value = "";
  snapshotDescription.value = "";
}

function restoreSnapshot(id) {
  showRestoreDialog.value = null;
  live.pushEvent("restore_snapshot", { id });
}

function deleteSnapshot(id) {
  showDeleteSnapshotDialog.value = null;
  live.pushEvent("delete_snapshot", { id });
}

function clearStaleLock() {
  live.pushEvent("clear_stale_lock", {});
}

function formatSnapshotSize(bytes) {
  if (typeof bytes !== "number") return "\u2014";
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1048576) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / 1048576).toFixed(1)} MB`;
}

function formatSnapshotDate(dateStr) {
  if (!dateStr) return "";
  const d = new Date(dateStr);
  return d.toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    timeZone: "UTC",
    timeZoneName: "short",
  });
}

const entityTypeOrder = [
  "sheets",
  "flows",
  "scenes",
  "languages",
  "localized_texts",
  "glossary_entries",
];

function sortedEntityCounts(counts) {
  if (!counts) return [];
  return entityTypeOrder
    .filter((type) => counts[type] && counts[type] > 0)
    .map((type) => ({ type, count: counts[type] }));
}

function downloadUrl(snapshotId) {
  return `/workspaces/${workspaceSlug}/projects/${projectSlug}/snapshots/${snapshotId}/download`;
}
</script>

<template>
  <div class="space-y-6">
    <!-- Restoration banner -->
    <div
      v-if="restorationInProgress"
      class="flex items-center gap-3 rounded-lg border border-yellow-500/30 bg-yellow-500/10 p-4 text-sm"
    >
      <Loader class="size-5 animate-spin text-yellow-600 shrink-0" />
      <span class="flex-1">A restoration is in progress. Please wait for it to complete.</span>
      <Button variant="ghost" size="sm" @click="clearStaleLock"> Clear stale lock </Button>
    </div>

    <!-- Create Snapshot -->
    <section>
      <div class="rounded-lg border border-border bg-muted/30 p-4">
        <form @submit.prevent="createSnapshot" class="space-y-4">
          <div class="space-y-1.5">
            <Label for="snapshot-title">Snapshot Title</Label>
            <Input
              id="snapshot-title"
              v-model="snapshotTitle"
              placeholder="e.g., Before playtest v2"
            />
          </div>
          <div class="space-y-1.5">
            <Label for="snapshot-desc">Description</Label>
            <Textarea id="snapshot-desc" v-model="snapshotDescription" :rows="2" />
          </div>
          <div class="flex justify-end gap-3 pt-1">
            <Button type="submit" :disabled="!canCreateSnapshot || restorationInProgress">
              <Archive class="size-4 mr-1.5" />
              Create Snapshot
            </Button>
          </div>
        </form>
        <p v-if="!canCreateSnapshot" class="text-sm text-destructive mt-2">
          Snapshot limit reached for your plan.
        </p>
      </div>
    </section>

    <Separator />

    <!-- Snapshot List -->
    <section>
      <h3 class="text-lg font-semibold mb-4">Snapshots</h3>

      <!-- Empty state -->
      <div v-if="snapshots.length === 0" class="text-center py-12">
        <Archive class="size-12 mx-auto mb-4 text-muted-foreground/30" />
        <p class="font-medium text-muted-foreground/70">No snapshots yet</p>
        <p class="text-sm text-muted-foreground/50 mt-1">
          Create a snapshot to save a point-in-time backup of your entire project.
        </p>
      </div>

      <div v-else class="space-y-3">
        <div
          v-for="snapshot in snapshots"
          :key="snapshot.id"
          class="rounded-lg border border-border bg-muted/30 p-4"
        >
          <div class="flex items-start justify-between gap-4">
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2">
                <Badge variant="secondary" class="text-xs"> v{{ snapshot.versionNumber }} </Badge>
                <span class="font-medium truncate">
                  {{ snapshot.title || "Untitled Snapshot" }}
                </span>
              </div>
              <p v-if="snapshot.description" class="text-sm text-muted-foreground mt-1">
                {{ snapshot.description }}
              </p>
              <div class="flex flex-wrap gap-3 mt-2 text-xs text-muted-foreground/60">
                <span v-if="snapshot.createdByEmail">
                  {{ snapshot.createdByEmail }}
                </span>
                <span>{{ formatSnapshotDate(snapshot.insertedAt) }}</span>
                <span>{{ formatSnapshotSize(snapshot.snapshotSizeBytes) }}</span>
                <span v-for="ec in sortedEntityCounts(snapshot.entityCounts)" :key="ec.type">
                  {{ ec.count }} {{ ec.type }}
                </span>
              </div>
            </div>
            <div class="flex gap-2 shrink-0">
              <Button variant="outline" size="sm" as="a" :href="downloadUrl(snapshot.id)">
                <Download class="size-3 mr-1" />
                Download
              </Button>
              <Button
                variant="outline"
                size="sm"
                :disabled="restorationInProgress"
                @click="showRestoreDialog = snapshot.id"
              >
                <RotateCcw class="size-3 mr-1" />
                Restore
              </Button>
              <Button
                variant="outline"
                size="sm"
                class="text-destructive border-destructive/30 hover:bg-destructive/10"
                :disabled="restorationInProgress"
                @click="showDeleteSnapshotDialog = snapshot.id"
              >
                <Trash2 class="size-3" />
              </Button>
            </div>
          </div>

          <!-- Restore dialog -->
          <Dialog
            :open="showRestoreDialog === snapshot.id"
            @update:open="
              (v) => {
                if (!v) showRestoreDialog = null;
              }
            "
          >
            <DialogContent>
              <DialogHeader>
                <div class="flex items-center gap-2">
                  <RotateCcw class="size-5 text-yellow-500" />
                  <DialogTitle>Restore project snapshot?</DialogTitle>
                </div>
                <DialogDescription>
                  This will overwrite all current project data with the state from this snapshot. A
                  safety snapshot will be created before restoring.
                </DialogDescription>
              </DialogHeader>
              <DialogFooter>
                <Button variant="outline" @click="showRestoreDialog = null">Cancel</Button>
                <Button
                  class="bg-yellow-600 hover:bg-yellow-700 text-white"
                  @click="restoreSnapshot(snapshot.id)"
                >
                  Restore
                </Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>

          <!-- Delete dialog -->
          <Dialog
            :open="showDeleteSnapshotDialog === snapshot.id"
            @update:open="
              (v) => {
                if (!v) showDeleteSnapshotDialog = null;
              }
            "
          >
            <DialogContent>
              <DialogHeader>
                <div class="flex items-center gap-2">
                  <Trash2 class="size-5 text-destructive" />
                  <DialogTitle>Delete snapshot?</DialogTitle>
                </div>
                <DialogDescription>
                  This will permanently delete this snapshot. This action cannot be undone.
                </DialogDescription>
              </DialogHeader>
              <DialogFooter>
                <Button variant="outline" @click="showDeleteSnapshotDialog = null">Cancel</Button>
                <Button variant="destructive" @click="deleteSnapshot(snapshot.id)">Delete</Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>
        </div>
      </div>
    </section>
  </div>
</template>
