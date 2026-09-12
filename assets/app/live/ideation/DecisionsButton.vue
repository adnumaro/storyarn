<script setup lang="ts">
import { ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import { ListChecks, Loader2 } from "@lucide/vue";
import { Popover, PopoverAnchor, PopoverContent } from "@components/ui/popover";
import ToolbarTooltip from "@components/toolbar/ToolbarTooltip.vue";
import { useLive } from "@shared/composables/useLive";
const { sessionId, epoch } = defineProps<{ sessionId: number; epoch: string }>();
const { t } = useI18n();
const live = useLive();
const pending = ref(false);
const error = ref(false);
const identity = () => `${epoch}:${sessionId}`;
watch(identity, () => {
  pending.value = false;
  error.value = false;
});
function open() {
  if (pending.value) return;
  const context = identity();
  pending.value = true;
  error.value = false;
  const finish = (failed: boolean) => {
    if (context !== identity()) return;
    pending.value = false;
    error.value = failed;
  };
  live.pushEvent(
    "decisions_open",
    { session_id: sessionId, epoch, from_header: true },
    (reply) => finish(reply?.status !== "ok"),
    () => finish(true),
  );
}
</script>
<template>
  <Popover :open="error" @update:open="error = $event"
    ><PopoverAnchor as-child
      ><span class="inline-flex shrink-0"
        ><ToolbarTooltip :label="t('brainstormingDecisions.title')" side="bottom"
          ><button
            id="brainstorming-decisions-open"
            type="button"
            class="toolbar-btn"
            :aria-label="t('brainstormingDecisions.title')"
            :disabled="pending"
            @click="open"
          >
            <Loader2 v-if="pending" class="size-3.5 animate-spin" /><ListChecks
              v-else
              class="size-3.5"
            /></button></ToolbarTooltip></span></PopoverAnchor
    ><PopoverContent
      class="w-64 p-3 text-xs text-destructive"
      side="bottom"
      align="start"
      :aria-label="t('brainstormingDecisions.title')"
      @open-auto-focus.prevent
      @close-auto-focus.prevent
      ><p role="alert">{{ t("brainstormingDecisions.errors.unavailable") }}</p></PopoverContent
    ></Popover
  >
</template>
