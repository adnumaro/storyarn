<script setup>
import { ArrowLeftRight, Settings, Tag } from "lucide-vue-next";
import { useLive } from "@composables/useLive";
import { ToolbarSeparator, ToolbarStrokePicker } from "../../toolbar";

const { element, canEdit } = defineProps({
  element: { type: Object, required: true },
  canEdit: { type: Boolean, default: false },
});

const live = useLive();

function updateField(field, value) {
  live.pushEvent("update_connection", {
    id: String(element.id),
    field,
    value: value === null ? "" : String(value),
  });
}

function toggleField(field, currentValue) {
  live.pushEvent("update_connection", {
    id: String(element.id),
    field,
    toggle: String(!currentValue),
  });
}

function onLabelBlur(event) {
  updateField("label", event.target.value);
}

function toggleElementPanel() {
  live.pushEvent("toggle_element_panel", {});
}
</script>

<template>
  <!-- Label input -->
  <input
    type="text"
    :value="element.label || ''"
    class="v2-toolbar-input w-24"
    placeholder="Label"
    :disabled="!canEdit"
    @blur="onLabelBlur"
    @keydown.enter="$event.target.blur()"
  />
  <ToolbarSeparator />

  <!-- Stroke picker (style + width + color) -->
  <ToolbarStrokePicker
    :line-style="element.lineStyle || 'solid'"
    :line-width="element.lineWidth || 2"
    :color="element.color || '#ffffff'"
    :disabled="!canEdit"
    @update:line-style="(v) => updateField('line_style', v)"
    @update:line-width="(v) => updateField('line_width', v)"
    @update:color="(v) => updateField('color', v)"
  />
  <ToolbarSeparator />

  <!-- Show Label toggle -->
  <button
    type="button"
    class="v2-toolbar-btn px-1.5"
    :class="{ '!bg-accent': element.showLabel }"
    title="Show Label"
    :disabled="!canEdit"
    @click="toggleField('show_label', element.showLabel)"
  >
    <Tag class="size-3" />
  </button>

  <!-- Bidirectional toggle -->
  <button
    type="button"
    class="v2-toolbar-btn px-1.5"
    :class="{ '!bg-accent': element.bidirectional }"
    title="Bidirectional"
    :disabled="!canEdit"
    @click="toggleField('bidirectional', element.bidirectional)"
  >
    <ArrowLeftRight class="size-3" />
  </button>
  <ToolbarSeparator />

  <!-- Settings cog -->
  <button type="button" class="v2-toolbar-btn" title="Properties" @click="toggleElementPanel">
    <Settings class="size-3.5" />
  </button>
</template>
