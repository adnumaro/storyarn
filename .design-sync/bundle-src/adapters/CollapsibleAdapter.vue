<script setup lang="ts">
/**
 * Props-driven facade over the app's Collapsible compound.
 * `trigger` is the toggle's text; children = the collapsible content.
 */
import { ChevronDown } from "@lucide/vue";
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from "@components/ui/collapsible";

const { trigger } = defineProps<{
  trigger: string;
  class?: string;
}>();

const open = defineModel<boolean>("open", { default: false });
</script>

<template>
  <Collapsible v-model:open="open" :class="$props.class">
    <CollapsibleTrigger
      class="flex w-full items-center justify-between gap-2 rounded-md px-2 py-1.5 text-sm font-medium hover:bg-accent"
    >
      {{ trigger }}
      <ChevronDown
        class="size-4 text-muted-foreground transition-transform"
        :class="{ 'rotate-180': open }"
      />
    </CollapsibleTrigger>
    <CollapsibleContent>
      <slot />
    </CollapsibleContent>
  </Collapsible>
</template>
