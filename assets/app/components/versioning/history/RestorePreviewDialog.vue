<script setup lang="ts">
import { computed, type Component } from "vue";
import {
  AlertTriangle,
  CircleAlert,
  FileText,
  GitBranch,
  Image,
  Link2,
  Loader2,
  Map,
  Puzzle,
  RotateCcw,
  Variable,
  UserRound,
} from "@lucide/vue";
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

const hasBlockingConflicts = computed(() => (restoreData?.report.conflicts.length ?? 0) > 0);

const conflictIcons: Record<string, Component> = {
  asset: Image,
  sheet: FileText,
  flow: GitBranch,
  scene: Map,
  block: Puzzle,
  avatar: UserRound,
  reference: Link2,
  variable: Variable,
};

function conflictIcon(type: string) {
  return conflictIcons[type] || CircleAlert;
}

function conflictLabelKey(type: string) {
  const keys: Record<string, string> = {
    asset: "common.restore_preview_dialog.entity_types.asset",
    sheet: "common.restore_preview_dialog.entity_types.sheet",
    flow: "common.restore_preview_dialog.entity_types.flow",
    scene: "common.restore_preview_dialog.entity_types.scene",
    block: "common.restore_preview_dialog.entity_types.block",
    avatar: "common.restore_preview_dialog.entity_types.avatar",
    reference: "common.restore_preview_dialog.entity_types.reference",
    variable: "common.restore_preview_dialog.entity_types.variable",
  };
  return keys[type] || "common.restore_preview_dialog.entity_types.entity";
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
            <span class="text-sm">{{
              $t("common.restore_preview_dialog.shortcut_collision", {
                name: restoreData.report.resolvedShortcut,
              })
            }}</span>
          </div>
          <div v-if="restoreData.report.conflicts.length > 0" class="space-y-2">
            <p class="text-sm font-medium text-destructive flex items-center gap-1.5">
              <AlertTriangle class="size-4" />
              {{ $t("common.restore_preview_dialog.missing_entities") }}
            </p>
            <div
              v-for="(conflict, ci) in restoreData.report.conflicts"
              :key="ci"
              class="bg-muted/50 rounded-lg p-3"
            >
              <div class="flex items-center gap-2 text-sm font-medium">
                <component :is="conflictIcon(conflict.type)" class="size-4 text-destructive" />
                <span
                  >{{
                    $t("common.restore_preview_dialog.missing_prefix", {
                      type: $t(conflictLabelKey(conflict.type)),
                    })
                  }}
                  (ID: {{ conflict.id ?? $t("common.restore_preview_dialog.invalid_id") }})</span
                >
              </div>
              <ul class="mt-1 ml-6 text-xs text-muted-foreground list-disc">
                <li v-for="(ctx, j) in conflict.contexts" :key="j">{{ ctx }}</li>
              </ul>
            </div>
          </div>
          <p v-if="hasBlockingConflicts" class="text-sm text-destructive">
            {{ $t("common.restore_preview_dialog.missing_blocked") }}
          </p>
        </div>
        <p v-else class="text-muted-foreground">
          {{
            $t("common.restore_preview_dialog.restore_info", { version: restoreData.versionNumber })
          }}
        </p>
      </template>
      <DialogFooter>
        <Button variant="ghost" @click="emit('update:open', false)">{{
          $t("common.cancel")
        }}</Button>
        <Button
          :disabled="loadingAction === 'confirm-restore' || hasBlockingConflicts"
          @click="emit('confirm')"
        >
          <Loader2 v-if="loadingAction === 'confirm-restore'" class="size-4 animate-spin mr-1" />
          <RotateCcw v-else class="size-4 mr-1" />
          <template v-if="hasBlockingConflicts">
            {{ $t("common.restore_preview_dialog.restore_blocked") }}
          </template>
          <template v-else>{{ $t("common.restore_preview_dialog.restore") }}</template>
        </Button>
      </DialogFooter>
    </DialogContent>
  </Dialog>
</template>
