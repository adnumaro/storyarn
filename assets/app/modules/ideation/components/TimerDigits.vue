<script setup lang="ts">
import { ref, watch } from "vue";
import { Play } from "@lucide/vue";
import { useBoardText } from "../composables/useBoardText";
import { formatSeconds, parseDuration } from "../composables/useTimerWrites";

// The digits are the input, as in Figma: click them, type m:ss (or minutes,
// or h:mm:ss), Enter or play. Nothing else to configure.
const {
  seconds,
  pending = false,
  idPrefix = "brainstorming-timer",
} = defineProps<{
  seconds: number;
  pending?: boolean;
  idPrefix?: string;
}>();
const emit = defineEmits<{ "update:seconds": [seconds: number]; start: [seconds: number] }>();
const { t } = useBoardText();
const text = ref(formatSeconds(seconds));
watch(
  () => seconds,
  (value) => {
    text.value = formatSeconds(value);
  },
);
function commit(): number | null {
  const parsed = parseDuration(text.value);
  if (parsed === null) {
    text.value = formatSeconds(seconds);
    return null;
  }
  text.value = formatSeconds(parsed);
  if (parsed !== seconds) emit("update:seconds", parsed);
  return parsed;
}
function submit() {
  const parsed = commit();
  if (parsed !== null && !pending) emit("start", parsed);
}
</script>
<template>
  <div class="flex items-center gap-1">
    <input
      :id="`${idPrefix}-input`"
      v-model="text"
      type="text"
      inputmode="numeric"
      autocomplete="off"
      class="w-[4.5rem] border-b border-transparent bg-transparent text-right text-[22px] font-semibold leading-none tabular-nums outline-none focus:border-primary"
      :aria-label="t('ideation.timer.duration')"
      :placeholder="t('ideation.timer.placeholder')"
      :disabled="pending"
      @focus="($event.target as HTMLInputElement).select()"
      @blur="commit"
      @keydown.enter.prevent="submit"
    />
    <button
      :id="`${idPrefix}-start`"
      type="button"
      class="toolbar-btn"
      :aria-label="t('ideation.timer.start')"
      :disabled="pending || parseDuration(text) === null"
      @click="submit"
    >
      <Play class="size-3.5" />
    </button>
  </div>
</template>
