<script setup>
defineProps({
	zoneConfigs: { type: Array, required: true },
	connectionConfigs: { type: Array, required: true },
	selectionColor: { type: String, required: true },
	labelColor: { type: String, required: true },
});

const emit = defineEmits([
	"zone-click",
	"zone-dblclick",
	"zone-mousedown",
	"connection-click",
	"connection-dblclick",
]);
</script>

<template>
  <v-layer>
    <v-group
      v-for="zone in zoneConfigs"
      :key="'zone-' + zone.id"
      :config="{ listening: zone.listening }"
      @click="(e) => emit('zone-click', zone.id, e)"
      @dblclick="(e) => emit('zone-dblclick', zone.id, e)"
      @mousedown="(e) => emit('zone-mousedown', zone.id, e)"
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
      <v-text
        v-if="zone.name"
        :config="{
          text: zone.name,
          fill: labelColor,
          fontSize: 12,
          fontStyle: '600',
          align: 'center',
          x: zone.centroidX - 50,
          y: zone.centroidY - 8,
          width: 100,
          ellipsis: true,
          wrap: 'none',
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
      @click="(e) => emit('connection-click', conn.id, e)"
      @dblclick="(e) => emit('connection-dblclick', conn.id, e)"
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
