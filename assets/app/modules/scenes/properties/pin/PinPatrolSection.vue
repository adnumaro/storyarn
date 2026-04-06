<script setup>
import { Route } from "lucide-vue-next";
import { NumberField, SelectField, SliderField } from "@components/form-fields";

const PATROL_MODES = [
  { id: "none", name: "None" },
  { id: "loop", name: "Loop" },
  { id: "ping_pong", name: "Ping-pong" },
  { id: "one_way", name: "One-way" },
];

const { patrolMode, patrolSpeed, patrolPauseMs, disabled } = defineProps({
  patrolMode: { type: String, default: "none" },
  patrolSpeed: { type: [Number, String], default: 1.0 },
  patrolPauseMs: { type: [Number, String], default: 0 },
  disabled: { type: Boolean, default: false },
});

const emit = defineEmits(["updateMode", "updateSpeed", "updatePause"]);

function formatSpeed(v) {
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
