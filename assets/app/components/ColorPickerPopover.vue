<script setup lang="ts">
/**
 * Color picker using vanilla-colorful web components inside shadcn Popover.
 */

import { ChevronDown, Pipette } from "lucide-vue-next";
import { onBeforeUnmount, ref, watch } from "vue";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";

import "vanilla-colorful/hex-color-picker.js";
import "vanilla-colorful/hex-input.js";

import { useLive } from "@composables/useLive";

const props = defineProps<{
  color?: string;
  disabled?: boolean;
  variant?: "swatch" | "inline" | "full";
  event?: string | null;
}>();

declare class EyeDropper {
  constructor();
  open(): Promise<{ sRGBHex: string }>;
}

const emit = defineEmits<{
  "update:color": [hex: string];
}>();
const live = useLive();

const localColor = ref(props.color ?? "#3b82f6");
const pickerRef = ref(null);
const hexInputRef = ref(null);
const isOpen = ref(false);
const hasEyeDropper = ref(typeof window !== "undefined" && "EyeDropper" in window);
let debounceTimer: ReturnType<typeof setTimeout> | null = null;

watch(
  () => props.color,
  (v) => {
    localColor.value = v;
  },
);

function pushColor(hex: string) {
  localColor.value = hex;
  clearTimeout(debounceTimer);
  debounceTimer = setTimeout(() => {
    emit("update:color", hex);
    if (props.event) live.pushEvent(props.event, { value: hex });
  }, 150);
}

function onPickerChanged(e: CustomEvent<{ value: string }>) {
  const hex = e.detail.value;
  pushColor(hex);
  if (hexInputRef.value) hexInputRef.value.color = hex;
}

function onHexChanged(e: CustomEvent<{ value: string }>) {
  const hex = e.detail.value;
  pushColor(hex);
  if (pickerRef.value) pickerRef.value.color = hex;
}

function setColor(hex: string) {
  pushColor(hex);
  if (pickerRef.value) pickerRef.value.color = hex;
  if (hexInputRef.value) hexInputRef.value.color = hex;
}

async function pickFromScreen() {
  if (!hasEyeDropper.value) return;
  try {
    const dropper = new EyeDropper();
    const result = await dropper.open();
    setColor(result.sRGBHex);
  } catch {
    /* cancelled */
  }
}

function onPopoverOpen(open: boolean) {
  isOpen.value = open;
}

onBeforeUnmount(() => {
  clearTimeout(debounceTimer);
});
</script>

<template>
  <Popover @update:open="onPopoverOpen">
    <PopoverTrigger as-child>
      <button
        v-if="variant === 'swatch'"
        :disabled="disabled"
        class="size-7 rounded-full border-2 border-white/50 shadow-sm hover:scale-110 transition-transform"
        :style="{ backgroundColor: localColor }"
        title="Change color"
      />
      <div
        v-else
        class="inline-flex items-center gap-1.5 px-2 py-1 border border-border rounded-md bg-card cursor-pointer hover:bg-accent/50 transition-colors"
      >
        <div
          class="size-4 rounded shrink-0 border border-border"
          :style="{ backgroundColor: localColor }"
        />
        <span class="font-mono text-[11px] text-muted-foreground/60 flex-1">{{ localColor }}</span>
        <ChevronDown class="size-2.5 opacity-35 shrink-0" />
      </div>
    </PopoverTrigger>

    <PopoverContent align="end" :side-offset="8" class="w-[252px] p-3">
      <hex-color-picker
        ref="pickerRef"
        :color="localColor"
        style="width: 100%; --hcp-height: 140px"
        @color-changed="onPickerChanged"
      />

      <div class="flex items-center gap-2 mt-2.5">
        <!-- Eyedropper -->
        <button
          v-if="hasEyeDropper"
          type="button"
          class="flex items-center justify-center size-7 rounded-md border border-border bg-muted text-muted-foreground hover:text-foreground transition-colors cursor-pointer"
          title="Pick color from screen"
          @click="pickFromScreen"
        >
          <Pipette class="size-3.5" />
        </button>

        <!-- Color swatch -->
        <div
          class="size-[22px] rounded-[5px] border border-border shrink-0"
          :style="{ backgroundColor: localColor }"
        />

        <!-- Hex input -->
        <span class="font-mono text-[11px] text-muted-foreground/40 shrink-0">#</span>
        <hex-input
          ref="hexInputRef"
          :color="localColor"
          alpha
          class="flex-1 min-w-0"
          @color-changed="onHexChanged"
        >
          <input
            class="w-full font-mono text-[11px] border border-border rounded px-1.5 py-0.5 bg-muted text-foreground outline-none"
          />
        </hex-input>
      </div>
    </PopoverContent>
  </Popover>
</template>

<style>
hex-color-picker {
  --hcp-background: transparent;
  --hcp-border: 0;
}

hex-color-picker::part(saturation) {
  border-radius: 0.375rem;
  border-bottom: none;
}

hex-color-picker::part(hue) {
  border-radius: 9999px;
  height: 10px;
  margin-top: 0.5rem;
}

hex-color-picker::part(saturation-pointer),
hex-color-picker::part(hue-pointer) {
  width: 16px;
  height: 16px;
  border: 2px solid white;
  box-shadow: 0 0 0 1px rgba(0, 0, 0, 0.3);
}
</style>
