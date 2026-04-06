<script setup lang="ts">
import type { Component } from "vue";
import { Circle, PenTool, Square, Triangle } from "lucide-vue-next";
import { ref } from "vue";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";

const { activeTool = "select" } = defineProps<{
  activeTool: string;
}>();

const emit = defineEmits<{
  "set-tool": [type: string];
}>();

const shapesOpen = ref(false);

interface ShapeTool {
  id: string;
  icon: Component;
  title: string;
}

const shapeTools: ShapeTool[] = [
  { id: "rectangle", icon: Square, title: "Rectangle" },
  { id: "triangle", icon: Triangle, title: "Triangle" },
  { id: "circle", icon: Circle, title: "Circle" },
  { id: "freeform", icon: PenTool, title: "Freeform" },
];

const shapeToolIds = shapeTools.map((s) => s.id);

const isShapeActive = (): boolean => shapeToolIds.includes(activeTool);

const activeShapeIcon = (): Component => {
  const shape = shapeTools.find((s) => s.id === activeTool);
  return shape ? shape.icon : PenTool;
};

function setTool(type: string): void {
  emit("set-tool", type);
  shapesOpen.value = false;
}
</script>

<template>
  <div class="v2-dock-item group relative">
    <Popover v-model:open="shapesOpen">
      <PopoverTrigger as-child>
        <button
          type="button"
          class="v2-dock-btn"
          :class="{ 'v2-dock-btn-active': isShapeActive() }"
        >
          <component :is="isShapeActive() ? activeShapeIcon() : PenTool" class="size-5" />
        </button>
      </PopoverTrigger>
      <PopoverContent side="top" :side-offset="12" class="w-52 p-3">
        <div class="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-2 px-1">
          Zone Shapes
        </div>
        <div class="flex flex-col gap-0.5">
          <button
            v-for="shape in shapeTools"
            :key="shape.id"
            type="button"
            class="w-full flex items-start gap-2.5 px-2.5 py-2 rounded-lg text-sm text-start cursor-pointer hover:bg-accent transition-colors"
            @click="setTool(shape.id)"
          >
            <component :is="shape.icon" class="size-4 mt-0.5 shrink-0" />
            <div class="font-medium">{{ shape.title }}</div>
          </button>
        </div>
      </PopoverContent>
    </Popover>
    <div v-if="!shapesOpen" class="v2-dock-tooltip">
      <div class="text-sm font-semibold mb-0.5">Zones</div>
      <div class="text-xs text-muted-foreground leading-relaxed">
        Draw shapes to define areas on the map
      </div>
    </div>
  </div>
</template>
