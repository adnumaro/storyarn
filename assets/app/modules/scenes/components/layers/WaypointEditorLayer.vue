<script setup lang="ts">
import type { KonvaEventObject } from "konva/lib/Node";

interface WaypointAnchorConfig {
  x: number;
  y: number;
  radius: number;
  fill: string;
  stroke: string;
  strokeWidth: number;
  index: number;
}

interface MidpointAnchorConfig {
  x: number;
  y: number;
  radius: number;
  fill: string;
  stroke: string;
  strokeWidth: number;
  segmentIndex: number;
}

interface WaypointEditorConfigs {
  waypointAnchors: WaypointAnchorConfig[];
  midpointAnchors: MidpointAnchorConfig[];
}

const { waypointEditorConfigs = null } = defineProps<{
  waypointEditorConfigs: WaypointEditorConfigs | null;
}>();

const emit = defineEmits<{
  "insert-waypoint": [segmentIndex: number, e: KonvaEventObject<MouseEvent>];
  "waypoint-dragmove": [index: number, e: KonvaEventObject<DragEvent>];
  "waypoint-dragend": [];
  "waypoint-click": [index: number, e: KonvaEventObject<MouseEvent>];
}>();
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
