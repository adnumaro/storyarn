<script setup lang="ts">
import { Layers } from "lucide-vue-next";
import { ref } from "vue";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";

interface Layer {
  id: number | string;
  name: string;
}

const {
  layerId = null,
  layers = [],
  disabled = false,
} = defineProps<{
  layerId?: number | string | null;
  layers?: Layer[];
  disabled?: boolean;
}>();

const emit = defineEmits<{
  "update:layerId": [value: number | string | null];
}>();
const open = ref(false);

function selectLayer(id: number | string | null) {
  emit("update:layerId", id);
  open.value = false;
}
</script>

<template>
  <Popover v-model:open="open">
    <PopoverTrigger as-child>
      <button
        type="button"
        class="toolbar-btn"
        :disabled="disabled"
        :title="$t('scenes.layer_picker.layer')"
      >
        <Layers class="size-3.5" />
      </button>
    </PopoverTrigger>
    <PopoverContent class="w-auto p-1" :side-offset="8" side="top">
      <div class="flex flex-col gap-0.5 min-w-30">
        <button
          type="button"
          class="px-2 py-1 text-xs text-left rounded cursor-pointer transition-colors"
          :class="layerId === null ? 'bg-primary text-primary-foreground' : 'hover:bg-muted'"
          @click="selectLayer(null)"
        >
          {{ $t("scenes.layer_picker.none") }}
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
