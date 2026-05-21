<script setup lang="ts">
import { Route } from "lucide-vue-next";
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import { NumberField, SelectField, SliderField } from "@components/forms/fields";

const { t } = useI18n();

const PATROL_MODES = computed(() => [
  { id: "none", name: t("scenes.pin_patrol.none") },
  { id: "loop", name: t("scenes.pin_patrol.loop") },
  { id: "ping_pong", name: t("scenes.pin_patrol.ping_pong") },
  { id: "one_way", name: t("scenes.pin_patrol.one_way") },
]);

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
      :label="$t('scenes.pin_patrol.patrol')"
      :icon="Route"
      :options="PATROL_MODES"
      :value="patrolMode || 'none'"
      :placeholder="$t('scenes.pin_patrol.mode_placeholder')"
      :disabled="disabled"
      @update="(v) => emit('updateMode', v)"
    />

    <template v-if="patrolMode && patrolMode !== 'none'">
      <SliderField
        :label="$t('scenes.pin_patrol.speed')"
        :value="patrolSpeed || 1.0"
        :min="0.2"
        :max="3.0"
        :step="0.1"
        :format="formatSpeed"
        :disabled="disabled"
        @update="(v) => emit('updateSpeed', v)"
      />
      <NumberField
        :label="$t('scenes.pin_patrol.pause_waypoints')"
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
