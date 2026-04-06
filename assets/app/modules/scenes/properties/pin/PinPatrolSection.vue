<script setup lang="ts">
import { Route } from "lucide-vue-next";
import { NumberField, SelectField, SliderField } from "@components/form-fields";

const PATROL_MODES = [
  { id: "none", name: "None" },
  { id: "loop", name: "Loop" },
  { id: "ping_pong", name: "Ping-pong" },
  { id: "one_way", name: "One-way" },
];

const {
  patrolMode = "none",
  patrolSpeed = 1.0,
  patrolPauseMs = 0,
  disabled = false,
} = defineProps<{
  patrolMode?: string;
  patrolSpeed?: number | string;
  patrolPauseMs?: number | string;
  disabled?: boolean;
}>();

const emit = defineEmits<{
  updateMode: [value: string];
  updateSpeed: [value: string];
  updatePause: [value: string];
}>();

function formatSpeed(v: number): string {
  return `${v}x`;
}
</script>

<template>
  <div class="space-y-2">
    <SelectField
      label="Patrol"
      :icon="Route"
      :options="PATROL_MODES"
      :value="patrolMode || 'none'"
      placeholder="Select mode..."
      :disabled="disabled"
      @update="(v) => emit('updateMode', v)"
    />

    <template v-if="patrolMode && patrolMode !== 'none'">
      <SliderField
        label="Speed"
        :value="patrolSpeed || 1.0"
        :min="0.2"
        :max="3.0"
        :step="0.1"
        :format="formatSpeed"
        :disabled="disabled"
        @update="(v) => emit('updateSpeed', v)"
      />
      <NumberField
        label="Pause at waypoints (ms)"
        :value="patrolPauseMs || 0"
        :min="0"
        :max="30000"
        :step="100"
        :disabled="disabled"
        @update="(v) => emit('updatePause', v)"
      />
    </template>
  </div>
</template>
