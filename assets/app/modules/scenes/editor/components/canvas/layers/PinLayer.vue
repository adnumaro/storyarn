<script setup lang="ts">
import type { KonvaEventObject } from "konva/lib/Node";
import type { PinConfig } from "../../../../canvas/composables/usePins";

const {
  pinConfigs,
  sourcePinId = null,
  hoveredPinId = null,
  selectionColor,
  sourceHighlightColor,
  targetHighlightColor,
  labelColor,
  clipCircle,
} = defineProps<{
  pinConfigs: PinConfig[];
  sourcePinId: number | string | null;
  hoveredPinId: number | string | null;
  selectionColor: string;
  sourceHighlightColor: string;
  targetHighlightColor: string;
  labelColor: string;
  clipCircle: (radius: number) => (ctx: CanvasRenderingContext2D) => void;
}>();

const emit = defineEmits<{
  "pin-click": [id: number | string, e: KonvaEventObject<MouseEvent>];
  dragstart: [type: string, id: number | string, e: KonvaEventObject<DragEvent>];
  dragmove: [type: string, id: number | string, e: KonvaEventObject<DragEvent>];
  dragend: [type: string, id: number | string, e: KonvaEventObject<DragEvent>];
}>();
</script>

<template>
  <v-layer>
    <v-group
      v-for="pin in pinConfigs"
      :key="'pin-' + pin.id"
      :config="{ x: pin.x, y: pin.y, listening: pin.listening, draggable: pin.draggable }"
      @click="(e: KonvaEventObject<MouseEvent>) => emit('pin-click', pin.id, e)"
      @dragstart="(e: KonvaEventObject<DragEvent>) => emit('dragstart', 'pin', pin.id, e)"
      @dragmove="(e: KonvaEventObject<DragEvent>) => emit('dragmove', 'pin', pin.id, e)"
      @dragend="(e: KonvaEventObject<DragEvent>) => emit('dragend', 'pin', pin.id, e)"
    >
      <v-circle
        v-if="pin.isSelected"
        :config="{
          radius: pin.radius + 5,
          stroke: selectionColor,
          strokeWidth: 3,
          listening: false,
        }"
      />
      <!-- Connection drawing: source highlight -->
      <v-circle
        v-if="sourcePinId === pin.id"
        :config="{
          radius: pin.radius + 6,
          stroke: sourceHighlightColor,
          strokeWidth: 2,
          dash: [6, 3],
          listening: false,
        }"
      />
      <!-- Connection drawing: target hover highlight -->
      <v-circle
        v-if="hoveredPinId === pin.id"
        :config="{
          radius: pin.radius + 6,
          stroke: targetHighlightColor,
          strokeWidth: 2,
          listening: false,
        }"
      />
      <v-image
        v-if="pin.iconCanvas"
        :key="'pin-icon-' + pin.id + '-' + pin.iconVersion"
        :config="{
          image: pin.iconCanvas,
          x: -pin.iconCanvas.width / 2,
          y: -pin.iconCanvas.height / 2,
          width: pin.iconCanvas.width,
          height: pin.iconCanvas.height,
        }"
      />
      <v-image
        v-else-if="pin.initialsCanvas"
        :config="{
          image: pin.initialsCanvas,
          x: -pin.initialsCanvas.width / 2,
          y: -pin.initialsCanvas.height / 2,
          width: pin.initialsCanvas.width,
          height: pin.initialsCanvas.height,
        }"
      />
      <template v-else-if="pin.image">
        <v-circle
          :config="{
            radius: pin.radius,
            fill: pin.color,
            opacity: pin.opacity,
            shadowColor: 'black',
            shadowBlur: 6,
            shadowOpacity: 0.3,
            shadowOffsetY: 2,
            shadowForStrokeEnabled: false,
            perfectDrawEnabled: false,
          }"
        />
        <v-group :config="{ clipFunc: clipCircle(pin.radius) }">
          <v-image
            :config="{
              image: pin.image,
              x: -pin.radius,
              y: -pin.radius,
              width: pin.diameter,
              height: pin.diameter,
            }"
          />
        </v-group>
      </template>
      <v-text
        v-if="pin.label"
        :config="{
          text: pin.label,
          fill: labelColor,
          fontSize: 11,
          fontStyle: '600',
          align: 'center',
          x: -50,
          y: pin.radius + 6,
          width: 100,
          ellipsis: true,
          wrap: 'none',
          listening: false,
        }"
      />
      <v-image
        v-if="pin.lockBadge"
        :config="{
          image: pin.lockBadge,
          x: pin.radius - 10,
          y: -pin.radius - 4,
          width: 14,
          height: 14,
          listening: false,
        }"
      />
    </v-group>
  </v-layer>
</template>
