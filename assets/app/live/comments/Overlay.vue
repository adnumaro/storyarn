<script setup lang="ts">
import { LoaderCircle, X } from "@lucide/vue";
import { nextTick, onMounted, onUnmounted, ref, watch } from "vue";
import { DialogContent, DialogPortal } from "reka-ui";
import { Dialog, DialogOverlay, DialogTitle } from "@components/ui/dialog";
import { Button } from "@components/ui/button";
import {
  OPEN_COMMENTS_EVENT,
  notifyCommentsVisibility,
} from "@components/comments/commentsHubEvents";
import { useLive } from "@shared/composables/useLive";
import Hub from "./Hub.vue";
import type { HubState } from "./types";

const { open, state, currentUserId } = defineProps<{
  open: boolean;
  state: HubState;
  currentUserId: number;
}>();

const live = useLive();
const visible = ref(open);
const failed = ref(false);
let returnFocus: HTMLElement | null = null;

function show(): void {
  if (visible.value && !failed.value) return;
  if (!visible.value) returnFocus = document.activeElement as HTMLElement | null;
  visible.value = true;
  failed.value = false;
  live.pushEvent("hub_open", {}, undefined, () => {
    failed.value = true;
  });
}

function close(): void {
  visible.value = false;
  live.pushEvent("hub_close", {});
}

function restoreFocus(event: Event): void {
  event.preventDefault();
  const target = returnFocus?.isConnected
    ? returnFocus
    : document.getElementById("comments-hub-button");
  target?.focus({ preventScroll: true });
}

function focusSearch(event: Event): void {
  event.preventDefault();
  const target =
    document.getElementById("comments-hub-search") ??
    document.getElementById("comments-review-dialog");
  target?.focus({ preventScroll: true });
}

// Keep editor shortcuts (delete, undo, Escape) away from the mounted background.
// Portalled child popovers handle their own Escape before returning here.
function handleKeydown(event: KeyboardEvent): void {
  event.stopPropagation();
  if (event.key === "Escape" && !event.defaultPrevented) {
    event.preventDefault();
    close();
  }
}

watch(
  () => open,
  async (value) => {
    if (!value && visible.value) {
      live.pushEvent("hub_open", {}, undefined, () => {
        failed.value = true;
      });
    }
    if (value && visible.value) {
      await nextTick();
      document.getElementById("comments-hub-search")?.focus({ preventScroll: true });
    }
  },
);
watch(visible, notifyCommentsVisibility);
onMounted(() => window.addEventListener(OPEN_COMMENTS_EVENT, show));
onUnmounted(() => {
  window.removeEventListener(OPEN_COMMENTS_EVENT, show);
  notifyCommentsVisibility(false);
});
</script>

<template>
  <Dialog
    :open="visible"
    @update:open="
      (value) => {
        if (!value) close();
      }
    "
  >
    <DialogPortal>
      <DialogOverlay class="z-50 bg-black/35 backdrop-blur-[2px] duration-150" />
      <DialogContent
        id="comments-review-dialog"
        aria-modal="true"
        :aria-describedby="undefined"
        class="fixed inset-0 z-50 flex min-h-0 flex-col overflow-hidden border-border bg-background shadow-2xl outline-none data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=open]:fade-in-0 data-[state=closed]:fade-out-0 duration-150 md:inset-6 md:rounded-xl md:border xl:inset-x-[max(1.5rem,calc((100vw-90rem)/2))]"
        @open-auto-focus="focusSearch"
        @close-auto-focus="restoreFocus"
        @keydown="handleKeydown"
      >
        <DialogTitle class="sr-only">{{ $t("comments_hub.title") }}</DialogTitle>
        <Hub v-if="open" :state="state" :current-user-id="currentUserId" @close="close" />
        <template v-else>
          <div class="flex h-16 shrink-0 items-center justify-between border-b px-5">
            <span class="font-semibold">{{ $t("comments_hub.title") }}</span>
            <Button
              variant="ghost"
              size="icon"
              :aria-label="$t('comments_hub.close')"
              @click="close"
              ><X class="size-4"
            /></Button>
          </div>
          <div
            class="flex flex-1 items-center justify-center gap-3 text-sm text-muted-foreground"
            role="status"
          >
            <template v-if="failed">
              <span>{{ $t("comments_hub.open_failed") }}</span>
              <Button variant="outline" size="sm" @click="show">{{
                $t("comments_hub.retry")
              }}</Button>
            </template>
            <template v-else
              ><LoaderCircle class="size-4 animate-spin" />{{
                $t("comments_hub.loading")
              }}</template
            >
          </div>
        </template>
      </DialogContent>
    </DialogPortal>
  </Dialog>
</template>
