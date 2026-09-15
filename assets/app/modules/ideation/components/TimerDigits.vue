<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { Play } from "@lucide/vue";
import { useBoardText } from "../composables/useBoardText";
import { joinDigits } from "../composables/useTimerWrites";

// Minutes and seconds, two digits each, as on a FigJam timer: the second digit
// of the minutes moves on to the seconds, Enter or play starts.
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
const pad = (value: number) => String(value).padStart(2, "0");
const minutes = ref(pad(Math.floor(seconds / 60)));
const secs = ref(pad(seconds % 60));
const root = ref<HTMLElement | null>(null);
const minutesField = ref<HTMLInputElement | null>(null);
const secondsField = ref<HTMLInputElement | null>(null);
watch(
  () => seconds,
  (value) => {
    minutes.value = pad(Math.floor(value / 60));
    secs.value = pad(value % 60);
  },
);
const total = computed(() => joinDigits(minutes.value, secs.value));
function digits(event: Event) {
  const field = event.target as HTMLInputElement;
  field.value = field.value.replace(/\D/g, "").slice(0, 2);
  return field.value;
}
function typeMinutes(event: Event) {
  minutes.value = digits(event);
  if (minutes.value.length === 2) select(secondsField.value);
}
function typeSeconds(event: Event) {
  secs.value = digits(event);
}
function backToMinutes(event: KeyboardEvent) {
  if (event.key === "Backspace" && secs.value === "") {
    event.preventDefault();
    select(minutesField.value);
  }
}
function select(field: HTMLInputElement | null) {
  field?.focus();
  field?.select();
}
// Leaving the digits altogether settles them; moving between the two fields does not.
function leave(event: FocusEvent) {
  if (!root.value?.contains(event.relatedTarget as Node | null)) commit();
}
function commit(): number | null {
  const parsed = total.value;
  const settled = parsed ?? seconds;
  minutes.value = pad(Math.floor(settled / 60));
  secs.value = pad(settled % 60);
  if (parsed !== null && parsed !== seconds) emit("update:seconds", parsed);
  return parsed;
}
function submit() {
  const parsed = commit();
  if (parsed !== null && !pending) emit("start", parsed);
}
</script>
<template>
  <div ref="root" class="flex items-center gap-1" @focusout="leave">
    <span class="flex items-center text-[22px] font-semibold leading-none tabular-nums">
      <input
        :id="`${idPrefix}-minutes`"
        ref="minutesField"
        :value="minutes"
        type="text"
        inputmode="numeric"
        maxlength="2"
        autocomplete="off"
        class="w-[2ch] border-b border-transparent bg-transparent text-right outline-none focus:border-primary"
        :aria-label="t('ideation.timer.minutes')"
        placeholder="00"
        :disabled="pending"
        @focus="($event.target as HTMLInputElement).select()"
        @input="typeMinutes"
        @keydown.enter.prevent="submit"
      />
      <span aria-hidden="true">:</span>
      <input
        :id="`${idPrefix}-seconds`"
        ref="secondsField"
        :value="secs"
        type="text"
        inputmode="numeric"
        maxlength="2"
        autocomplete="off"
        class="w-[2ch] border-b border-transparent bg-transparent outline-none focus:border-primary"
        :aria-label="t('ideation.timer.seconds')"
        placeholder="00"
        :disabled="pending"
        @focus="($event.target as HTMLInputElement).select()"
        @input="typeSeconds"
        @keydown="backToMinutes"
        @keydown.enter.prevent="submit"
      />
    </span>
    <button
      :id="`${idPrefix}-start`"
      type="button"
      class="toolbar-btn"
      :aria-label="t('ideation.timer.start')"
      :disabled="pending || total === null"
      @click="submit"
    >
      <Play class="size-3.5" />
    </button>
  </div>
</template>
