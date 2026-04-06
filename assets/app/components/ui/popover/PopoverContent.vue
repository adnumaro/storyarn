<script setup lang="ts">
import type { Component, HTMLAttributes } from "vue";
import { reactiveOmit } from "@vueuse/core";
import { PopoverContent, PopoverPortal, useForwardPropsEmits, type AsTag } from "reka-ui";
import { cn } from "@utils/utils";

defineOptions({
  inheritAttrs: false,
});

const props = defineProps<{
  forceMount?: boolean;
  side?: "top" | "right" | "bottom" | "left";
  sideOffset?: number;
  sideFlip?: boolean;
  align?: "start" | "center" | "end";
  alignOffset?: number;
  alignFlip?: boolean;
  avoidCollisions?: boolean;
  collisionBoundary?: Element | (Element | null)[] | null;
  collisionPadding?: number | Partial<Record<"top" | "right" | "bottom" | "left", number>>;
  arrowPadding?: number;
  hideShiftedArrow?: boolean;
  sticky?: "partial" | "always";
  hideWhenDetached?: boolean;
  positionStrategy?: "fixed" | "absolute";
  updatePositionStrategy?: "always" | "optimized";
  disableUpdateOnLayoutShift?: boolean;
  prioritizePosition?: boolean;
  reference?: HTMLElement | null;
  asChild?: boolean;
  as?: AsTag | Component;
  disableOutsidePointerEvents?: boolean;
  class?: HTMLAttributes["class"];
}>();
const emits = defineEmits<{
  escapeKeyDown: [event: KeyboardEvent];
  pointerDownOutside: [event: Event];
  focusOutside: [event: Event];
  interactOutside: [event: Event];
  openAutoFocus: [event: Event];
  closeAutoFocus: [event: Event];
}>();

const delegatedProps = reactiveOmit(props, "class");

const forwarded = useForwardPropsEmits(delegatedProps, emits);
</script>

<template>
  <PopoverPortal class="popover">
    <PopoverContent
      data-slot="popover-content"
      v-bind="{ ...$attrs, ...forwarded }"
      :class="
        cn(
          'bg-popover text-popover-foreground data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:fade-in-0 data-[state=closed]:zoom-out-95 data-[state=open]:zoom-in-95 data-[side=bottom]:slide-in-from-top-2 data-[side=left]:slide-in-from-right-2 data-[side=right]:slide-in-from-left-2 data-[side=top]:slide-in-from-bottom-2 z-50 w-72 rounded-md border p-4 shadow-md origin-(--reka-popover-content-transform-origin) outline-hidden',
          props.class,
        )
      "
    >
      <slot />
    </PopoverContent>
  </PopoverPortal>
</template>
