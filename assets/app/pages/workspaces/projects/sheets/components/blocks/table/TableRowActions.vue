<script setup>
import { GripVertical, Trash2 } from "lucide-vue-next";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover/index.js";
import { useLive } from "@composables/useLive.js";

const props = defineProps({
  row: { type: Object, required: true },
  rows: { type: Array, required: true },
  canManage: { type: Boolean, default: false },
});

const live = useLive();

function saveRowName(event) {
  const name = event.target.value.trim();
  if (name && name !== props.row.name) {
    live.pushEvent("rename_table_row", {
      "row-id": props.row.id,
      value: name,
    });
  }
}

function deleteRow() {
  live.pushEvent("delete_table_row", { "row-id": props.row.id });
}
</script>

<template>
  <!-- Row handle + menu (canManage only) -->
  <div
    v-if="canManage"
    class="absolute -left-[5px] top-1/2 -translate-y-1/2 z-20 opacity-0 group-hover/row:opacity-100 transition-opacity"
  >
    <Popover>
      <PopoverTrigger as-child>
        <button type="button" class="cursor-grab row-drag-handle p-0.5 rounded hover:bg-accent">
          <GripVertical class="size-3.5 text-muted-foreground/40" />
        </button>
      </PopoverTrigger>
      <PopoverContent align="start" :side-offset="4" class="w-36 p-1">
        <button
          :disabled="rows.length <= 1"
          class="flex items-center gap-2 w-full px-2 py-1.5 text-sm rounded-sm hover:bg-accent text-destructive disabled:opacity-30 disabled:pointer-events-none"
          @click="deleteRow()"
        >
          <Trash2 class="size-3.5" />
          <span>Delete</span>
        </button>
      </PopoverContent>
    </Popover>
  </div>

  <!-- Row name: editable input (canManage) -->
  <label v-if="canManage" class="block cursor-text px-3 py-2">
    <input
      type="text"
      :value="row.name"
      class="w-full px-0 py-0.5 text-sm font-medium bg-transparent border-0 outline-none"
      @blur="saveRowName($event)"
      @keydown.enter="saveRowName($event)"
    />
    <span class="text-[10px] text-muted-foreground/30 block">{{ row.slug }}</span>
  </label>

  <!-- Row name: read-only (inherited / viewer) -->
  <div v-else class="px-3 py-2">
    <span>{{ row.name }}</span>
    <div class="text-[10px] text-muted-foreground/30">{{ row.slug }}</div>
  </div>
</template>
