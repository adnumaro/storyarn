<script setup lang="ts">
/**
 * Props-driven facade over the app's Tooltip compound (provider included).
 * Children = trigger; `content` is plain text.
 */
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@components/ui/tooltip";
import { useContentThemeClass } from "./useDsTheme";

const {
  content,
  side = "top",
  open = undefined,
} = defineProps<{
  content: string;
  side?: "top" | "right" | "bottom" | "left";
  /** Force visibility (useful in static previews). */
  open?: boolean;
}>();

const themeClass = useContentThemeClass();
</script>

<template>
  <TooltipProvider :delay-duration="200">
    <Tooltip :open="open">
      <TooltipTrigger as-child>
        <slot />
      </TooltipTrigger>
      <TooltipContent :side="side" :class="themeClass">{{ content }}</TooltipContent>
    </Tooltip>
  </TooltipProvider>
</template>
