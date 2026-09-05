<script setup lang="ts">
import { LoaderCircle, Search } from "@lucide/vue";
import { onBeforeUnmount, onMounted, ref, watch } from "vue";
import { Button } from "@components/ui/button";
import type { TextRow } from "../../domain/types";
import StringRow from "./StringRow.vue";

/**
 * The full-height list of strings. Loads the next page as the translator
 * scrolls (and through a button for keyboards and small screens); ↑/↓ move
 * between rows, Enter opens the focused one.
 */
const {
  texts,
  selectedId = null,
  totalCount,
  hasMore = false,
  loadingMore = false,
  canTranslate = false,
  translating = false,
  selectedPosition = null,
} = defineProps<{
  texts: TextRow[];
  selectedId?: number | null;
  totalCount: number;
  hasMore?: boolean;
  loadingMore?: boolean;
  canTranslate?: boolean;
  translating?: boolean;
  selectedPosition?: number | null;
}>();

const emit = defineEmits<{
  select: [id: number];
  translate: [id: number];
  "load-more": [];
}>();

const scroller = ref<HTMLElement | null>(null);
const sentinel = ref<HTMLElement | null>(null);
let observer: IntersectionObserver | null = null;

function requestMore(): void {
  if (hasMore && !loadingMore) emit("load-more");
}

onMounted(() => {
  if (typeof IntersectionObserver === "undefined" || !sentinel.value) return;
  observer = new IntersectionObserver(
    (entries) => {
      if (entries.some((entry) => entry.isIntersecting)) requestMore();
    },
    { root: scroller.value, rootMargin: "240px 0px" },
  );
  observer.observe(sentinel.value);
});

onBeforeUnmount(() => observer?.disconnect());

watch(
  () => selectedId,
  (id) => {
    if (id === null || !scroller.value) return;
    const row = scroller.value.querySelector<HTMLElement>(`[data-row-id="${id}"]`);
    row?.scrollIntoView({ block: "nearest" });
  },
);

function onKeydown(event: KeyboardEvent): void {
  if (event.key !== "ArrowDown" && event.key !== "ArrowUp") return;
  const rows = Array.from(scroller.value?.querySelectorAll<HTMLElement>("[data-row-id]") ?? []);
  if (rows.length === 0) return;

  const current = rows.findIndex((row) => row === document.activeElement);
  const delta = event.key === "ArrowDown" ? 1 : -1;
  const next = current === -1 ? 0 : Math.min(rows.length - 1, Math.max(0, current + delta));
  event.preventDefault();
  rows[next].focus();
}
</script>

<template>
  <section
    class="flex min-h-0 flex-col overflow-hidden rounded-lg border border-border bg-card"
    :aria-label="$t('localization.workbench.list_label')"
  >
    <slot name="filters" />

    <div
      class="flex items-center justify-between border-b border-border/60 px-4 py-1.5 text-xs text-muted-foreground"
    >
      <span>
        {{ $t("localization.workbench.count", totalCount) }}
        · {{ $t("localization.workbench.sorted") }}
      </span>
      <span v-if="selectedPosition !== null" class="tabular-nums">
        {{ $t("localization.workbench.position", { index: selectedPosition, total: totalCount }) }}
      </span>
    </div>

    <div
      ref="scroller"
      class="min-h-0 flex-1 overflow-y-auto overscroll-contain"
      data-testid="localization-string-list"
      @keydown="onKeydown"
    >
      <div
        v-if="texts.length === 0"
        class="flex h-full flex-col items-center justify-center gap-2 px-6 py-12 text-center"
      >
        <Search class="size-8 text-muted-foreground/40" />
        <p class="text-sm font-medium">{{ $t("localization.workbench.no_results") }}</p>
        <p class="text-xs text-muted-foreground">
          {{ $t("localization.workbench.no_results_hint") }}
        </p>
      </div>

      <template v-else>
        <StringRow
          v-for="text in texts"
          :key="text.id"
          :text="text"
          :selected="text.id === selectedId"
          :can-translate="canTranslate"
          :translating="translating"
          @select="emit('select', text.id)"
          @translate="emit('translate', text.id)"
        />
        <div ref="sentinel" class="h-px" aria-hidden="true" />
        <div v-if="hasMore" class="flex justify-center px-4 py-3">
          <Button variant="ghost" size="xs" :disabled="loadingMore" @click="requestMore">
            <LoaderCircle v-if="loadingMore" class="size-3.5 animate-spin" />
            {{
              loadingMore
                ? $t("localization.workbench.loading_more")
                : $t("localization.workbench.load_more")
            }}
          </Button>
        </div>
      </template>
    </div>

    <div
      class="flex items-center justify-between border-t border-border px-4 py-1.5 text-[11px] text-muted-foreground"
    >
      <span>{{ $t("localization.workbench.keys_hint") }}</span>
      <span>{{ $t("localization.workbench.loads_on_scroll") }}</span>
    </div>
  </section>
</template>
