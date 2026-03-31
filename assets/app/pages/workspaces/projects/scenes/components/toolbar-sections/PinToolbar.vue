<script setup>
import { Settings } from "lucide-vue-next";
import { useLive } from "@composables/useLive";
import {
  ToolbarColorPicker,
  ToolbarLayerPicker,
  ToolbarLockToggle,
  ToolbarSeparator,
  ToolbarSizePicker,
  ToolbarTypePicker,
} from "../../toolbar";

const props = defineProps({
  element: { type: Object, required: true },
  layers: { type: Array, default: () => [] },
  canEdit: { type: Boolean, default: false },
});

const live = useLive();

function updateField(field, value) {
  live.pushEvent("update_pin", {
    id: String(props.element.id),
    field,
    value: value === null ? "" : String(value),
  });
}

function toggleLock() {
  live.pushEvent("update_pin", {
    id: String(props.element.id),
    field: "locked",
    toggle: String(!props.element.locked),
  });
}

function toggleElementPanel() {
  live.pushEvent("toggle_element_panel", {});
}
</script>

<template>
  <!-- Label -->
  <input
    type="text"
    :value="element.label || ''"
    class="v2-toolbar-input w-20"
    placeholder="Label"
    :disabled="element.locked"
    @blur="(e) => updateField('label', e.target.value)"
    @keydown.enter="$event.target.blur()"
  />
  <ToolbarSeparator />

  <!-- Type -->
  <ToolbarTypePicker
    :type="element.pinType || 'location'"
    :disabled="element.locked"
    @update:type="(t) => updateField('pin_type', t)"
  />

  <!-- Color + Opacity -->
  <ToolbarColorPicker
    :color="element.color || '#3b82f6'"
    :disabled="element.locked"
    @update:color="(c) => updateField('color', c)"
  >
    <template #extra>
      <div class="pt-2 border-t border-border mt-2">
        <label class="text-xs font-medium text-muted-foreground">Opacity</label>
        <div class="flex items-center gap-2 mt-1">
          <input
            type="range"
            min="0"
            max="1"
            step="0.05"
            :value="element.opacity ?? 1"
            class="flex-1 h-1 accent-primary"
            :disabled="element.locked"
            @input="(e) => updateField('opacity', e.target.value)"
          />
          <span class="text-xs font-mono w-8 text-right"
            >{{ Math.round((element.opacity ?? 1) * 100) }}%</span
          >
        </div>
      </div>
    </template>
  </ToolbarColorPicker>

  <!-- Size -->
  <ToolbarSizePicker
    :size="element.size || 'md'"
    :disabled="element.locked"
    @update:size="(s) => updateField('size', s)"
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
