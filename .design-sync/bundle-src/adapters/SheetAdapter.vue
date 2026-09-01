<script setup lang="ts">
/**
 * Props-driven facade over the app's Sheet (side panel) compound.
 * Children = panel body; `footer` slot renders in SheetFooter.
 */
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetFooter,
  SheetHeader,
  SheetTitle,
} from "@components/ui/sheet";
import { useContentThemeClass } from "./useDsTheme";

const {
  title,
  description,
  side = "right",
} = defineProps<{
  title?: string;
  description?: string;
  side?: "top" | "right" | "bottom" | "left";
  contentClass?: string;
}>();

const open = defineModel<boolean>("open", { default: false });

const themeClass = useContentThemeClass();
</script>

<template>
  <Sheet v-model:open="open">
    <SheetContent :side="side" :class="[themeClass, contentClass]">
      <SheetHeader v-if="title || description">
        <SheetTitle v-if="title">{{ title }}</SheetTitle>
        <SheetDescription v-if="description">{{ description }}</SheetDescription>
      </SheetHeader>
      <slot />
      <SheetFooter v-if="$slots.footer">
        <slot name="footer" />
      </SheetFooter>
    </SheetContent>
  </Sheet>
</template>
