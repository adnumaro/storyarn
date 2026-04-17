<script setup lang="ts">
import { AlertTriangle, Loader2, Save, Trash2, X } from "lucide-vue-next";
import { Button } from "@components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@components/ui/dialog";

const {
  open,
  versionNumber = null,
  loadingAction = null,
} = defineProps<{
  open: boolean;
  versionNumber?: number | null;
  loadingAction?: string | null;
}>();

const emit = defineEmits<{
  "update:open": [open: boolean];
  "save-and-restore": [];
  "discard-and-restore": [];
}>();
</script>

<template>
  <Dialog :open="open" @update:open="emit('update:open', $event)">
    <DialogContent class="sm:max-w-md">
      <DialogHeader>
        <DialogTitle class="flex items-center gap-2">
          <AlertTriangle class="size-5 text-amber-500" />
          {{ $t("common.unsaved_changes_dialog.title") }}
        </DialogTitle>
        <DialogDescription>
          {{ $t("common.unsaved_changes_dialog.description", { version: versionNumber }) }}
        </DialogDescription>
      </DialogHeader>
      <p class="text-sm text-muted-foreground">
        {{ $t("common.unsaved_changes_dialog.question") }}
      </p>
      <div class="flex flex-col gap-2">
        <Button
          class="w-full justify-start gap-2"
          :disabled="loadingAction === 'save-restore'"
          @click="emit('save-and-restore')"
        >
          <Loader2 v-if="loadingAction === 'save-restore'" class="size-4 animate-spin" />
          <Save v-else class="size-4" />
          {{ $t("common.unsaved_changes_dialog.save_then_restore") }}
        </Button>
        <Button
          variant="outline"
          class="w-full justify-start gap-2 border-amber-500/30 text-amber-600 hover:bg-amber-500/10"
          :disabled="loadingAction === 'discard-restore'"
          @click="emit('discard-and-restore')"
        >
          <Loader2 v-if="loadingAction === 'discard-restore'" class="size-4 animate-spin" />
          <Trash2 v-else class="size-4" />
          {{ $t("common.unsaved_changes_dialog.discard_and_restore") }}
        </Button>
        <Button
          variant="ghost"
          class="w-full justify-start gap-2"
          @click="emit('update:open', false)"
        >
          <X class="size-4" />
          {{ $t("common.cancel") }}
        </Button>
      </div>
    </DialogContent>
  </Dialog>
</template>
