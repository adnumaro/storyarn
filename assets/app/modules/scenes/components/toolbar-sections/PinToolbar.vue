<script setup lang="ts">
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

interface PinElement {
  id: number | string;
  label: string | null;
  pinType: string | null;
  color: string | null;
  opacity: number | null;
  size: string | null;
  locked: boolean;
  layerId: number | string | null;
}

interface LayerData {
  id: number | string;
  name: string;
  visible: boolean;
}

const {
  element,
  layers = [],
  canEdit = false,
} = defineProps<{
  element: PinElement;
  layers: LayerData[];
  canEdit: boolean;
}>();

const live = useLive();

function updateField(field: string, value: string | number | null): void {
  live.pushEvent("update_pin", {
    id: String(element.id),
    field,
    value: value === null ? "" : String(value),
  });
}

function toggleLock(): void {
  live.pushEvent("update_pin", {
    id: String(element.id),
    field: "locked",
    toggle: String(!element.locked),
  });
}

function toggleElementPanel(): void {
  live.pushEvent("toggle_element_panel", {});
}
</script>

<template>
  <!-- Label -->
  <input
    type="text"
    :value="element.label || ''"
    class="toolbar-input w-20"
    placeholder="Label"
    :disabled="element.locked"
    @blur="(e) => updateField('label', (e.target as HTMLInputElement).value)"
    @keydown.enter="($event.target as HTMLInputElement).blur()"
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
            @input="(e) => updateField('opacity', (e.target as HTMLInputElement).value)"
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
  <button type="button" class="toolbar-btn" title="Properties" @click="toggleElementPanel">
    <Settings class="size-3.5" />
  </button>
</template>
