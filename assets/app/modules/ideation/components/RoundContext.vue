<script setup lang="ts">
import { ChevronDown } from "@lucide/vue";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";
import { useBoardText } from "../composables/useBoardText";
import type { Round } from "../types";

defineProps<{ round: Round }>();
const { t } = useBoardText();
</script>
<template>
  <div
    id="brainstorming-round-context"
    class="flex min-w-0 items-center gap-3 border-b bg-muted/20 px-4 py-2 text-xs"
  >
    <span class="shrink-0 font-medium text-primary">{{
      t("ideation.rounds.number", { number: round.number })
    }}</span>
    <Popover>
      <PopoverTrigger as-child>
        <button
          id="brainstorming-round-context-trigger"
          type="button"
          class="flex min-w-0 items-center gap-2 rounded-sm text-left text-muted-foreground transition-colors hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
          :aria-label="`${t('ideation.rounds.context')}: ${round.prompt}`"
        >
          <span class="truncate">{{ round.prompt }}</span>
          <ChevronDown class="size-3 shrink-0" />
        </button>
      </PopoverTrigger>
      <PopoverContent align="start" class="w-96 max-w-[calc(100vw-2rem)]">
        <h2 class="mb-2 text-xs font-medium">{{ t("ideation.rounds.context") }}</h2>
        <p class="max-h-64 overflow-y-auto whitespace-pre-wrap break-words text-sm leading-relaxed">
          {{ round.prompt }}
        </p>
      </PopoverContent>
    </Popover>
  </div>
</template>
