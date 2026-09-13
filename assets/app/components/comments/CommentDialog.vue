<script setup lang="ts">
import { Dialog, DialogContent, DialogTitle } from "@components/ui/dialog";
import { useLive } from "@shared/composables/useLive";
import CommentPopover from "./CommentPopover.vue";
import type { CommentsPanelState, CommentUiConfig } from "./types";

const {
  state,
  ui,
  draftStorageKey = null,
} = defineProps<{
  state: CommentsPanelState;
  ui: CommentUiConfig;
  draftStorageKey?: string | null;
}>();
const live = useLive();
</script>

<template>
  <Dialog
    :open="state.open"
    @update:open="
      (value) => {
        if (!value) live.pushEvent('comments_close', {});
      }
    "
  >
    <DialogContent
      :show-close-button="false"
      :aria-describedby="undefined"
      class="flex max-h-[calc(100dvh-2rem)] flex-col gap-0 border-0 p-0 sm:max-w-md"
      @pointer-down-outside.prevent
      @keydown.stop
    >
      <DialogTitle class="sr-only">{{
        $t(`${ui.i18nPrefix}.${state.thread ? "title" : "new_thread"}`)
      }}</DialogTitle>
      <CommentPopover :state="state" :ui="ui" :draft-storage-key="draftStorageKey">
        <template v-if="$slots.footer" #footer><slot name="footer" /></template>
      </CommentPopover>
    </DialogContent>
  </Dialog>
</template>
