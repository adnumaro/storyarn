<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { Circle, Diamond, RectangleHorizontal, Shapes, Type } from "@lucide/vue";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";
import ToolbarTooltip from "@components/toolbar/ToolbarTooltip.vue";
import { useBoardText } from "../composables/useBoardText";
import type { NoteShape } from "../types";

const { value, count, disabled } = defineProps<{
  value: NoteShape | null;
  count: number;
  disabled: boolean;
}>();
const emit = defineEmits<{ change: [shape: NoteShape]; close: [] }>();
const { t } = useBoardText();
const open = ref(false);
const trigger = ref<HTMLButtonElement>();
let chosen = false;
const shapes = [
  { id: "plain", icon: Type },
  { id: "rectangle", icon: RectangleHorizontal },
  { id: "ellipse", icon: Circle },
  { id: "diamond", icon: Diamond },
] as const;
const icon = computed(() => shapes.find((shape) => shape.id === value)?.icon ?? Shapes);
watch(
  () => disabled,
  (busy) => {
    if (busy) open.value = false;
  },
);
function choose(shape: NoteShape) {
  if (disabled) return;
  chosen = true;
  open.value = false;
  emit("change", shape);
}
function restoreFocus(event: Event) {
  if (!chosen) return;
  chosen = false;
  event.preventDefault();
  emit("close");
}
</script>

<template>
  <Popover v-model:open="open">
    <ToolbarTooltip :label="t('ideation.canvas.shape')">
      <PopoverTrigger as-child>
        <button
          id="brainstorming-shape-picker"
          ref="trigger"
          type="button"
          class="toolbar-btn disabled:opacity-45"
          :aria-label="t('ideation.canvas.shape')"
          :disabled="disabled"
        >
          <component :is="icon" class="size-4" />
        </button>
      </PopoverTrigger>
    </ToolbarTooltip>
    <PopoverContent
      :reference="trigger"
      class="w-72 p-2"
      :aria-label="t('ideation.canvas.shape')"
      @close-auto-focus="restoreFocus"
    >
      <p class="px-1 pb-2 pt-1 text-xs font-medium text-muted-foreground">
        {{
          count > 1 ? t("ideation.canvas.shapeSelection", { count }) : t("ideation.canvas.shape")
        }}
      </p>
      <div class="grid grid-cols-4 gap-1">
        <button
          v-for="shape in shapes"
          :id="`note-shape-${shape.id}`"
          :key="shape.id"
          type="button"
          class="flex min-w-0 flex-col items-center gap-1.5 rounded-md border px-1 py-2 text-[11px] transition-colors focus-visible:ring-2 focus-visible:ring-ring"
          :class="
            value === shape.id
              ? 'border-primary bg-primary/10 text-primary'
              : 'border-border hover:bg-accent'
          "
          :aria-label="t(`ideation.canvas.shapes.${shape.id}`)"
          :aria-pressed="value === shape.id"
          :disabled="disabled"
          @click="choose(shape.id)"
        >
          <component
            :is="shape.icon"
            class="size-5"
            :class="shape.id === 'ellipse' && 'scale-x-125 scale-y-90'"
          />
          {{ t(`ideation.canvas.shapes.${shape.id}`) }}
        </button>
      </div>
    </PopoverContent>
  </Popover>
</template>
