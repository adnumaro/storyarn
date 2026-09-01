<script setup lang="ts">
/**
 * Props-driven facade over the app's DropdownMenu compound.
 * The React children become the trigger; items describe the menu.
 */
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuShortcut,
  DropdownMenuTrigger,
} from "@components/ui/dropdown-menu";
import { useContentThemeClass } from "./useDsTheme";

export interface DropdownItem {
  /** Emitted with select when clicked; defaults to label. */
  value?: string;
  label?: string;
  /** "item" (default), "label" or "separator". */
  type?: "item" | "label" | "separator";
  shortcut?: string;
  disabled?: boolean;
  destructive?: boolean;
}

const {
  items = [],
  side = "bottom",
  align = "start",
} = defineProps<{
  items?: DropdownItem[];
  side?: "top" | "right" | "bottom" | "left";
  align?: "start" | "center" | "end";
}>();

const emit = defineEmits<{ select: [value: string] }>();

const themeClass = useContentThemeClass();
</script>

<template>
  <DropdownMenu>
    <DropdownMenuTrigger as-child>
      <slot />
    </DropdownMenuTrigger>
    <DropdownMenuContent :side="side" :align="align" :class="themeClass">
      <template v-for="(item, i) in items" :key="i">
        <DropdownMenuSeparator v-if="item.type === 'separator'" />
        <DropdownMenuLabel v-else-if="item.type === 'label'">{{ item.label }}</DropdownMenuLabel>
        <DropdownMenuItem
          v-else
          :disabled="item.disabled"
          :variant="item.destructive ? 'destructive' : undefined"
          @select="emit('select', item.value ?? item.label ?? '')"
        >
          {{ item.label }}
          <DropdownMenuShortcut v-if="item.shortcut">{{ item.shortcut }}</DropdownMenuShortcut>
        </DropdownMenuItem>
      </template>
    </DropdownMenuContent>
  </DropdownMenu>
</template>
