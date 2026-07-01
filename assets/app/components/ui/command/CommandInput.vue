<script setup lang="ts">
import type { Component, HTMLAttributes } from "vue";
import { reactiveOmit } from "@vueuse/core";
import { Search } from "lucide-vue-next";
import { ListboxFilter, useForwardProps, type AsTag } from "reka-ui";
import { computed, watch } from "vue";
import { cn } from "../../../shared/utils/utils";
import { useCommand } from "./context";

defineOptions({
  inheritAttrs: false,
});

const props = defineProps<{
  modelValue?: string;
  autoFocus?: boolean;
  disabled?: boolean;
  asChild?: boolean;
  as?: AsTag | Component;
  class?: HTMLAttributes["class"];
}>();
const emit = defineEmits<{
  "update:modelValue": [value: string];
}>();

const delegatedProps = reactiveOmit(props, "class");

const forwardedProps = useForwardProps(delegatedProps);

const { filterState } = useCommand();

const search = computed({
  get: () => filterState.search,
  set: (value: string) => {
    filterState.search = value;
    emit("update:modelValue", value);
  },
});

watch(
  () => props.modelValue,
  (value) => {
    if (value !== undefined && value !== filterState.search) {
      filterState.search = value;
    }
  },
  { immediate: true },
);
</script>

<template>
  <div data-slot="command-input-wrapper" class="flex h-9 items-center gap-2 border-b px-3">
    <Search class="size-4 shrink-0 opacity-50" />
    <ListboxFilter
      v-bind="{ ...forwardedProps, ...$attrs }"
      v-model="search"
      data-slot="command-input"
      auto-focus
      :class="
        cn(
          'placeholder:text-muted-foreground flex h-10 w-full rounded-md bg-transparent py-3 text-sm outline-hidden disabled:cursor-not-allowed disabled:opacity-50',
          props.class,
        )
      "
    />
  </div>
</template>
