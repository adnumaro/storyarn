<script setup>
import { ref } from "vue";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";
import { COLOR_SWATCHES } from "./color-swatches";

const props = defineProps({
  color: { type: String, default: "#fbbf24" },
  disabled: { type: Boolean, default: false },
});

const emit = defineEmits(["update:color"]);
const open = ref(false);

function selectColor(c) {
  emit("update:color", c);
  open.value = false;
}

function onCustomColor(e) {
  emit("update:color", e.target.value);
}
</script>

<template>
  <Popover v-model:open="open">
    <PopoverTrigger as-child>
      <button type="button" class="v2-toolbar-btn" :disabled="disabled" :title="'Color'">
        <span
          class="size-4 rounded-full border border-white/20"
          :style="{ backgroundColor: color }"
        />
      </button>
    </PopoverTrigger>
    <PopoverContent class="w-auto p-2" :side-offset="8" side="top">
      <div class="flex flex-col gap-1">
        <div v-for="(row, i) in COLOR_SWATCHES" :key="i" class="flex gap-1">
          <button
            v-for="c in row"
            :key="c"
            type="button"
            class="size-5 rounded-full border border-white/10 hover:scale-125 transition-transform cursor-pointer"
            :class="{ 'ring-2 ring-primary ring-offset-1': c === color }"
            :style="{ backgroundColor: c }"
            @click="selectColor(c)"
          />
          <label
            v-if="i === row.length - 1"
            class="size-5 rounded-full border border-dashed border-white/30 flex items-center justify-center cursor-pointer hover:scale-125 transition-transform"
            title="Custom color"
          >
            <span class="text-[9px]">+</span>
            <input type="color" class="sr-only" :value="color" @input="onCustomColor" />
          </label>
        </div>
      </div>
      <slot name="extra" />
    </PopoverContent>
  </Popover>
</template>
