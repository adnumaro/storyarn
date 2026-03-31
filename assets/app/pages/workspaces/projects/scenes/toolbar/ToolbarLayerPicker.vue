<script setup>
import { Layers } from "lucide-vue-next";
import { ref } from "vue";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";

const props = defineProps({
  layerId: { type: [Number, null], default: null },
  layers: { type: Array, default: () => [] },
  disabled: { type: Boolean, default: false },
});

const emit = defineEmits(["update:layerId"]);
const open = ref(false);

function selectLayer(id) {
  emit("update:layerId", id);
  open.value = false;
}
</script>

<template>
  <Popover v-model:open="open">
    <PopoverTrigger as-child>
      <button type="button" class="v2-toolbar-btn" :disabled="disabled" title="Layer">
        <Layers class="size-3.5" />
      </button>
    </PopoverTrigger>
    <PopoverContent class="w-auto p-1" :side-offset="8" side="top">
      <div class="flex flex-col gap-0.5 min-w-[120px]">
        <button
          type="button"
          class="px-2 py-1 text-xs text-left rounded cursor-pointer transition-colors"
          :class="layerId === null ? 'bg-primary text-primary-foreground' : 'hover:bg-muted'"
          @click="selectLayer(null)"
        >
          None
        </button>
        <button
          v-for="layer in layers"
          :key="layer.id"
          type="button"
          class="px-2 py-1 text-xs text-left rounded cursor-pointer transition-colors"
          :class="layer.id === layerId ? 'bg-primary text-primary-foreground' : 'hover:bg-muted'"
          @click="selectLayer(layer.id)"
        >
          {{ layer.name }}
        </button>
      </div>
    </PopoverContent>
  </Popover>
</template>
