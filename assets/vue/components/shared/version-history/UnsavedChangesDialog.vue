<script setup>
import { AlertTriangle, Loader2, Save, Trash2, X } from "lucide-vue-next";
import { Button } from "@/vue/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/vue/components/ui/dialog";

defineProps({
  open: { type: Boolean, required: true },
  versionNumber: { type: Number, default: null },
  loadingAction: { type: String, default: null },
});

const emit = defineEmits([
  "update:open",
  "save-and-restore",
  "discard-and-restore",
]);
</script>

<template>
  <Dialog :open="open" @update:open="emit('update:open', $event)">
    <DialogContent class="sm:max-w-md">
      <DialogHeader>
        <DialogTitle class="flex items-center gap-2">
          <AlertTriangle class="size-5 text-amber-500" />
          Unsaved changes
        </DialogTitle>
        <DialogDescription>
          You have changes that aren't saved in any version.
          Restoring to v{{ versionNumber }} will overwrite them.
        </DialogDescription>
      </DialogHeader>
      <p class="text-sm text-muted-foreground">What would you like to do with your current changes?</p>
      <div class="flex flex-col gap-2">
        <Button class="w-full justify-start gap-2" :disabled="loadingAction === 'save-restore'" @click="emit('save-and-restore')">
          <Loader2 v-if="loadingAction === 'save-restore'" class="size-4 animate-spin" />
          <Save v-else class="size-4" />
          Save current state, then restore
        </Button>
        <Button variant="outline" class="w-full justify-start gap-2 border-amber-500/30 text-amber-600 hover:bg-amber-500/10" :disabled="loadingAction === 'discard-restore'" @click="emit('discard-and-restore')">
          <Loader2 v-if="loadingAction === 'discard-restore'" class="size-4 animate-spin" />
          <Trash2 v-else class="size-4" />
          Discard changes and restore
        </Button>
        <Button variant="ghost" class="w-full justify-start gap-2" @click="emit('update:open', false)">
          <X class="size-4" />
          Cancel
        </Button>
      </div>
    </DialogContent>
  </Dialog>
</template>
