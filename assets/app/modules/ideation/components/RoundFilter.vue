<script setup lang="ts">
import { computed } from "vue";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@components/ui/select";
import { useBoardText } from "../composables/useBoardText";
import type { Round, RoundFilter } from "../types";
const {
  rounds,
  value,
  pending = false,
} = defineProps<{
  rounds: Round[];
  value: RoundFilter;
  pending?: boolean;
}>();
const emit = defineEmits<{ change: [value: RoundFilter] }>();
const { t } = useBoardText();
const selected = computed(() => (value === null ? "none" : String(value)));
function choose(value: string) {
  if (value === "all") emit("change", "all");
  else if (value === "none") emit("change", null);
  else emit("change", Number(value));
}
</script>
<template>
  <Select :model-value="selected" :disabled="pending" @update:model-value="choose(String($event))">
    <SelectTrigger
      id="brainstorming-round-filter"
      :aria-label="t('ideation.rounds.filter')"
      class="h-8 w-40 text-xs"
    >
      <SelectValue />
    </SelectTrigger>
    <SelectContent>
      <SelectItem value="all">{{ t("ideation.rounds.all") }}</SelectItem>
      <SelectItem value="none">{{ t("ideation.rounds.none") }}</SelectItem>
      <SelectItem v-for="round in rounds" :key="round.id" :value="String(round.id)">{{
        t("ideation.rounds.number", { number: round.number })
      }}</SelectItem>
    </SelectContent>
  </Select>
</template>
