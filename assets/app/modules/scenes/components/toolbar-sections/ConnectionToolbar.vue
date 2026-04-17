<script setup lang="ts">
import { ArrowLeftRight, Settings, Tag } from "lucide-vue-next";
import ToolbarTooltip from "@components/toolbar/ToolbarTooltip.vue";
import { useLive } from "@composables/useLive";
import { ToolbarSeparator, ToolbarStrokePicker } from "../../toolbar";

interface ConnectionElement {
  id: number | string;
  label: string | null;
  color: string | null;
  lineStyle: string | null;
  lineWidth: number | null;
  showLabel: boolean;
  bidirectional: boolean;
}

const { element, canEdit = false } = defineProps<{
  element: ConnectionElement;
  canEdit: boolean;
}>();

const live = useLive();

function updateField(field: string, value: string | number | null): void {
  live.pushEvent("update_connection", {
    id: String(element.id),
    field,
    value: value === null ? "" : String(value),
  });
}

function toggleField(field: string, currentValue: boolean): void {
  live.pushEvent("update_connection", {
    id: String(element.id),
    field,
    toggle: String(!currentValue),
  });
}

function onLabelBlur(event: FocusEvent): void {
  updateField("label", (event.target as HTMLInputElement).value);
}

function toggleElementPanel(): void {
  live.pushEvent("toggle_element_panel", {});
}
</script>

<template>
  <!-- Label input -->
  <input
    type="text"
    :value="element.label || ''"
    class="toolbar-input w-24"
    :placeholder="$t('scenes.connection_toolbar.label')"
    :disabled="!canEdit"
    @blur="onLabelBlur"
    @keydown.enter="($event.target as HTMLInputElement).blur()"
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
  <ToolbarTooltip :label="$t('scenes.connection_toolbar.show_label')">
    <button
      type="button"
      class="toolbar-btn px-1.5"
      :class="{ '!bg-accent': element.showLabel }"
      :disabled="!canEdit"
      @click="toggleField('show_label', element.showLabel)"
    >
      <Tag class="size-3" />
    </button>
  </ToolbarTooltip>

  <!-- Bidirectional toggle -->
  <ToolbarTooltip :label="$t('scenes.connection_toolbar.bidirectional')">
    <button
      type="button"
      class="toolbar-btn px-1.5"
      :class="{ '!bg-accent': element.bidirectional }"
      :disabled="!canEdit"
      @click="toggleField('bidirectional', element.bidirectional)"
    >
      <ArrowLeftRight class="size-3" />
    </button>
  </ToolbarTooltip>
  <ToolbarSeparator />

  <!-- Settings cog -->
  <ToolbarTooltip :label="$t('scenes.connection_toolbar.properties')">
    <button
      type="button"
      class="toolbar-btn"
      @click="toggleElementPanel"
    >
      <Settings class="size-3.5" />
    </button>
  </ToolbarTooltip>
</template>
