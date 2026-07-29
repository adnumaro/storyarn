<script setup lang="ts">
import { FileText, GitBranch, Link, Map as MapIcon, type LucideIcon } from "lucide-vue-next";
import { injectListboxRootContext } from "reka-ui";
import { nextTick, ref } from "vue";
import { CommandGroup, CommandItem } from "@components/ui/command";
import {
  lookupResultAccessibleLabel,
  lookupResultSearchText,
  type PaletteLookupResult,
  type PaletteLookupResultIcon,
} from "@shared/command-palette/lookupResults";

const {
  items,
  heading,
  disabled = false,
  loading = false,
  truncated = false,
  truncatedLabel,
} = defineProps<{
  items: readonly PaletteLookupResult[];
  heading?: string;
  disabled?: boolean;
  loading?: boolean;
  truncated?: boolean;
  truncatedLabel?: string;
}>();

const emit = defineEmits<{
  select: [result: PaletteLookupResult];
}>();

const icons: Record<PaletteLookupResultIcon, LucideIcon> = {
  sheet: FileText,
  flow: GitBranch,
  scene: MapIcon,
  reference: Link,
};

const rootElement = ref<HTMLElement | null>(null);
const listboxRoot = injectListboxRootContext();

function resultIcon(result: PaletteLookupResult): LucideIcon {
  return icons[result.icon ?? "reference"];
}

function selectResult(result: PaletteLookupResult): void {
  if (disabled) return;
  emit("select", result);
}

function highlightedResultId(): string | null {
  return listboxRoot.highlightedElement.value?.dataset.lookupResultId ?? null;
}

async function highlightFirstResult(): Promise<void> {
  await nextTick();
  if (listboxRoot.highlightedElement.value?.isConnected) return;
  listboxRoot.highlightFirstItem();
  await nextTick();
}

async function restoreHighlightedResult(resultId: string | null): Promise<void> {
  await nextTick();

  const preferred = resultId
    ? Array.from(
        rootElement.value?.querySelectorAll<HTMLElement>("[data-lookup-result-id]") ?? [],
      ).find((element) => element.dataset.lookupResultId === resultId)
    : null;

  if (preferred) {
    listboxRoot.changeHighlight(preferred, false, false);
    return;
  }

  listboxRoot.highlightFirstItem();
  await nextTick();
}

defineExpose({
  highlightedResultId,
  highlightFirstResult,
  restoreHighlightedResult,
});
</script>

<template>
  <div
    ref="rootElement"
    class="contents"
    :aria-busy="loading"
    :data-lookup-results-truncated="truncated"
  >
    <CommandGroup v-if="items.length > 0" :heading="heading">
      <CommandItem
        v-for="result in items"
        :key="`${result.id}:${disabled ? 'disabled' : 'enabled'}`"
        :value="`lookup-result-${result.id}`"
        :data-lookup-result-id="result.id"
        :search-text="lookupResultSearchText(result)"
        :disabled="disabled"
        :aria-label="lookupResultAccessibleLabel(result)"
        class="items-start py-2"
        @select="selectResult(result)"
      >
        <component :is="resultIcon(result)" class="mt-0.5 size-4 shrink-0" />
        <span class="min-w-0 flex-1">
          <span class="block truncate font-medium">{{ result.label }}</span>
          <span
            v-if="result.detail || result.context"
            class="mt-0.5 flex min-w-0 items-center gap-1.5 text-xs text-muted-foreground"
          >
            <span v-if="result.detail" class="shrink-0">{{ result.detail }}</span>
            <span v-if="result.detail && result.context" aria-hidden="true">·</span>
            <span v-if="result.context" class="truncate">{{ result.context }}</span>
          </span>
        </span>
      </CommandItem>
    </CommandGroup>
    <p
      v-if="truncated && truncatedLabel"
      role="status"
      class="border-t px-3 py-2 text-xs text-muted-foreground"
    >
      {{ truncatedLabel }}
    </p>
  </div>
</template>
