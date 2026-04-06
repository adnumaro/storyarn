<script setup>
import { Settings } from "lucide-vue-next";
import { useLive } from "@composables/useLive";
import {
  ToolbarActionTypePicker,
  ToolbarColorPicker,
  ToolbarLayerPicker,
  ToolbarLockToggle,
  ToolbarSeparator,
  ToolbarStrokePicker,
} from "../../toolbar";

const { element, layers, canEdit } = defineProps({
  element: { type: Object, required: true },
  layers: { type: Array, default: () => [] },
  canEdit: { type: Boolean, default: false },
});

const live = useLive();

function updateField(field, value) {
  live.pushEvent("update_zone", {
    id: String(element.id),
    field,
    value: value === null ? "" : String(value),
  });
}

function updateActionType(type) {
  live.pushEvent("update_zone_action_type", {
    "zone-id": String(element.id),
    "action-type": type,
  });
}

function toggleLock() {
  live.pushEvent("update_zone", {
    id: String(element.id),
    field: "locked",
    toggle: String(!element.locked),
  });
}

function toggleElementPanel() {
  live.pushEvent("toggle_element_panel", {});
}
</script>

<template>
  <!-- Action type -->
  <ToolbarActionTypePicker
    :action-type="element.actionType || 'none'"
    :disabled="element.locked"
    @update:action-type="updateActionType"
  />

  <!-- Name -->
  <input
    type="text"
    :value="element.name || ''"
    class="v2-toolbar-input w-20"
    placeholder="Name"
    :disabled="element.locked"
    @blur="(e) => updateField('name', e.target.value)"
    @keydown.enter="$event.target.blur()"
  />
  <ToolbarSeparator />

  <!-- Fill color + Opacity -->
  <ToolbarColorPicker
    :color="element.fillColor || '#3b82f6'"
    :disabled="element.locked"
    @update:color="(c) => updateField('fill_color', c)"
  >
    <template #extra>
      <div class="pt-2 border-t border-border mt-2">
        <label class="text-xs font-medium text-foreground/70">Opacity</label>
        <div class="flex items-center gap-2 mt-1">
          <input
            type="range"
            min="0"
            max="1"
            step="0.05"
            :value="element.opacity ?? 0.3"
            class="flex-1 h-1 accent-primary"
            :disabled="element.locked"
            @input="(e) => updateField('opacity', e.target.value)"
          />
          <span class="text-xs font-mono w-8 text-right"
            >{{ Math.round((element.opacity ?? 0.3) * 100) }}%</span
          >
        </div>
      </div>
    </template>
  </ToolbarColorPicker>

  <!-- Border -->
  <ToolbarStrokePicker
    :line-style="element.borderStyle || 'solid'"
    :line-width="element.borderWidth || 2"
    :color="element.borderColor || '#1e40af'"
    :disabled="element.locked"
    @update:line-style="(v) => updateField('border_style', v)"
    @update:line-width="(v) => updateField('border_width', v)"
    @update:color="(v) => updateField('border_color', v)"
  />
  <ToolbarSeparator />

  <!-- Layer -->
  <ToolbarLayerPicker
    :layer-id="element.layerId"
    :layers="layers"
    :disabled="element.locked"
    @update:layer-id="(id) => updateField('layer_id', id)"
  />

  <!-- Lock -->
  <ToolbarLockToggle :locked="element.locked || false" :disabled="!canEdit" @toggle="toggleLock" />
  <ToolbarSeparator />

  <!-- Settings cog -->
  <button type="button" class="v2-toolbar-btn" title="Properties" @click="toggleElementPanel">
    <Settings class="size-3.5" />
  </button>
</template>
