<script setup lang="ts">
import { onBeforeUnmount, ref, watch } from "vue";
import { Popover, PopoverContent } from "@components/ui/popover";
import DecisionCard from "@app/live/ideation/DecisionCard.vue";
import type { DecisionRecord } from "@app/live/ideation/decisionTypes";
import { useBoardText } from "../composables/useBoardText";

const OPEN_DELAY = 350;
const CLOSE_DELAY = 150;

const {
  target,
  decisions,
  roundCount = 1,
} = defineProps<{
  /** The note under the pointer, when it supports a decision. */
  target: { id: number; element: HTMLElement } | null;
  decisions: DecisionRecord[];
  roundCount?: number;
}>();
const emit = defineEmits<{ open: [id: number] }>();
const { t } = useBoardText();

// The card waits for the pointer to rest and stays while it moves onto it.
const shown = ref<{ element: HTMLElement; decisions: DecisionRecord[] } | null>(null);
let inside = false;
let timer: ReturnType<typeof setTimeout> | null = null;
function schedule(action: () => void, delay: number) {
  if (timer) clearTimeout(timer);
  timer = setTimeout(action, delay);
}
watch(
  () => target,
  (current) => {
    if (current) {
      const next = { element: current.element, decisions };
      schedule(() => (shown.value = next), shown.value ? 0 : OPEN_DELAY);
    } else if (!inside) schedule(() => (shown.value = null), CLOSE_DELAY);
  },
);
function enter() {
  inside = true;
  if (timer) clearTimeout(timer);
}
function leave() {
  inside = false;
  if (!target) schedule(() => (shown.value = null), CLOSE_DELAY);
}
function open(id: number) {
  shown.value = null;
  inside = false;
  emit("open", id);
}
onBeforeUnmount(() => timer && clearTimeout(timer));
</script>
<template>
  <Popover :open="shown !== null">
    <PopoverContent
      v-if="shown"
      data-decision-hover
      :reference="shown.element"
      side="right"
      align="start"
      :side-offset="10"
      :aria-label="t('brainstormingDecisions.supports', { count: shown.decisions.length })"
      class="flex w-80 flex-col gap-0.5 p-1.5"
      @open-auto-focus.prevent
      @close-auto-focus.prevent
      @pointerenter="enter"
      @pointerleave="leave"
    >
      <p class="px-2 pt-1 pb-1.5 text-[11px] font-medium text-muted-foreground">
        {{ t("brainstormingDecisions.supports", { count: shown.decisions.length }) }}
      </p>
      <button
        v-for="decision in shown.decisions"
        :key="decision.id"
        type="button"
        :data-decision-hover-card="decision.id"
        class="rounded-md px-2 py-1.5 text-left hover:bg-accent focus-visible:bg-accent focus-visible:outline-none"
        @click="open(decision.id)"
      >
        <DecisionCard size="compact" :decision="decision" :round-count="roundCount" />
      </button>
    </PopoverContent>
  </Popover>
</template>
