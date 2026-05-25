<script setup lang="ts">
import { Undo2 } from "lucide-vue-next";
import { computed } from "vue";
import { NumberField, ToggleField } from "@components/forms/fields";
import type {
  SceneRouteConnectionBase,
  SceneRouteStopFields,
  SceneRouteWaypoint,
} from "@modules/scenes/types/routes";
import { useLive } from "@shared/composables/useLive.ts";

type ConnectionElement = Pick<SceneRouteConnectionBase, "id"> &
  Partial<Omit<SceneRouteConnectionBase, "id">> &
  SceneRouteStopFields;

const { element, canEdit = false } = defineProps<{
  element: ConnectionElement;
  canEdit?: boolean;
}>();

const live = useLive();

const waypointCount = computed(() => element?.waypoints?.length || 0);
const routePoints = computed(() => element?.waypoints || []);

const hasFromPin = computed(() => element?.fromPinId !== null && element?.fromPinId !== undefined);
const hasToPin = computed(() => element?.toPinId !== null && element?.toPinId !== undefined);

function straightenPath() {
  live.pushEvent("clear_connection_waypoints", {
    id: String(element.id),
  });
}

function updateField(field: string, value: string | boolean | number | null) {
  live.pushEvent("update_connection", {
    id: String(element.id),
    field,
    value: value === null ? "" : String(value),
  });
}

function toggleField(field: string, value: boolean | undefined) {
  live.pushEvent("update_connection", {
    id: String(element.id),
    field,
    toggle: String(!value),
  });
}

function updateWaypoint(index: number, attrs: Partial<SceneRouteWaypoint>) {
  const next = routePoints.value.map((point, idx) =>
    idx === index ? { ...point, ...attrs } : point,
  );

  live.pushEvent("update_connection_waypoints", {
    id: String(element.id),
    waypoints: next,
  });
}

function waypointPause(point: SceneRouteWaypoint): number | string {
  return point.pauseMs ?? point.pause_ms ?? 0;
}
</script>

<template>
  <div class="space-y-3">
    <button
      v-if="canEdit && waypointCount > 0"
      type="button"
      class="flex items-center gap-2 w-full px-2 py-1.5 text-sm rounded-md hover:bg-accent transition-colors"
      @click="straightenPath"
    >
      <Undo2 class="size-3.5" />
      {{ $t("scenes.connection_properties.straighten") }}
    </button>
    <p v-else class="text-sm text-muted-foreground italic">
      {{ $t("scenes.connection_properties.no_waypoints") }}
    </p>

    <div class="space-y-3 border-t border-border pt-3">
      <p class="text-xs font-medium text-foreground/70">
        {{ $t("scenes.connection_properties.stops") }}
      </p>

      <div v-if="hasFromPin" class="space-y-2">
        <ToggleField
          :label="$t('scenes.connection_properties.start_pin_stop')"
          :checked="element.fromStop !== false"
          :disabled="!canEdit"
          @toggle="toggleField('from_stop', element.fromStop !== false)"
        />
        <NumberField
          v-if="element.fromStop !== false"
          :label="$t('scenes.connection_properties.pause_ms')"
          :value="element.fromPauseMs ?? ''"
          :min="0"
          :max="30000"
          :step="100"
          :disabled="!canEdit"
          @update="(v) => updateField('from_pause_ms', v)"
        />
      </div>

      <div v-for="(point, index) in routePoints" :key="index" class="space-y-2">
        <ToggleField
          :label="$t('scenes.connection_properties.waypoint_stop', { number: index + 1 })"
          :checked="!!point.stop"
          :disabled="!canEdit"
          @toggle="updateWaypoint(index, { stop: !point.stop })"
        />
        <NumberField
          v-if="point.stop"
          :label="$t('scenes.connection_properties.pause_ms')"
          :value="waypointPause(point)"
          :min="0"
          :max="30000"
          :step="100"
          :disabled="!canEdit"
          @update="(v) => updateWaypoint(index, { pauseMs: Number(v) || 0 })"
        />
      </div>

      <div v-if="hasToPin" class="space-y-2">
        <ToggleField
          :label="$t('scenes.connection_properties.end_pin_stop')"
          :checked="element.toStop !== false"
          :disabled="!canEdit"
          @toggle="toggleField('to_stop', element.toStop !== false)"
        />
        <NumberField
          v-if="element.toStop !== false"
          :label="$t('scenes.connection_properties.pause_ms')"
          :value="element.toPauseMs ?? ''"
          :min="0"
          :max="30000"
          :step="100"
          :disabled="!canEdit"
          @update="(v) => updateField('to_pause_ms', v)"
        />
      </div>
    </div>
  </div>
</template>
