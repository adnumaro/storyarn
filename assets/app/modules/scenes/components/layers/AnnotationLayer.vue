<script setup lang="ts">
import type { KonvaEventObject } from "konva/lib/Node";
import type { AnnotationConfig } from "../../composables/useAnnotations";

const { annotationConfigs, selectionColor, isEditingAnnotation, getDisplayText } = defineProps<{
  annotationConfigs: AnnotationConfig[];
  selectionColor: string;
  isEditingAnnotation: (id: number | string) => boolean;
  getDisplayText: (id: number | string, fallback: string) => string;
}>();

const emit = defineEmits<{
  "annotation-click": [id: number | string, e: KonvaEventObject<MouseEvent>];
  "annotation-dblclick": [config: AnnotationConfig, e: KonvaEventObject<MouseEvent>];
  dragstart: [type: string, id: number | string, e: KonvaEventObject<DragEvent>];
  dragmove: [type: string, id: number | string, e: KonvaEventObject<DragEvent>];
  dragend: [type: string, id: number | string, e: KonvaEventObject<DragEvent>];
}>();
</script>

<template>
  <v-layer>
    <v-group
      v-for="ann in annotationConfigs"
      :key="'ann-' + ann.id"
      :config="{ x: ann.x, y: ann.y, listening: ann.listening, draggable: ann.draggable }"
      @click="(e) => emit('annotation-click', ann.id, e)"
      @dblclick="(e) => emit('annotation-dblclick', ann, e)"
      @dragstart="(e) => emit('dragstart', 'annotation', ann.id, e)"
      @dragmove="(e) => emit('dragmove', 'annotation', ann.id, e)"
      @dragend="(e) => emit('dragend', 'annotation', ann.id, e)"
    >
      <v-rect
        v-if="ann.isSelected"
        :config="{
          x: -3,
          y: -3,
          width: ann.width + 6,
          height: ann.height + 6,
          stroke: selectionColor,
          strokeWidth: 2,
          listening: false,
        }"
      />
      <v-line
        :config="{
          points: ann.bodyPoints,
          fill: ann.color,
          opacity: ann.bgOpacity,
          closed: true,
          perfectDrawEnabled: false,
        }"
      />
      <v-line
        :config="{
          points: ann.foldPoints,
          fill: ann.color,
          closed: true,
          listening: false,
          perfectDrawEnabled: false,
        }"
      />
      <v-text
        v-if="!isEditingAnnotation(ann.id)"
        :config="{
          text: getDisplayText(ann.id, ann.text),
          fill: '#111827',
          fontSize: ann.fontSize,
          fontStyle: '600',
          fontFamily: 'system-ui, sans-serif',
          lineHeight: 1.3,
          width: ann.textWidth,
          x: ann.padLeft,
          y: ann.padTop,
          wrap: 'word',
          listening: false,
        }"
      />
      <v-image
        v-if="ann.lockBadge"
        :config="{
          image: ann.lockBadge,
          x: ann.width - 18,
          y: -4,
          width: 14,
          height: 14,
          listening: false,
        }"
      />
    </v-group>
  </v-layer>
</template>
