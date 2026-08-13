<script setup lang="ts">
import { AlertTriangle, Loader2, Trash2 } from "@lucide/vue";
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
import VersionTransportError from "./VersionTransportError.vue";

const {
  open,
  loadingAction = null,
  transportError = false,
} = defineProps<{
  open: boolean;
  loadingAction?: string | null;
  transportError?: boolean;
}>();

const emit = defineEmits<{
  "update:open": [open: boolean];
  confirm: [];
}>();
</script>

<template>
  <Dialog :open="open" @update:open="emit('update:open', $event)">
    <DialogContent class="sm:max-w-sm">
      <DialogHeader>
        <DialogTitle class="flex items-center gap-2">
          <AlertTriangle class="size-5 text-destructive" />
          {{ $t("common.delete_version_dialog.title") }}
        </DialogTitle>
        <DialogDescription>{{ $t("common.delete_version_dialog.description") }}</DialogDescription>
      </DialogHeader>
      <VersionTransportError :visible="transportError" />
      <DialogFooter>
        <DialogClose as-child
          ><Button variant="ghost" type="button">{{ $t("common.cancel") }}</Button></DialogClose
        >
        <Button
          variant="destructive"
          :disabled="loadingAction === 'delete'"
          @click="emit('confirm')"
        >
          <Loader2 v-if="loadingAction === 'delete'" class="size-4 animate-spin mr-1" />
          <Trash2 v-else class="size-4 mr-1" />
          {{ $t("common.delete") }}
        </Button>
      </DialogFooter>
    </DialogContent>
  </Dialog>
</template>
