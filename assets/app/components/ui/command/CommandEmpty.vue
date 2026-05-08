<script setup lang="ts">
import type { Component, HTMLAttributes } from "vue";
import { reactiveOmit } from "@vueuse/core";
import { Primitive, type AsTag } from "reka-ui";
import { computed } from "vue";
import { cn } from "../../../shared/utils/utils";
import { useCommand } from ".";

const props = defineProps<{
  asChild?: boolean;
  as?: AsTag | Component;
  class?: HTMLAttributes["class"];
}>();

const delegatedProps = reactiveOmit(props, "class");

const { filterState } = useCommand();
const isRender = computed(() => !!filterState.search && filterState.filtered.count === 0);
</script>

<template>
  <Primitive
    v-if="isRender"
    data-slot="command-empty"
    v-bind="delegatedProps"
    :class="cn('py-6 text-center text-sm', props.class)"
  >
    <slot />
  </Primitive>
</template>
