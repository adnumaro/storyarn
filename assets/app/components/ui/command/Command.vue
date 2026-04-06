<script setup lang="ts">
import type { Component, HTMLAttributes } from "vue";
import { reactiveOmit } from "@vueuse/core";
import { ListboxRoot, useFilter, useForwardPropsEmits, type AsTag } from "reka-ui";
import { reactive, ref, watch } from "vue";
import { cn } from "@utils/utils";
import { provideCommandContext } from ".";

const props = defineProps<{
  modelValue?: string | string[];
  defaultValue?: string | string[];
  multiple?: boolean;
  orientation?: "horizontal" | "vertical";
  dir?: "ltr" | "rtl";
  disabled?: boolean;
  selectionBehavior?: "toggle" | "replace";
  highlightOnHover?: boolean;
  by?: string | ((a: string, b: string) => boolean);
  asChild?: boolean;
  as?: AsTag | Component;
  name?: string;
  required?: boolean;
  class?: HTMLAttributes["class"];
}>();

const emits = defineEmits<{
  "update:modelValue": [value: string | string[]];
  highlight: [event: Event];
  entryFocus: [event: Event];
  leave: [event: Event];
}>();

const delegatedProps = reactiveOmit(props, "class");

const forwarded = useForwardPropsEmits(delegatedProps, emits);

const allItems = ref(new Map<string, string>());
const allGroups = ref(new Map<string, Set<string>>());

const { contains } = useFilter({ sensitivity: "base" });
const filterState = reactive({
  search: "",
  filtered: {
    /** The count of all visible items. */
    count: 0,
    /** Map from visible item id to its search score. */
    items: new Map<string, number>(),
    /** Set of groups with at least one visible item. */
    groups: new Set<string>(),
  },
});

function filterItems() {
  if (!filterState.search) {
    filterState.filtered.count = allItems.value.size;
    // Do nothing, each item will know to show itself because search is empty
    return;
  }

  // Reset the groups
  filterState.filtered.groups = new Set();
  let itemCount = 0;

  // Check which items should be included
  for (const [id, value] of allItems.value) {
    const score = contains(value, filterState.search);
    filterState.filtered.items.set(id, score ? 1 : 0);
    if (score) itemCount++;
  }

  // Check which groups have at least 1 item shown
  for (const [groupId, group] of allGroups.value) {
    for (const itemId of group) {
      if (filterState.filtered.items.get(itemId) > 0) {
        filterState.filtered.groups.add(groupId);
        break;
      }
    }
  }

  filterState.filtered.count = itemCount;
}

watch(
  () => filterState.search,
  () => {
    filterItems();
  },
);

provideCommandContext({
  allItems,
  allGroups,
  filterState,
});
</script>

<template>
  <ListboxRoot
    data-slot="command"
    v-bind="forwarded"
    :class="
      cn(
        'bg-popover text-popover-foreground flex h-full w-full flex-col overflow-hidden rounded-md',
        props.class,
      )
    "
  >
    <slot />
  </ListboxRoot>
</template>
