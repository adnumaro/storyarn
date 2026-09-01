<script setup lang="ts">
/**
 * Props-driven facade over the app's Popover compound.
 * Children = trigger; the `content` slot (a React prop) is the floating panel.
 */
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";
import { useContentThemeClass } from "./useDsTheme";

const {
  side = "bottom",
  align = "center",
} = defineProps<{
  side?: "top" | "right" | "bottom" | "left";
  align?: "start" | "center" | "end";
  contentClass?: string;
}>();

const open = defineModel<boolean>("open", { default: undefined });

const themeClass = useContentThemeClass();
</script>

<template>
  <Popover v-model:open="open">
    <PopoverTrigger class="inline-flex">
      <slot />
    </PopoverTrigger>
    <PopoverContent :side="side" :align="align" :class="[themeClass, contentClass]">
      <slot name="content" />
    </PopoverContent>
  </Popover>
</template>
