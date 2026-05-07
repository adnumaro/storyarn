<script setup lang="ts">
import { ref } from "vue";
import { Popover, PopoverAnchor, PopoverContent, PopoverTrigger } from "@components/ui/popover";
import ToolbarTooltip from "@components/toolbar/ToolbarTooltip.vue";

const SIZE_OPTIONS = [
  { value: "sm", label: "S" },
  { value: "md", label: "M" },
  { value: "lg", label: "L" },
] as const;

const { size = "md", disabled = false } = defineProps<{
  size?: string;
  disabled?: boolean;
}>();

const emit = defineEmits<{
  "update:size": [size: string];
}>();
const open = ref(false);

function selectSize(s: string) {
  emit("update:size", s);
  open.value = false;
}

const currentLabel = () => SIZE_OPTIONS.find((o) => o.value === size)?.label || "M";
</script>

<template>
  <Popover v-model:open="open">
    <PopoverAnchor as-child>
      <ToolbarTooltip :label="$t('common.toolbar_size.size')">
        <PopoverTrigger
          class="toolbar-btn text-xs font-semibold min-w-7"
          :disabled="disabled"
        >
          {{ currentLabel() }}
        </PopoverTrigger>
      </ToolbarTooltip>
    </PopoverAnchor>
    <PopoverContent class="w-auto p-1" :side-offset="8" side="top">
      <div class="flex gap-0.5">
        <button
          v-for="opt in SIZE_OPTIONS"
          :key="opt.value"
          type="button"
          class="px-3 py-1 text-xs font-medium rounded cursor-pointer transition-colors"
          :class="opt.value === size ? 'bg-primary text-primary-foreground' : 'hover:bg-muted'"
          @click="selectSize(opt.value)"
        >
          {{ opt.label }}
        </button>
      </div>
    </PopoverContent>
  </Popover>
</template>
