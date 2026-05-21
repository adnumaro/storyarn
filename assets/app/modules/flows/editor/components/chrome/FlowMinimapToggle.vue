<script setup lang="ts">
import { LayoutGrid, Maximize2, Minus, Plus } from "lucide-vue-next";
import type { NodeEditor } from "rete";
import type { AreaPlugin } from "rete-area-plugin";
import { AreaExtensions } from "rete-area-plugin";
import { ref } from "vue";
import type { FlowSchemes, FlowAreaExtra } from "../../lib/rete-schemes";

const { area = null, editor = null } = defineProps<{
  area: AreaPlugin<FlowSchemes, FlowAreaExtra> | null;
  editor: NodeEditor<FlowSchemes> | null;
}>();

const minimapVisible = ref(true);
const ZOOM_STEP = 1.2;

function toggleMinimap() {
  if (!area) return;
  minimapVisible.value = !minimapVisible.value;

  const minimapEl = area.container?.querySelector(".minimap") as HTMLElement | null;
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

function zoomBy(factor: number) {
  if (!area) return;
  const inner = area.area;
  const rect = area.container.getBoundingClientRect();
  const { x: tx, y: ty } = inner.transform;
  const delta = factor - 1;
  const ox = (tx - rect.width / 2) * delta;
  const oy = (ty - rect.height / 2) * delta;
  inner.zoom(inner.transform.k * factor, ox, oy);
}

function zoomIn() {
  zoomBy(ZOOM_STEP);
}

function zoomOut() {
  zoomBy(1 / ZOOM_STEP);
}
</script>

<template>
  <div class="absolute bottom-3 right-3 z-20 flex gap-1">
    <button
      type="button"
      class="toolbar-btn surface-panel !rounded-lg size-8"
      :title="$t('flows.minimap.zoom_in')"
      @click="zoomIn"
    >
      <Plus class="size-4" />
    </button>
    <button
      type="button"
      class="toolbar-btn surface-panel !rounded-lg size-8"
      :title="$t('flows.minimap.zoom_out')"
      @click="zoomOut"
    >
      <Minus class="size-4" />
    </button>
    <button
      type="button"
      class="toolbar-btn surface-panel !rounded-lg size-8"
      :title="$t('flows.minimap.fit_view')"
      @click="fitToView"
    >
      <Maximize2 class="size-4" />
    </button>
    <button
      type="button"
      class="toolbar-btn surface-panel !rounded-lg size-8"
      :class="{ 'opacity-50': !minimapVisible }"
      :title="$t('flows.minimap.toggle')"
      @click="toggleMinimap"
    >
      <LayoutGrid class="size-4" />
    </button>
  </div>
</template>
