<script setup lang="ts">
import { FileText, Zap } from "lucide-vue-next";
import { ref, watch } from "vue";

interface MentionItem {
  id: string | number;
  type: "sheet" | "flow";
  name: string;
  shortcut?: string;
}

const { items = [], command } = defineProps<{
  items?: MentionItem[];
  command: (item: MentionItem) => void;
}>();

const selectedIndex = ref(0);

watch(
  () => items,
  () => {
    selectedIndex.value = 0;
  },
);

function selectItem(index: number) {
  const item = items[index];
  if (item) command(item);
}

function onKeyDown({ event }: { event: KeyboardEvent }) {
  if (event.key === "ArrowUp") {
    selectedIndex.value = (selectedIndex.value - 1 + items.length) % items.length;
    return true;
  }
  if (event.key === "ArrowDown") {
    selectedIndex.value = (selectedIndex.value + 1) % items.length;
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
    class="bg-popover border border-border rounded-lg shadow-lg p-1 max-h-60 overflow-y-auto min-w-50 max-w-75"
  >
    <button
      v-for="(item, index) in items"
      :key="item.id"
      type="button"
      class="w-full text-left px-2 py-1.5 rounded flex items-center gap-2 text-sm transition-colors"
      :class="index === selectedIndex ? 'bg-primary/20' : 'hover:bg-accent'"
      @click="selectItem(index)"
    >
      <span
        class="shrink-0 size-5 rounded flex items-center justify-center text-xs"
        :class="
          item.type === 'sheet' ? 'bg-primary/20 text-primary' : 'bg-violet-500/20 text-violet-500'
        "
      >
        <FileText v-if="item.type === 'sheet'" class="size-3.5" />
        <Zap v-else class="size-3.5" />
      </span>
      <span class="truncate">{{ item.name }}</span>
      <span v-if="item.shortcut" class="text-muted-foreground text-xs ml-auto"
        >#{{ item.shortcut }}</span
      >
    </button>
  </div>
  <div v-else class="bg-popover border border-border rounded-lg shadow-lg p-1">
    <div class="text-muted-foreground text-sm px-3 py-2">{{ $t("common.mention_list.no_results") }}</div>
  </div>
</template>
