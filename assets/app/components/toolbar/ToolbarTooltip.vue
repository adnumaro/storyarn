<script setup lang="ts">
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@components/ui/tooltip";

const { side = "bottom", align = "center" } = defineProps<{
  label: string;
  side?: "top" | "right" | "bottom" | "left";
  align?: "start" | "center" | "end";
}>();
</script>

<template>
  <TooltipProvider :delay-duration="300">
    <Tooltip :disable-closing-trigger="true">
      <TooltipTrigger as-child>
        <span class="inline-flex">
          <slot />
        </span>
      </TooltipTrigger>
      <TooltipContent :side="side" :align="align">
        {{ label }}
      </TooltipContent>
    </Tooltip>
  </TooltipProvider>
</template>
