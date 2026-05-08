<script setup lang="ts">
import type { Component, HTMLAttributes } from "vue";
import { reactiveOmit } from "@vueuse/core";
import {
  SelectContent,
  SelectPortal,
  SelectViewport,
  useForwardPropsEmits,
  type AsTag,
} from "reka-ui";
import { cn } from "../../../shared/utils/utils";
import { SelectScrollDownButton, SelectScrollUpButton } from ".";

defineOptions({
  inheritAttrs: false,
});

const props = defineProps<{
  forceMount?: boolean;
  position?: "item-aligned" | "popper";
  bodyLock?: boolean;
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
  reference?: HTMLElement;
  asChild?: boolean;
  as?: AsTag | Component;
  disableOutsidePointerEvents?: boolean;
  class?: HTMLAttributes["class"];
}>();
const emits = defineEmits<{
  closeAutoFocus: [event: Event];
  escapeKeyDown: [event: KeyboardEvent];
  pointerDownOutside: [event: Event];
}>();

const delegatedProps = reactiveOmit(props, "class");

const forwarded = useForwardPropsEmits(delegatedProps, emits);
</script>

<template>
  <SelectPortal>
    <SelectContent
      data-slot="select-content"
      v-bind="{ ...$attrs, ...forwarded }"
      :class="
        cn(
          'bg-popover text-popover-foreground data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:fade-in-0 data-[state=closed]:zoom-out-95 data-[state=open]:zoom-in-95 data-[side=bottom]:slide-in-from-top-2 data-[side=left]:slide-in-from-right-2 data-[side=right]:slide-in-from-left-2 data-[side=top]:slide-in-from-bottom-2 relative z-50 max-h-(--reka-select-content-available-height) min-w-[8rem] overflow-x-hidden overflow-y-auto rounded-md border shadow-md',
          position === 'popper' &&
            'data-[side=bottom]:translate-y-1 data-[side=left]:-translate-x-1 data-[side=right]:translate-x-1 data-[side=top]:-translate-y-1',
          props.class,
        )
      "
    >
      <SelectScrollUpButton />
      <SelectViewport
        :class="
          cn(
            'p-1',
            position === 'popper' &&
              'h-[var(--reka-select-trigger-height)] w-full min-w-[var(--reka-select-trigger-width)] scroll-my-1',
          )
        "
      >
        <slot />
      </SelectViewport>
      <SelectScrollDownButton />
    </SelectContent>
  </SelectPortal>
</template>
