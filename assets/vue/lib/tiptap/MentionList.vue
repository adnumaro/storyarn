<script setup>
import { FileText, Zap } from "lucide-vue-next";
import { ref, watch } from "vue";

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
		selectedIndex.value =
			(selectedIndex.value - 1 + props.items.length) % props.items.length;
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
  <div v-if="items.length > 0" class="bg-popover border border-border rounded-lg shadow-lg p-1 max-h-60 overflow-y-auto min-w-[200px] max-w-[300px]">
    <button
      v-for="(item, index) in items"
      :key="item.id"
      type="button"
      class="w-full text-left px-2 py-1.5 rounded flex items-center gap-2 text-sm transition-colors"
      :class="index === selectedIndex ? 'bg-primary/20' : 'hover:bg-accent'"
      @click="selectItem(index)"
    >
      <span class="flex-shrink-0 size-5 rounded flex items-center justify-center text-xs"
        :class="item.type === 'sheet' ? 'bg-primary/20 text-primary' : 'bg-violet-500/20 text-violet-500'"
      >
        <FileText v-if="item.type === 'sheet'" class="size-3.5" />
        <Zap v-else class="size-3.5" />
      </span>
      <span class="truncate">{{ item.name }}</span>
      <span v-if="item.shortcut" class="text-muted-foreground text-xs ml-auto">#{{ item.shortcut }}</span>
    </button>
  </div>
  <div v-else class="bg-popover border border-border rounded-lg shadow-lg p-1">
    <div class="text-muted-foreground text-sm px-3 py-2">No results found</div>
  </div>
</template>
