<script setup lang="ts">
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import { CommandGroup, CommandItem } from "@components/ui/command";
import {
  advancedSearchVariableOperators,
  type AdvancedSearchPrefixDefinition,
  type AdvancedSearchPrefixSymbol,
} from "@shared/command-palette/advancedSearch";

const { definitions, selectedPrefix = null } = defineProps<{
  definitions: readonly AdvancedSearchPrefixDefinition[];
  selectedPrefix?: AdvancedSearchPrefixSymbol | null;
}>();

const emit = defineEmits<{
  select: [symbol: AdvancedSearchPrefixSymbol];
}>();

const { t } = useI18n();

const visibleDefinitions = computed<readonly AdvancedSearchPrefixDefinition[]>(() => {
  if (!selectedPrefix) return definitions;
  const selected = definitions.find((definition) => definition.symbol === selectedPrefix);
  return selected ? [selected] : [];
});

function searchText(definition: AdvancedSearchPrefixDefinition): string {
  return [
    definition.symbol,
    t(definition.labelKey),
    t(definition.descriptionKey),
    ...definition.examples,
  ].join(" ");
}
</script>

<template>
  <section
    data-testid="palette-advanced-search-help"
    :data-selected-prefix="selectedPrefix ?? undefined"
    class="border-b"
    :aria-label="t('palette.advanced_search.title')"
  >
    <div class="px-3 py-3">
      <p class="text-sm font-medium">{{ t("palette.advanced_search.title") }}</p>
      <p class="mt-0.5 text-xs leading-relaxed text-muted-foreground">
        {{ t("palette.advanced_search.description") }}
      </p>
    </div>

    <CommandGroup :heading="t('palette.advanced_search.prefixes_heading')">
      <CommandItem
        v-for="definition in visibleDefinitions"
        :key="definition.mode"
        :value="`advanced-search-prefix-${definition.mode}`"
        :search-text="searchText(definition)"
        :data-advanced-search-prefix="definition.symbol"
        :aria-current="definition.symbol === selectedPrefix ? 'true' : undefined"
        class="items-start py-2.5"
        @select="emit('select', definition.symbol)"
      >
        <kbd
          class="mt-0.5 flex size-6 shrink-0 items-center justify-center rounded-md border bg-muted font-mono text-xs font-semibold text-foreground shadow-xs"
        >
          {{ definition.symbol }}
        </kbd>

        <span class="min-w-0 flex-1">
          <span class="flex items-center gap-2 font-medium">
            <span>{{ t(definition.labelKey) }}</span>
            <span
              v-if="definition.cost === 'high'"
              class="rounded-full bg-amber-500/10 px-1.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-amber-700 dark:text-amber-300"
            >
              {{ t("palette.advanced_search.high_cost") }}
            </span>
          </span>

          <span class="mt-0.5 block text-xs leading-relaxed text-muted-foreground">
            {{ t(definition.descriptionKey) }}
          </span>

          <span class="mt-1.5 flex flex-wrap gap-1.5">
            <code
              v-for="example in definition.examples"
              :key="example"
              class="rounded bg-muted px-1.5 py-0.5 font-mono text-[11px] text-muted-foreground"
            >
              {{ example }}
            </code>
          </span>

          <span
            v-if="definition.trigger === 'submit'"
            class="mt-1.5 block text-[11px] font-medium text-muted-foreground"
          >
            {{
              t("palette.advanced_search.submit_hint", {
                count: definition.minimumLength,
              })
            }}
          </span>
        </span>
      </CommandItem>
    </CommandGroup>

    <div
      v-if="selectedPrefix === '$'"
      role="group"
      :aria-label="t('palette.advanced_search.variable_operators.heading')"
      class="border-t px-3 py-3"
    >
      <p class="px-1 text-xs font-medium text-muted-foreground">
        {{ t("palette.advanced_search.variable_operators.heading") }}
      </p>

      <div class="mt-2 grid gap-2">
        <div
          v-for="operator in advancedSearchVariableOperators"
          :key="operator.symbol"
          class="grid grid-cols-[minmax(8.5rem,auto)_1fr] gap-3 rounded-lg border bg-muted/30 px-3 py-2.5"
        >
          <code class="self-start font-mono text-xs font-medium text-foreground">
            {{ operator.example }}
          </code>

          <span class="min-w-0">
            <span class="block text-xs font-medium text-foreground">
              {{ t(operator.labelKey) }}
            </span>
            <span class="mt-0.5 block text-xs leading-relaxed text-muted-foreground">
              {{ t(operator.descriptionKey) }}
            </span>
          </span>
        </div>
      </div>
    </div>
  </section>
</template>
