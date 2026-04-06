<script setup>
import { AlertTriangle, Loader2, Trash2 } from "lucide-vue-next";
import { Button } from "@components/ui/button";
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@components/ui/dialog";

const { open, loadingAction } = defineProps({
  open: { type: Boolean, required: true },
  loadingAction: { type: String, default: null },
});

const emit = defineEmits(["update:open", "confirm"]);
</script>

<template>
  <Dialog :open="open" @update:open="emit('update:open', $event)">
    <DialogContent class="sm:max-w-sm">
      <DialogHeader>
        <DialogTitle class="flex items-center gap-2">
          <AlertTriangle class="size-5 text-destructive" />
          Delete version?
        </DialogTitle>
        <DialogDescription
          >Are you sure you want to delete this version? This action cannot be
          undone.</DialogDescription
        >
      </DialogHeader>
      <DialogFooter>
        <DialogClose as-child><Button variant="ghost" type="button">Cancel</Button></DialogClose>
        <Button
          variant="destructive"
          :disabled="loadingAction === 'delete'"
          @click="emit('confirm')"
        >
          <Loader2 v-if="loadingAction === 'delete'" class="size-4 animate-spin mr-1" />
          <Trash2 v-else class="size-4 mr-1" />
          Delete
        </Button>
      </DialogFooter>
    </DialogContent>
  </Dialog>
</template>
