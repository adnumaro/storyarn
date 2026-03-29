<script setup>
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
import { Button } from "@/vue/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/vue/components/ui/dialog";

defineProps({
  open: { type: Boolean, required: true },
  restoreData: { type: Object, default: null },
  loadingAction: { type: String, default: null },
});

const emit = defineEmits(["update:open", "confirm"]);

const conflictIcons = {
  asset: Image,
  sheet: FileText,
  flow: GitBranch,
  scene: Map,
  block: Puzzle,
};

function conflictIcon(type) {
  return conflictIcons[type] || CircleAlert;
}

function conflictLabel(type) {
  const labels = {
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
          Restore to version {{ restoreData?.versionNumber }}
        </DialogTitle>
      </DialogHeader>
      <template v-if="restoreData">
        <div v-if="restoreData.report.hasConflicts" class="space-y-3">
          <div v-if="restoreData.report.shortcutCollision" class="flex items-start gap-2 p-3 rounded-lg bg-amber-500/10 border border-amber-500/20">
            <AlertTriangle class="size-4 text-amber-500 shrink-0 mt-0.5" />
            <span class="text-sm">Shortcut collision — will be renamed to "{{ restoreData.report.resolvedShortcut }}"</span>
          </div>
          <div v-if="restoreData.report.conflicts.length > 0" class="space-y-2">
            <p class="text-sm font-medium text-amber-600 flex items-center gap-1.5">
              <AlertTriangle class="size-4" />
              Some referenced entities no longer exist:
            </p>
            <div v-for="(conflict, ci) in restoreData.report.conflicts" :key="ci" class="bg-muted/50 rounded-lg p-3">
              <div class="flex items-center gap-2 text-sm font-medium">
                <component :is="conflictIcon(conflict.type)" class="size-4 text-amber-500" />
                <span>Missing {{ conflictLabel(conflict.type) }} (ID: {{ conflict.id }})</span>
              </div>
              <ul class="mt-1 ml-6 text-xs text-muted-foreground list-disc">
                <li v-for="(ctx, j) in conflict.contexts" :key="j">{{ ctx }}</li>
              </ul>
            </div>
          </div>
          <p class="text-sm text-muted-foreground">
            <template v-if="restoreData.skipPreSnapshot">Missing references will be cleared.</template>
            <template v-else>Missing references will be cleared. Current state will be saved as a backup.</template>
          </p>
        </div>
        <p v-else class="text-muted-foreground">This will restore to version {{ restoreData.versionNumber }}.</p>
        <div v-if="restoreData.report.autoResolved?.length > 0" class="bg-blue-500/10 border border-blue-500/20 rounded-lg p-3">
          <p class="text-sm font-medium text-blue-600 dark:text-blue-400 mb-1 flex items-center gap-1.5">
            <Info class="size-4" />
            Auto-resolved:
          </p>
          <ul class="text-xs text-muted-foreground list-disc ml-5">
            <li v-for="(item, i) in restoreData.report.autoResolved" :key="i">{{ item }}</li>
          </ul>
        </div>
      </template>
      <DialogFooter>
        <Button variant="ghost" @click="emit('update:open', false)">Cancel</Button>
        <Button
          :class="restoreData?.report?.hasConflicts ? 'bg-amber-600 hover:bg-amber-700' : ''"
          :disabled="loadingAction === 'confirm-restore'"
          @click="emit('confirm')"
        >
          <Loader2 v-if="loadingAction === 'confirm-restore'" class="size-4 animate-spin mr-1" />
          <RotateCcw v-else class="size-4 mr-1" />
          {{ restoreData?.report?.hasConflicts ? 'Restore anyway' : 'Restore' }}
        </Button>
      </DialogFooter>
    </DialogContent>
  </Dialog>
</template>
