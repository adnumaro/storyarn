<script setup lang="ts">
import { AlertTriangle, Loader2, ShieldCheck, X } from "@lucide/vue";
import { Button } from "@components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@components/ui/dialog";
import VersionTransportError from "./VersionTransportError.vue";

const {
  open,
  versionNumber = null,
  loadingAction = null,
  transportError = false,
} = defineProps<{
  open: boolean;
  versionNumber?: number | null;
  loadingAction?: string | null;
  transportError?: boolean;
}>();

const emit = defineEmits<{
  "update:open": [open: boolean];
  "review-restore": [];
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
      <VersionTransportError :visible="transportError" />
      <p class="text-sm text-muted-foreground">
        {{ $t("common.unsaved_changes_dialog.question") }}
      </p>
      <div class="flex flex-col gap-2">
        <Button
          class="w-full justify-start gap-2"
          :disabled="loadingAction === 'review-restore'"
          @click="emit('review-restore')"
        >
          <Loader2 v-if="loadingAction === 'review-restore'" class="size-4 animate-spin" />
          <ShieldCheck v-else class="size-4" />
          {{ $t("common.unsaved_changes_dialog.review_restore") }}
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
