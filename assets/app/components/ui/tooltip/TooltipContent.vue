<script setup lang="ts">
import type { Component, HTMLAttributes } from "vue";
import { reactiveOmit } from "@vueuse/core";
import {
  TooltipArrow,
  TooltipContent,
  TooltipPortal,
  useForwardPropsEmits,
  type AsTag,
} from "reka-ui";
import { cn } from "@utils/utils";

defineOptions({
  inheritAttrs: false,
});

const props = defineProps<{
  forceMount?: boolean;
  ariaLabel?: string;
  asChild?: boolean;
  as?: AsTag | Component;
  side?: "top" | "right" | "bottom" | "left";
  sideOffset?: number;
  align?: "start" | "center" | "end";
  alignOffset?: number;
  avoidCollisions?: boolean;
  collisionBoundary?: Element | (Element | null)[] | null;
  collisionPadding?: number | Partial<Record<"top" | "right" | "bottom" | "left", number>>;
  arrowPadding?: number;
  sticky?: "partial" | "always";
  hideWhenDetached?: boolean;
  positionStrategy?: "fixed" | "absolute";
  updatePositionStrategy?: "always" | "optimized";
  class?: HTMLAttributes["class"];
}>();

const emits = defineEmits<{
  escapeKeyDown: [event: KeyboardEvent];
  pointerDownOutside: [event: Event];
}>();

const delegatedProps = reactiveOmit(props, "class");
const forwarded = useForwardPropsEmits(delegatedProps, emits);
</script>

<template>
  <TooltipPortal>
    <TooltipContent
      data-slot="tooltip-content"
      v-bind="{ ...forwarded, ...$attrs }"
      :class="
        cn(
          'bg-foreground text-background animate-in fade-in-0 zoom-in-95 data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=closed]:zoom-out-95 data-[side=bottom]:slide-in-from-top-2 data-[side=left]:slide-in-from-right-2 data-[side=right]:slide-in-from-left-2 data-[side=top]:slide-in-from-bottom-2 z-50 w-fit rounded-md px-3 py-1.5 text-xs text-balance',
          props.class,
        )
      "
    >
      <slot />

      <TooltipArrow
        class="bg-foreground fill-foreground z-50 size-2.5 translate-y-[calc(-50%_-_2px)] rotate-45 rounded-[2px]"
      />
    </TooltipContent>
  </TooltipPortal>
</template>
