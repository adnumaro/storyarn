<script setup lang="ts">
import { Archive, Download, Loader, RotateCcw, Trash2 } from "lucide-vue-next";
import { ref } from "vue";
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
import { Separator } from "@components/ui/separator";
import { Textarea } from "@components/ui/textarea";
import { useLive } from "@shared/composables/useLive";

interface Snapshot {
  id: number;
  title?: string;
  description?: string;
  versionNumber: number;
  insertedAt: string;
  snapshotSizeBytes?: number;
  entityCounts?: Record<string, number>;
  createdByEmail?: string;
}

const {
  snapshots = [],
  canCreateSnapshot = true,
  restorationInProgress = false,
  workspaceSlug = "",
  projectSlug = "",
} = defineProps<{
  snapshots?: Snapshot[];
  canCreateSnapshot?: boolean;
  restorationInProgress?: boolean;
  workspaceSlug?: string;
  projectSlug?: string;
}>();

const live = useLive();

const snapshotTitle = ref("");
const snapshotDescription = ref("");
const showRestoreDialog = ref<number | null>(null);
const showDeleteSnapshotDialog = ref<number | null>(null);

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

function restoreSnapshot(id: number) {
  showRestoreDialog.value = null;
  live.pushEvent("restore_snapshot", { id });
}

function deleteSnapshot(id: number) {
  showDeleteSnapshotDialog.value = null;
  live.pushEvent("delete_snapshot", { id });
}

function clearStaleLock() {
  live.pushEvent("clear_stale_lock", {});
}

function formatSnapshotSize(bytes: number | undefined) {
  if (typeof bytes !== "number") return "\u2014";
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1048576) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / 1048576).toFixed(1)} MB`;
}

function formatSnapshotDate(dateStr: string | undefined) {
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

function sortedEntityCounts(counts: Record<string, number> | undefined) {
  if (!counts) return [];
  return entityTypeOrder
    .filter((type) => counts[type] && counts[type] > 0)
    .map((type) => ({ type, count: counts[type] }));
}

function downloadUrl(snapshotId: number) {
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
      <span class="flex-1">{{ $t("project_settings.snapshots.restoration_in_progress") }}</span>
      <Button variant="ghost" size="sm" @click="clearStaleLock">
        {{ $t("project_settings.snapshots.clear_lock") }}
      </Button>
    </div>

    <!-- Create Snapshot -->
    <section>
      <div class="rounded-lg border border-border bg-muted/30 p-4">
        <form @submit.prevent="createSnapshot" class="space-y-4">
          <div class="space-y-1.5">
            <Label for="snapshot-title">{{
              $t("project_settings.snapshots.snapshot_title")
            }}</Label>
            <Input
              id="snapshot-title"
              v-model="snapshotTitle"
              :placeholder="$t('project_settings.snapshots.snapshot_placeholder')"
            />
          </div>
          <div class="space-y-1.5">
            <Label for="snapshot-desc">{{ $t("project_settings.snapshots.description") }}</Label>
            <Textarea id="snapshot-desc" v-model="snapshotDescription" :rows="2" />
          </div>
          <div class="flex justify-end gap-3 pt-1">
            <Button type="submit" :disabled="!canCreateSnapshot || restorationInProgress">
              <Archive class="size-4 mr-1.5" />
              {{ $t("project_settings.snapshots.create_snapshot") }}
            </Button>
          </div>
        </form>
        <p v-if="!canCreateSnapshot" class="text-sm text-destructive mt-2">
          {{ $t("project_settings.snapshots.limit_reached") }}
        </p>
      </div>
    </section>

    <Separator />

    <!-- Snapshot List -->
    <section>
      <h3 class="text-lg font-semibold mb-4">
        {{ $t("project_settings.snapshots.snapshots_heading") }}
      </h3>

      <!-- Empty state -->
      <div v-if="snapshots.length === 0" class="text-center py-12">
        <Archive class="size-12 mx-auto mb-4 text-muted-foreground/30" />
        <p class="font-medium text-muted-foreground/70">
          {{ $t("project_settings.snapshots.empty_title") }}
        </p>
        <p class="text-sm text-muted-foreground/50 mt-1">
          {{ $t("project_settings.snapshots.empty_description") }}
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
                  {{ snapshot.title || $t("project_settings.snapshots.untitled") }}
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
                {{ $t("project_settings.snapshots.download") }}
              </Button>
              <Button
                variant="outline"
                size="sm"
                :disabled="restorationInProgress"
                @click="showRestoreDialog = snapshot.id"
              >
                <RotateCcw class="size-3 mr-1" />
                {{ $t("project_settings.snapshots.restore") }}
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
                  <DialogTitle>{{
                    $t("project_settings.snapshots.restore_confirm_title")
                  }}</DialogTitle>
                </div>
                <DialogDescription>
                  {{ $t("project_settings.snapshots.restore_confirm_description") }}
                </DialogDescription>
              </DialogHeader>
              <DialogFooter>
                <Button variant="outline" @click="showRestoreDialog = null">{{
                  $t("project_settings.snapshots.cancel")
                }}</Button>
                <Button
                  class="bg-yellow-600 hover:bg-yellow-700 text-white"
                  @click="restoreSnapshot(snapshot.id)"
                >
                  {{ $t("project_settings.snapshots.restore") }}
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
                  <DialogTitle>{{
                    $t("project_settings.snapshots.delete_confirm_title")
                  }}</DialogTitle>
                </div>
                <DialogDescription>
                  {{ $t("project_settings.snapshots.delete_confirm_description") }}
                </DialogDescription>
              </DialogHeader>
              <DialogFooter>
                <Button variant="outline" @click="showDeleteSnapshotDialog = null">{{
                  $t("project_settings.snapshots.cancel")
                }}</Button>
                <Button variant="destructive" @click="deleteSnapshot(snapshot.id)">{{
                  $t("project_settings.snapshots.delete")
                }}</Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>
        </div>
      </div>
    </section>
  </div>
</template>
