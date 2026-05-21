<script setup lang="ts">
import { Layers } from "lucide-vue-next";
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import { Popover, PopoverAnchor, PopoverContent, PopoverTrigger } from "@components/ui/popover";
import ToolbarTooltip from "@components/toolbar/ToolbarTooltip.vue";

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
const { t } = useI18n();

const selectedLayer = computed(() => {
  if (layerId == null) {
    return null;
  }

  return layers.find((layer) => String(layer.id) === String(layerId)) ?? null;
});

const selectedLayerLabel = computed(
  () => selectedLayer.value?.name ?? t("scenes.layer_picker.none"),
);
const tooltipLabel = computed(
  () => `${t("scenes.layer_picker.layer")}: ${selectedLayerLabel.value}`,
);

function isSelected(id: number | string | null): boolean {
  if (id == null) {
    return layerId == null;
  }

  return String(id) === String(layerId);
}

function selectLayer(id: number | string | null) {
  emit("update:layerId", id);
  open.value = false;
}
</script>

<template>
  <Popover v-model:open="open">
    <PopoverAnchor as-child>
      <ToolbarTooltip :label="tooltipLabel">
        <PopoverTrigger
          class="toolbar-btn gap-1.5 max-w-36 px-1.5"
          :disabled="disabled"
          :aria-label="tooltipLabel"
          :title="tooltipLabel"
        >
          <Layers class="size-3.5 shrink-0" />
          <span class="min-w-0 max-w-24 truncate text-xs">
            {{ selectedLayerLabel }}
          </span>
        </PopoverTrigger>
      </ToolbarTooltip>
    </PopoverAnchor>
    <PopoverContent class="w-auto p-1" :side-offset="8" side="top">
      <div class="flex flex-col gap-0.5 min-w-30">
        <button
          type="button"
          class="px-2 py-1 text-xs text-left rounded cursor-pointer transition-colors"
          :class="isSelected(null) ? 'bg-primary text-primary-foreground' : 'hover:bg-muted'"
          @click="selectLayer(null)"
        >
          {{ $t("scenes.layer_picker.none") }}
        </button>
        <button
          v-for="layer in layers"
          :key="layer.id"
          type="button"
          class="px-2 py-1 text-xs text-left rounded cursor-pointer transition-colors"
          :class="isSelected(layer.id) ? 'bg-primary text-primary-foreground' : 'hover:bg-muted'"
          @click="selectLayer(layer.id)"
        >
          {{ layer.name }}
        </button>
      </div>
    </PopoverContent>
  </Popover>
</template>
