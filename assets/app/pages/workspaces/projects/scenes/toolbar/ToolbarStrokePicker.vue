<script setup>
import { ref } from "vue";
import { COLOR_SWATCHES } from "@components/shared/toolbar/color-swatches";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";

const STYLES = ["solid", "dashed", "dotted"];
const DASH_MAP = { solid: "none", dashed: "6,3", dotted: "2,2" };

const props = defineProps({
  lineStyle: { type: String, default: "solid" },
  lineWidth: { type: Number, default: 2 },
  color: { type: String, default: "#6b7280" },
  disabled: { type: Boolean, default: false },
});

const emit = defineEmits(["update:lineStyle", "update:lineWidth", "update:color"]);
const open = ref(false);

function decWidth() {
  if (props.lineWidth > 0) emit("update:lineWidth", props.lineWidth - 1);
}
function incWidth() {
  if (props.lineWidth < 10) emit("update:lineWidth", props.lineWidth + 1);
}
function selectColor(c) {
  emit("update:color", c);
}
function onCustomColor(e) {
  emit("update:color", e.target.value);
}
</script>

<template>
  <Popover v-model:open="open">
    <PopoverTrigger as-child>
      <button type="button" class="v2-toolbar-btn" :disabled="disabled" title="Line style">
        <span class="flex items-center gap-1">
          <svg width="16" height="16" viewBox="0 0 16 16" class="text-current">
            <line
              x1="2"
              y1="8"
              x2="14"
              y2="8"
              stroke="currentColor"
              stroke-width="2"
              :stroke-dasharray="DASH_MAP[lineStyle] || 'none'"
            />
          </svg>
          <span
            class="inline-block w-2.5 h-2.5 rounded-full shrink-0 border border-white/10"
            :style="{ background: color }"
          />
        </span>
      </button>
    </PopoverTrigger>
    <PopoverContent class="w-auto p-2" :side-offset="8" side="top">
      <div class="space-y-3">
        <!-- Style + Width row -->
        <div class="flex items-end gap-4">
          <div>
            <div class="text-xs font-medium text-muted-foreground mb-1.5">Style</div>
            <div class="flex gap-1">
              <button
                v-for="style in STYLES"
                :key="style"
                type="button"
                class="v2-toolbar-btn h-7 w-10"
                :class="{ 'bg-primary text-primary-foreground': style === lineStyle }"
                :disabled="disabled"
                @click="emit('update:lineStyle', style)"
              >
                <svg width="24" height="8" viewBox="0 0 24 8" class="text-current">
                  <line
                    x1="0"
                    y1="4"
                    x2="24"
                    y2="4"
                    stroke="currentColor"
                    stroke-width="2"
                    :stroke-dasharray="DASH_MAP[style] || 'none'"
                  />
                </svg>
              </button>
            </div>
          </div>
          <div>
            <div class="text-xs font-medium text-muted-foreground mb-1.5">Width</div>
            <div class="flex items-center gap-1">
              <button
                type="button"
                class="v2-toolbar-btn h-6 w-6 text-xs"
                :disabled="disabled || lineWidth <= 0"
                @click="decWidth"
              >
                −
              </button>
              <span class="w-5 text-center text-xs font-mono">{{ lineWidth }}</span>
              <button
                type="button"
                class="v2-toolbar-btn h-6 w-6 text-xs"
                :disabled="disabled || lineWidth >= 10"
                @click="incWidth"
              >
                +
              </button>
            </div>
          </div>
        </div>

        <!-- Color swatches -->
        <div>
          <div class="text-xs font-medium text-muted-foreground mb-1.5">Color</div>
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
                v-if="i === COLOR_SWATCHES.length - 1"
                class="size-5 rounded-full border border-dashed border-white/30 flex items-center justify-center cursor-pointer hover:scale-125 transition-transform"
                title="Custom color"
              >
                <span class="text-[9px]">+</span>
                <input type="color" class="sr-only" :value="color" @input="onCustomColor" />
              </label>
            </div>
          </div>
        </div>
      </div>
    </PopoverContent>
  </Popover>
</template>
