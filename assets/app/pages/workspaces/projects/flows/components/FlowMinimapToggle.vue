<script setup>
import { LayoutGrid, Maximize2 } from "lucide-vue-next";
import { AreaExtensions } from "rete-area-plugin";
import { ref } from "vue";

const { area, editor } = defineProps({
  area: { type: Object, default: null },
  editor: { type: Object, default: null },
});

const minimapVisible = ref(true);

function toggleMinimap() {
  if (!area) return;
  minimapVisible.value = !minimapVisible.value;

  const minimapEl = area.container?.querySelector(".minimap");
  if (minimapEl) {
    minimapEl.style.display = minimapVisible.value ? "" : "none";
  }
}

function fitToView() {
  if (!area || !editor) return;
  const nodes = editor.getNodes();
  if (nodes.length > 0) {
    AreaExtensions.zoomAt(area, nodes);
  }
}
</script>

<template>
  <div class="absolute bottom-3 right-3 z-20 flex flex-col gap-1">
    <button
      type="button"
      class="v2-toolbar-btn v2-surface-panel !rounded-lg size-8"
      :class="{ 'opacity-50': !minimapVisible }"
      title="Toggle minimap"
      @click="toggleMinimap"
    >
      <LayoutGrid class="size-4" />
    </button>
    <button
      type="button"
      class="v2-toolbar-btn v2-surface-panel !rounded-lg size-8"
      title="Fit to view"
      @click="fitToView"
    >
      <Maximize2 class="size-4" />
    </button>
  </div>
</template>
