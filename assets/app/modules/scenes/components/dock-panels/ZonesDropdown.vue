<script setup lang="ts">
import type { Component } from "vue";
import { Circle, PenTool, Square, Triangle } from "lucide-vue-next";
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";

const { t } = useI18n();

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

const shapeTools = computed<ShapeTool[]>(() => [
  { id: "rectangle", icon: Square, title: t("scenes.zones_dropdown.rectangle") },
  { id: "triangle", icon: Triangle, title: t("scenes.zones_dropdown.triangle") },
  { id: "circle", icon: Circle, title: t("scenes.zones_dropdown.circle") },
  { id: "freeform", icon: PenTool, title: t("scenes.zones_dropdown.freeform") },
]);

const shapeToolIds = computed(() => shapeTools.value.map((s) => s.id));

const isShapeActive = (): boolean => shapeToolIds.value.includes(activeTool);

const activeShapeIcon = (): Component => {
  const shape = shapeTools.value.find((s) => s.id === activeTool);
  return shape ? shape.icon : PenTool;
};

function setTool(type: string): void {
  emit("set-tool", type);
  shapesOpen.value = false;
}
</script>

<template>
  <div class="dock-item group relative">
    <Popover v-model:open="shapesOpen">
      <PopoverTrigger as-child>
        <button type="button" class="dock-btn" :class="{ 'dock-btn-active': isShapeActive() }">
          <component :is="isShapeActive() ? activeShapeIcon() : PenTool" class="size-5" />
        </button>
      </PopoverTrigger>
      <PopoverContent side="top" :side-offset="12" class="w-52 p-3">
        <div class="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-2 px-1">
          {{ $t("scenes.zones_dropdown.title") }}
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
            <span class="font-medium">{{ shape.title }}</span>
          </button>
        </div>
      </PopoverContent>
    </Popover>
    <div v-if="!shapesOpen" class="dock-tooltip">
      <div class="text-sm font-semibold mb-0.5">{{ $t("scenes.zones_dropdown.zones_tooltip") }}</div>
      <div class="text-xs text-muted-foreground leading-relaxed">
        {{ $t("scenes.zones_dropdown.zones_tooltip_desc") }}
      </div>
    </div>
  </div>
</template>
