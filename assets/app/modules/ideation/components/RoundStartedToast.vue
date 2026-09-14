<script setup lang="ts">
import { onUnmounted, ref, watch } from "vue";
import { Button } from "@components/ui/button";
import { useBoardText } from "../composables/useBoardText";
import type { Round } from "../types";

// A facilitator started a round elsewhere: tell everyone without moving their
// viewport, and offer the jump. The one who started it is scrolled directly.
const { round = null } = defineProps<{ round?: Round | null }>();
const emit = defineEmits<{ go: [round: Round]; dismiss: [] }>();
const { t } = useBoardText();
const visible = ref<Round | null>(null);
let timer: ReturnType<typeof setTimeout> | undefined;
watch(
  () => round,
  (next) => {
    clearTimeout(timer);
    visible.value = next;
    if (next) timer = setTimeout(() => emit("dismiss"), 8000);
  },
  { immediate: true },
);
onUnmounted(() => clearTimeout(timer));
// The toast may still be leaving when the click lands; only a shown round is a target.
function go() {
  if (visible.value) emit("go", visible.value);
}
</script>
<template>
  <Transition
    enter-active-class="transition duration-200 ease-out"
    enter-from-class="translate-y-2 opacity-0"
    enter-to-class="translate-y-0 opacity-100"
    leave-active-class="transition duration-150 ease-in"
    leave-from-class="translate-y-0 opacity-100"
    leave-to-class="translate-y-2 opacity-0"
  >
    <div
      v-if="visible"
      id="brainstorming-round-started"
      role="status"
      class="surface-panel absolute bottom-20 left-1/2 z-40 flex -translate-x-1/2 items-center gap-3 px-3 py-2 text-sm sm:bottom-16"
    >
      <span>{{ t("ideation.rounds.started", { number: visible.number }) }}</span>
      <Button size="sm" variant="outline" @click="go">{{ t("ideation.rounds.go") }}</Button>
    </div>
  </Transition>
</template>
