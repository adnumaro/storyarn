<script setup lang="ts">
import type { Component } from "vue";
import {
  AlertTriangle,
  CircleAlert,
  FileText,
  GitBranch,
  Image,
  Info,
  Loader2,
  Map,
  Puzzle,
  RotateCcw,
} from "lucide-vue-next";
import { Button } from "@components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@components/ui/dialog";
import type { RestoreData } from "./useVersionHistory";

const {
  open,
  restoreData = null,
  loadingAction = null,
} = defineProps<{
  open: boolean;
  restoreData?: RestoreData | null;
  loadingAction?: string | null;
}>();

const emit = defineEmits<{
  "update:open": [open: boolean];
  confirm: [];
}>();

const conflictIcons: Record<string, Component> = {
  asset: Image,
  sheet: FileText,
  flow: GitBranch,
  scene: Map,
  block: Puzzle,
};

function conflictIcon(type: string) {
  return conflictIcons[type] || CircleAlert;
}

function conflictLabel(type: string) {
  const labels: Record<string, string> = {
    asset: "asset",
    sheet: "sheet",
    flow: "flow",
    scene: "scene",
    block: "block",
  };
  return labels[type] || "entity";
}
</script>

<template>
  <Dialog :open="open" @update:open="emit('update:open', $event)">
    <DialogContent class="sm:max-w-lg">
      <DialogHeader>
        <DialogTitle class="flex items-center gap-2">
          <RotateCcw class="size-5" />
          {{ $t("common.restore_preview_dialog.title", { version: restoreData?.versionNumber }) }}
        </DialogTitle>
      </DialogHeader>
      <template v-if="restoreData">
        <div v-if="restoreData.report.hasConflicts" class="space-y-3">
          <div
            v-if="restoreData.report.shortcutCollision"
            class="flex items-start gap-2 p-3 rounded-lg bg-amber-500/10 border border-amber-500/20"
          >
            <AlertTriangle class="size-4 text-amber-500 shrink-0 mt-0.5" />
            <span class="text-sm">{{ $t("common.restore_preview_dialog.shortcut_collision", { name: restoreData.report.resolvedShortcut }) }}</span>
          </div>
          <div v-if="restoreData.report.conflicts.length > 0" class="space-y-2">
            <p class="text-sm font-medium text-amber-600 flex items-center gap-1.5">
              <AlertTriangle class="size-4" />
              {{ $t("common.restore_preview_dialog.missing_entities") }}
            </p>
            <div
              v-for="(conflict, ci) in restoreData.report.conflicts"
              :key="ci"
              class="bg-muted/50 rounded-lg p-3"
            >
              <div class="flex items-center gap-2 text-sm font-medium">
                <component :is="conflictIcon(conflict.type)" class="size-4 text-amber-500" />
                <span>{{ $t("common.restore_preview_dialog.missing_prefix", { type: conflictLabel(conflict.type) }) }} (ID: {{ conflict.id }})</span>
              </div>
              <ul class="mt-1 ml-6 text-xs text-muted-foreground list-disc">
                <li v-for="(ctx, j) in conflict.contexts" :key="j">{{ ctx }}</li>
              </ul>
            </div>
          </div>
          <p class="text-sm text-muted-foreground">
            <template v-if="restoreData.skipPreSnapshot">{{ $t("common.restore_preview_dialog.missing_cleared") }}</template>
            <template v-else>{{ $t("common.restore_preview_dialog.missing_cleared_backup") }}</template>
          </p>
        </div>
        <p v-else class="text-muted-foreground">
          {{ $t("common.restore_preview_dialog.restore_info", { version: restoreData.versionNumber }) }}
        </p>
        <div
          v-if="(restoreData.report.autoResolved?.length ?? 0) > 0"
          class="bg-blue-500/10 border border-blue-500/20 rounded-lg p-3"
        >
          <p
            class="text-sm font-medium text-blue-600 dark:text-blue-400 mb-1 flex items-center gap-1.5"
          >
            <Info class="size-4" />
            {{ $t("common.restore_preview_dialog.auto_resolved") }}
          </p>
          <ul class="text-xs text-muted-foreground list-disc ml-5">
            <li v-for="(item, i) in restoreData.report.autoResolved" :key="i">{{ item }}</li>
          </ul>
        </div>
      </template>
      <DialogFooter>
        <Button variant="ghost" @click="emit('update:open', false)">{{ $t("common.cancel") }}</Button>
        <Button
          :class="restoreData?.report?.hasConflicts ? 'bg-amber-600 hover:bg-amber-700' : ''"
          :disabled="loadingAction === 'confirm-restore'"
          @click="emit('confirm')"
        >
          <Loader2 v-if="loadingAction === 'confirm-restore'" class="size-4 animate-spin mr-1" />
          <RotateCcw v-else class="size-4 mr-1" />
          {{ restoreData?.report?.hasConflicts ? $t("common.restore_preview_dialog.restore_anyway") : $t("common.restore_preview_dialog.restore") }}
        </Button>
      </DialogFooter>
    </DialogContent>
  </Dialog>
</template>
