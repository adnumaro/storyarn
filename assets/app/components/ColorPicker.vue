<script setup lang="ts">
import { ref, watch } from "vue";
import { Popover, PopoverContent, PopoverTrigger } from "../components/ui/popover";

const {
  modelValue = "#8b5cf6",
  presets = [
    "#ef4444",
    "#f97316",
    "#f59e0b",
    "#eab308",
    "#84cc16",
    "#22c55e",
    "#14b8a6",
    "#06b6d4",
    "#3b82f6",
    "#6366f1",
    "#8b5cf6",
    "#a855f7",
    "#d946ef",
    "#ec4899",
    "#f43f5e",
    "#6b7280",
  ],
  disabled = false,
} = defineProps<{
  modelValue?: string;
  presets?: string[];
  disabled?: boolean;
}>();

const emit = defineEmits<{
  "update:modelValue": [color: string];
}>();

const open = ref(false);

function selectColor(color: string) {
  emit("update:modelValue", color);
  open.value = false;
}
</script>

<template>
  <Popover v-model:open="open">
    <PopoverTrigger as-child>
      <button
        type="button"
        class="size-7 rounded-md border border-border shadow-sm transition-colors hover:opacity-80"
        :style="{ backgroundColor: modelValue }"
        :disabled="disabled"
      />
    </PopoverTrigger>
    <PopoverContent class="w-auto p-3" side="bottom" align="start">
      <div class="grid grid-cols-8 gap-1.5">
        <button
          v-for="color in presets"
          :key="color"
          type="button"
          class="size-6 rounded-md border border-border/50 transition-all hover:scale-110"
          :class="
            modelValue === color && 'ring-2 ring-primary ring-offset-1 ring-offset-background'
          "
          :style="{ backgroundColor: color }"
          @click="selectColor(color)"
        />
      </div>
      <div class="mt-2 flex items-center gap-2">
        <input
          type="color"
          :value="modelValue"
          class="size-7 cursor-pointer rounded border-0 p-0"
          @input="(e: Event) => selectColor((e.target as HTMLInputElement).value)"
        />
        <span class="text-xs text-muted-foreground font-mono">{{ modelValue }}</span>
      </div>
    </PopoverContent>
  </Popover>
</template>
