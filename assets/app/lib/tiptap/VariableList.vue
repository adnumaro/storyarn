<script setup>
import { Calendar, Hash, List, ToggleLeft, Type } from "lucide-vue-next";
import { ref, watch } from "vue";

const TYPE_ICONS = {
  number: Hash,
  text: Type,
  rich_text: Type,
  boolean: ToggleLeft,
  select: List,
  multi_select: List,
  date: Calendar,
};

const props = defineProps({
  items: { type: Array, default: () => [] },
  command: { type: Function, required: true },
});

const selectedIndex = ref(0);

watch(
  () => props.items,
  () => {
    selectedIndex.value = 0;
  },
);

function selectItem(index) {
  const item = props.items[index];
  if (item) props.command(item);
}

function onKeyDown({ event }) {
  if (event.key === "ArrowUp") {
    selectedIndex.value = (selectedIndex.value - 1 + props.items.length) % props.items.length;
    return true;
  }
  if (event.key === "ArrowDown") {
    selectedIndex.value = (selectedIndex.value + 1) % props.items.length;
    return true;
  }
  if (event.key === "Enter") {
    selectItem(selectedIndex.value);
    return true;
  }
  return false;
}

defineExpose({ onKeyDown });
</script>

<template>
  <div
    v-if="items.length > 0"
    class="bg-popover border border-border rounded-lg shadow-lg p-1 max-h-60 overflow-y-auto min-w-[200px] max-w-[300px]"
  >
    <button
      v-for="(item, index) in items"
      :key="item.id || item.ref"
      type="button"
      class="w-full text-left px-2 py-1.5 rounded flex items-center gap-2 text-sm transition-colors"
      :class="index === selectedIndex ? 'bg-primary/20' : 'hover:bg-accent'"
      @click="selectItem(index)"
    >
      <component :is="TYPE_ICONS[item.block_type] || Hash" class="size-3.5 shrink-0 opacity-60" />
      <span class="truncate">{{ item.label || item.ref }}</span>
      <span v-if="item.sheet_name" class="text-muted-foreground text-xs ml-auto">{{
        item.sheet_name
      }}</span>
    </button>
  </div>
  <div v-else class="bg-popover border border-border rounded-lg shadow-lg p-1">
    <div class="text-muted-foreground text-sm px-3 py-2">No variables found</div>
  </div>
</template>
