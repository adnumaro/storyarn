<script setup lang="ts">
import { computed, nextTick, onMounted, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import { Check, Search, X, Layers, StickyNote, Loader2 } from "@lucide/vue";
import { Button } from "@components/ui/button";
import { Input } from "@components/ui/input";
import type { DecisionSource, DecisionSourceType } from "./decisionTypes";
const { sources, results, nextCursor, searched, pending } = defineProps<{
  sources: DecisionSource[];
  results: DecisionSource[];
  nextCursor: number | null;
  searched: boolean;
  pending: boolean;
}>();
const emit = defineEmits<{
  search: [type: DecisionSourceType, query: string, cursor: number | null, onSuccess: () => void];
  select: [source: DecisionSource];
  close: [];
}>();
const { t } = useI18n();
const query = ref("");
const type = ref<DecisionSourceType>("idea");
const searchInput = ref<InstanceType<typeof Input> | null>(null);
const previous = ref<Array<number | null>>([]);
const cursor = ref<number | null>(null);
const applied = ref("");
const searchKey = () => JSON.stringify([type.value, query.value]);
const currentQuery = computed(() => applied.value === searchKey());
const visible = computed(() => results.filter((source) => source.type === type.value));
const selected = (source: DecisionSource) =>
  sources.some((item) => item.identity === source.identity);
watch(searchKey, () => {
  previous.value = [];
  cursor.value = null;
});
function search(next: number | null = null, history: Array<number | null> = []) {
  if (pending) return;
  const key = searchKey();
  emit("search", type.value, query.value, next, () => {
    if (key !== searchKey()) return;
    previous.value = history;
    cursor.value = next;
    applied.value = key;
  });
}
function changeType(next: DecisionSourceType) {
  type.value = next;
  search();
}
onMounted(async () => {
  await nextTick();
  const input = searchInput.value?.$el;
  if (input instanceof HTMLInputElement) input.focus();
});
</script>
<template>
  <section
    id="decision-source-picker"
    class="space-y-3 rounded-lg border border-primary/30 bg-muted/25 p-3"
    :aria-label="t('brainstormingDecisions.addSources')"
  >
    <div class="flex items-center gap-1">
      <Button
        v-for="kind in ['idea', 'group'] as const"
        :key="kind"
        size="sm"
        :variant="type === kind ? 'secondary' : 'ghost'"
        :aria-pressed="type === kind"
        :disabled="pending"
        @click="changeType(kind)"
        >{{ t(`brainstormingDecisions.sourceTypes.${kind}`) }}</Button
      ><Button
        class="ml-auto"
        size="icon-sm"
        variant="ghost"
        :aria-label="t('brainstormingDecisions.closePicker')"
        @click="emit('close')"
        ><X class="size-3.5"
      /></Button>
    </div>
    <form id="decision-source-search-form" class="flex gap-1.5" @submit.prevent="search()">
      <label for="decision-source-query" class="sr-only">{{
        t("brainstormingDecisions.searchSources")
      }}</label
      ><Input
        id="decision-source-query"
        ref="searchInput"
        v-model="query"
        :maxlength="200"
        :placeholder="t('brainstormingDecisions.searchSources')"
        :disabled="pending"
      /><Button
        id="decision-source-search"
        type="submit"
        variant="outline"
        size="icon"
        :disabled="pending"
        :aria-label="t('brainstormingDecisions.searchSources')"
        ><Loader2 v-if="pending" class="size-4 animate-spin" /><Search v-else class="size-4"
      /></Button>
    </form>
    <p v-if="!searched" class="text-xs text-muted-foreground">
      {{ t("brainstormingDecisions.searchHelp") }}
    </p>
    <p v-else-if="!visible.length" class="text-xs text-muted-foreground">
      {{ t("brainstormingDecisions.noSourceResults") }}
    </p>
    <ul class="max-h-64 space-y-1 overflow-y-auto">
      <li v-for="source in visible" :key="source.identity">
        <button
          :id="`decision-source-option-${source.type}-${source.id ?? source.identity}`"
          type="button"
          class="flex w-full items-start gap-2 rounded-md px-2 py-2 text-left transition-colors hover:bg-accent disabled:opacity-50"
          :aria-pressed="selected(source)"
          :disabled="pending || selected(source) || !source.available || sources.length >= 20"
          @click="emit('select', source)"
        >
          <Check v-if="selected(source)" class="mt-0.5 size-4 shrink-0 text-primary" /><Layers
            v-else-if="source.type === 'group'"
            class="mt-0.5 size-4 shrink-0 text-muted-foreground"
          /><StickyNote v-else class="mt-0.5 size-4 shrink-0 text-muted-foreground" /><span
            class="min-w-0"
            ><span class="block break-words text-xs font-medium">{{
              source.available
                ? source.title || t("brainstormingDecisions.untitledSource")
                : t("brainstormingDecisions.sourceUnavailable")
            }}</span
            ><span
              v-if="source.available"
              class="mt-0.5 line-clamp-2 block text-[11px] text-muted-foreground"
              >{{ source.preview }}</span
            ></span
          >
        </button>
      </li>
    </ul>
    <div v-if="currentQuery && (previous.length || nextCursor !== null)" class="flex gap-2">
      <Button
        v-if="previous.length"
        id="decision-source-previous"
        size="sm"
        variant="outline"
        :disabled="pending"
        @click="search(previous[previous.length - 1], previous.slice(0, -1))"
        >{{ t("brainstormingDecisions.previousSources") }}</Button
      ><Button
        v-if="nextCursor !== null"
        id="decision-source-next"
        size="sm"
        variant="outline"
        class="ml-auto"
        :disabled="pending"
        @click="search(nextCursor, [...previous, cursor])"
        >{{ t("brainstormingDecisions.nextSources") }}</Button
      >
    </div>
  </section>
</template>
