<script setup>
defineProps({
  vertexEditorConfigs: { type: Object, default: null },
});

const emit = defineEmits(["insert-vertex", "vertex-dragmove", "vertex-dragend", "vertex-click"]);
</script>

<template>
  <v-layer v-if="vertexEditorConfigs">
    <!-- Midpoint anchors (click to insert vertex) -->
    <v-circle
      v-for="(mp, i) in vertexEditorConfigs.midpointAnchors"
      :key="'mp-' + i"
      :config="{
        x: mp.x,
        y: mp.y,
        radius: mp.radius,
        fill: mp.fill,
        stroke: mp.stroke,
        strokeWidth: mp.strokeWidth,
      }"
      @click="(e) => emit('insert-vertex', mp.afterIndex, e)"
    />
    <!-- Vertex anchors (drag to reshape, ctrl+click to remove) -->
    <v-circle
      v-for="(va, i) in vertexEditorConfigs.vertexAnchors"
      :key="'va-' + i"
      :config="{
        x: va.x,
        y: va.y,
        radius: va.radius,
        fill: va.fill,
        stroke: va.stroke,
        strokeWidth: va.strokeWidth,
        draggable: true,
      }"
      @dragmove="(e) => emit('vertex-dragmove', va.index, e)"
      @dragend="emit('vertex-dragend')"
      @click="(e) => emit('vertex-click', va.index, e)"
    />
  </v-layer>
</template>
