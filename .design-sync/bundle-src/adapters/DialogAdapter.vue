<script setup lang="ts">
/**
 * Props-driven facade over the app's generic Dialog compound.
 * Children = body; the `footer` slot (a React prop) renders in DialogFooter.
 * For confirm/cancel flows prefer ConfirmDialog — the real product dialog.
 */
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@components/ui/dialog";
import { useContentThemeClass } from "./useDsTheme";

const { title, description } = defineProps<{
  title?: string;
  description?: string;
  contentClass?: string;
}>();

const open = defineModel<boolean>("open", { default: false });

const themeClass = useContentThemeClass();
</script>

<template>
  <Dialog v-model:open="open">
    <DialogContent :class="[themeClass, contentClass]">
      <DialogHeader v-if="title || description">
        <DialogTitle v-if="title">{{ title }}</DialogTitle>
        <DialogDescription v-if="description">{{ description }}</DialogDescription>
      </DialogHeader>
      <slot />
      <DialogFooter v-if="$slots.footer">
        <slot name="footer" />
      </DialogFooter>
    </DialogContent>
  </Dialog>
</template>
