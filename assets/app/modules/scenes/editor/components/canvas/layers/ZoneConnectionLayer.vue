<script setup lang="ts">
import type { KonvaEventObject } from "konva/lib/Node";
import type { ZoneConfig } from "../../../../canvas/composables/useZones";
import type { ConnectionConfig } from "../../../../canvas/composables/useConnections";

const { zoneConfigs, connectionConfigs, selectionColor, labelColor } = defineProps<{
  zoneConfigs: ZoneConfig[];
  connectionConfigs: ConnectionConfig[];
  selectionColor: string;
  labelColor: string;
}>();

const emit = defineEmits<{
  "zone-click": [id: number | string, e: KonvaEventObject<MouseEvent>];
  "zone-dblclick": [id: number | string, e: KonvaEventObject<MouseEvent>];
  "zone-mousedown": [id: number | string, e: KonvaEventObject<MouseEvent>];
  "connection-click": [id: number | string, e: KonvaEventObject<MouseEvent>];
  "connection-dblclick": [id: number | string, e: KonvaEventObject<MouseEvent>];
}>();

function onZoneClick(id: number | string, e: KonvaEventObject<MouseEvent>) {
  emit("zone-click", id, e);
}
function onZoneDblclick(id: number | string, e: KonvaEventObject<MouseEvent>) {
  emit("zone-dblclick", id, e);
}
function onZoneMousedown(id: number | string, e: KonvaEventObject<MouseEvent>) {
  emit("zone-mousedown", id, e);
}
function onConnectionClick(id: number | string, e: KonvaEventObject<MouseEvent>) {
  emit("connection-click", id, e);
}
function onConnectionDblclick(id: number | string, e: KonvaEventObject<MouseEvent>) {
  emit("connection-dblclick", id, e);
}
</script>

<template>
  <v-layer>
    <v-group
      v-for="zone in zoneConfigs"
      :key="'zone-' + zone.id"
      :config="{ listening: zone.listening }"
      @click="(e: KonvaEventObject<MouseEvent>) => onZoneClick(zone.id, e)"
      @dblclick="(e: KonvaEventObject<MouseEvent>) => onZoneDblclick(zone.id, e)"
      @mousedown="(e: KonvaEventObject<MouseEvent>) => onZoneMousedown(zone.id, e)"
    >
      <!-- Zone polygon -->
      <v-line
        :config="{
          points: zone.points,
          fill: zone.fill,
          stroke: zone.stroke,
          strokeWidth: zone.strokeWidth,
          dash: zone.dash,
          opacity: zone.opacity,
          closed: true,
          hitStrokeWidth: zone.hitStrokeWidth,
          shadowColor: zone.isSelected ? selectionColor : undefined,
          shadowBlur: zone.isSelected ? 10 : 0,
          shadowOpacity: zone.isSelected ? 0.8 : 0,
          shadowEnabled: zone.isSelected,
          shadowForStrokeEnabled: false,
          perfectDrawEnabled: false,
        }"
      />
      <v-line
        v-if="zone.isSelected"
        :config="{
          points: zone.points,
          stroke: selectionColor,
          strokeWidth: Math.max(zone.strokeWidth + 2, 4),
          dash: [8, 5],
          opacity: 0.95,
          closed: true,
          listening: false,
          shadowColor: selectionColor,
          shadowBlur: 6,
          shadowOpacity: 0.45,
          shadowForStrokeEnabled: false,
          perfectDrawEnabled: false,
        }"
      />
      <v-text
        v-if="zone.name"
        :config="{
          text: zone.name,
          fill: labelColor,
          fontSize: 12,
          fontFamily: 'sans-serif',
          fontStyle: '600',
          lineHeight: 1.33,
          align: 'center',
          x: zone.labelX,
          y: zone.labelY,
          width: zone.labelWidth,
          height: zone.labelHeight,
          ellipsis: false,
          wrap: 'word',
          shadowColor: 'black',
          shadowBlur: 3,
          shadowOpacity: 0.8,
          shadowForStrokeEnabled: false,
          listening: false,
        }"
      />
      <v-image
        v-if="zone.lockBadge"
        :config="{
          image: zone.lockBadge,
          x: zone.lockBadgeX,
          y: zone.lockBadgeY,
          width: 14,
          height: 14,
          listening: false,
        }"
      />
    </v-group>
    <v-group
      v-for="conn in connectionConfigs"
      :key="'conn-' + conn.id"
      :config="{ listening: conn.listening }"
      @click="(e: KonvaEventObject<MouseEvent>) => onConnectionClick(conn.id, e)"
      @dblclick="(e: KonvaEventObject<MouseEvent>) => onConnectionDblclick(conn.id, e)"
    >
      <v-arrow
        :config="{
          points: conn.points,
          stroke: conn.stroke,
          fill: conn.fill,
          strokeWidth: conn.strokeWidth,
          dash: conn.dash,
          opacity: conn.opacity,
          pointerLength: conn.pointerLength,
          pointerWidth: conn.pointerWidth,
          pointerAtBeginning: conn.pointerAtBeginning,
          pointerAtEnding: conn.pointerAtEnding,
          hitStrokeWidth: conn.hitStrokeWidth,
        }"
      />
      <v-text v-if="conn.labelConfig" :config="conn.labelConfig" />
    </v-group>
  </v-layer>
</template>
