<script setup lang="ts">
/**
 * Custom context menu renderer for rete-context-menu-plugin.
 *
 * Wired via the render preset in `lib/context_menu_preset.ts`. Receives
 * `items` (list of FlowContextMenuItem), `onHide` callback, and an optional
 * `searchBar` flag. Replaces rete-vue-plugin's default Menu with
 * shadcn-styled markup to match the rest of the editor chrome.
 *
 * 4c1-plus scope: no subitems (flat list only). Subitems land in 4c2.
 *
 * @see docs/audit/flow-context-menu-broken-after-vue-migration.md
 */

import { onBeforeUnmount, onMounted } from "vue";
import type { FlowContextMenuItem } from "../lib/context_menu_items";

const { items = [], onHide = () => {} } = defineProps<{
  items: FlowContextMenuItem[];
  onHide: () => void;
  searchBar?: boolean;
}>();

function invoke(item: FlowContextMenuItem) {
  item.handler();
  onHide();
}

function onKeydown(e: KeyboardEvent) {
  if (e.key === "Escape") {
    e.stopPropagation();
    onHide();
  }
}

onMounted(() => {
  document.addEventListener("keydown", onKeydown);
});

onBeforeUnmount(() => {
  document.removeEventListener("keydown", onKeydown);
});
</script>

<template>
  <div class="flow-context-menu" data-testid="flow-context-menu" @pointerdown.stop @click.stop>
    <button
      v-for="item in items"
      :key="item.key"
      type="button"
      class="flow-context-menu-item"
      :class="{ 'is-destructive': item.key === 'delete' }"
      :data-key="item.key"
      @click="invoke(item)"
    >
      <component :is="item.icon" v-if="item.icon" class="size-3.5 opacity-60" />
      <span>{{ item.label }}</span>
    </button>
  </div>
</template>

<style scoped>
.flow-context-menu {
  min-width: 12rem;
  background: hsl(var(--background));
  border: 1px solid hsl(var(--border));
  border-radius: 0.5rem;
  box-shadow: 0 10px 30px -10px rgba(0, 0, 0, 0.35);
  padding: 0.25rem;
  font-size: 0.8125rem;
  user-select: none;
}

.flow-context-menu-item {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  width: 100%;
  padding: 0.375rem 0.625rem;
  text-align: left;
  background: none;
  border: none;
  border-radius: 0.3125rem;
  color: hsl(var(--foreground));
  cursor: pointer;
  transition: background-color 0.1s ease;
}

.flow-context-menu-item:hover,
.flow-context-menu-item:focus-visible {
  background-color: hsl(var(--accent));
  outline: none;
}

.flow-context-menu-item.is-destructive {
  color: hsl(var(--destructive));
}

.flow-context-menu-item.is-destructive:hover,
.flow-context-menu-item.is-destructive:focus-visible {
  background-color: hsl(var(--destructive) / 0.1);
}
</style>
