<script setup>
defineProps({
	waypointEditorConfigs: { type: Object, default: null },
});

const emit = defineEmits([
	"insert-waypoint",
	"waypoint-dragmove",
	"waypoint-dragend",
	"waypoint-click",
]);
</script>

<template>
  <v-layer v-if="waypointEditorConfigs">
    <!-- Midpoint anchors (click to insert waypoint) -->
    <v-circle
      v-for="(mp, i) in waypointEditorConfigs.midpointAnchors"
      :key="'wmp-' + i"
      :config="{
        x: mp.x,
        y: mp.y,
        radius: mp.radius,
        fill: mp.fill,
        stroke: mp.stroke,
        strokeWidth: mp.strokeWidth,
      }"
      @click="(e) => emit('insert-waypoint', mp.segmentIndex, e)"
    />
    <!-- Waypoint anchors (drag to reshape, ctrl+click to remove) -->
    <v-circle
      v-for="(wa, i) in waypointEditorConfigs.waypointAnchors"
      :key="'wa-' + i"
      :config="{
        x: wa.x,
        y: wa.y,
        radius: wa.radius,
        fill: wa.fill,
        stroke: wa.stroke,
        strokeWidth: wa.strokeWidth,
        draggable: true,
      }"
      @dragmove="(e) => emit('waypoint-dragmove', wa.index, e)"
      @dragend="emit('waypoint-dragend')"
      @click="(e) => emit('waypoint-click', wa.index, e)"
    />
  </v-layer>
</template>
