<script lang="ts">
const zoneNameDrafts = new Map<string, string>();
</script>

<script setup lang="ts">
import { Settings } from "lucide-vue-next";
import { nextTick, onMounted, ref, watch } from "vue";
import ToolbarTooltip from "@components/toolbar/ToolbarTooltip.vue";
import { useLive } from "@shared/composables/useLive.ts";
import { useSceneElementOptimisticUpdater } from "../../../composables/useSceneElementOptimism";
import {
  ToolbarActionTypePicker,
  ToolbarColorPicker,
  ToolbarLayerPicker,
  ToolbarLockToggle,
  ToolbarSeparator,
  ToolbarStrokePicker,
} from "../controls";

interface ZoneElement {
  id: number | string;
  name: string | null;
  actionType: string | null;
  fillColor: string | null;
  borderColor: string | null;
  borderWidth: number | null;
  borderStyle: string | null;
  opacity: number | null;
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
  element: ZoneElement;
  layers: LayerData[];
  canEdit: boolean;
}>();

const live = useLive();
const updateOptimistically = useSceneElementOptimisticUpdater();

const FIELD_TO_PROP: Record<string, keyof ZoneElement> = {
  name: "name",
  fill_color: "fillColor",
  border_color: "borderColor",
  border_width: "borderWidth",
  border_style: "borderStyle",
  opacity: "opacity",
  action_type: "actionType",
  layer_id: "layerId",
  locked: "locked",
};

function elementKey(): string {
  return String(element.id);
}

const existingDraft = zoneNameDrafts.get(elementKey());
const zoneNameDraft = ref(existingDraft ?? element.name ?? "");
const editingName = ref(existingDraft !== undefined);
const nameInputRef = ref<HTMLInputElement | null>(null);

watch(
  () => [element.id, element.name] as const,
  ([id, name], previous) => {
    const draft = zoneNameDrafts.get(String(id));

    if (draft !== undefined) {
      editingName.value = true;
      zoneNameDraft.value = draft;
      return;
    }

    if (!previous || id !== previous[0] || !editingName.value) {
      editingName.value = false;
      zoneNameDraft.value = name || "";
    }
  },
  { immediate: true },
);

watch(zoneNameDraft, (value) => {
  if (editingName.value) {
    zoneNameDrafts.set(elementKey(), value);
  }
});

onMounted(() => {
  if (!editingName.value) {
    return;
  }

  nextTick(() => {
    const input = nameInputRef.value;
    if (!input) {
      return;
    }

    input.focus();
    input.setSelectionRange(input.value.length, input.value.length);
  });
});

function updateField(field: string, value: string | number | null): void {
  const prop = FIELD_TO_PROP[field];
  if (prop) updateOptimistically("zone", element.id, { [prop]: value });

  live.pushEvent("update_zone", {
    id: String(element.id),
    field,
    value: value === null ? "" : String(value),
  });
}

function updateActionType(type: string): void {
  updateOptimistically("zone", element.id, { actionType: type });

  live.pushEvent("update_zone_action_type", {
    "zone-id": String(element.id),
    "action-type": type,
  });
}

function toggleLock(): void {
  updateOptimistically("zone", element.id, { locked: !element.locked });

  live.pushEvent("update_zone", {
    id: String(element.id),
    field: "locked",
    toggle: String(!element.locked),
  });
}

function toggleElementPanel(): void {
  live.pushEvent("toggle_element_panel", {});
}

function startNameEdit(): void {
  editingName.value = true;
  zoneNameDrafts.set(elementKey(), zoneNameDraft.value);
}

function updateNameDraft(event: Event): void {
  const value = (event.target as HTMLInputElement).value;
  editingName.value = true;
  zoneNameDraft.value = value;
  zoneNameDrafts.set(elementKey(), value);
}

function finishNameEdit(): void {
  editingName.value = false;
  zoneNameDrafts.delete(elementKey());

  const nextName = zoneNameDraft.value.trim();
  const currentName = element.name || "";
  if (!nextName) {
    zoneNameDraft.value = currentName;
    return;
  }

  if (nextName !== currentName) {
    updateField("name", nextName);
  } else {
    zoneNameDraft.value = currentName;
  }
}

function cancelNameEdit(event: KeyboardEvent): void {
  zoneNameDraft.value = element.name || "";
  editingName.value = false;
  zoneNameDrafts.delete(elementKey());
  (event.target as HTMLInputElement).blur();
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
    ref="nameInputRef"
    type="text"
    :value="zoneNameDraft"
    class="toolbar-input w-20"
    :placeholder="$t('scenes.zone_toolbar.name')"
    :disabled="element.locked"
    @focus="startNameEdit"
    @input="updateNameDraft"
    @blur="finishNameEdit"
    @keydown.enter.prevent="($event.target as HTMLInputElement).blur()"
    @keydown.escape.prevent="cancelNameEdit"
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
        <label class="text-xs font-medium text-foreground/70">{{
          $t("scenes.zone_toolbar.opacity")
        }}</label>
        <div class="flex items-center gap-2 mt-1">
          <input
            type="range"
            min="0"
            max="1"
            step="0.05"
            :value="element.opacity ?? 0.3"
            class="flex-1 h-1 accent-primary"
            :disabled="element.locked"
            @input="(e) => updateField('opacity', (e.target as HTMLInputElement).value)"
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
  <ToolbarTooltip :label="$t('scenes.zone_toolbar.properties')">
    <button
      type="button"
      class="toolbar-btn"
      :aria-label="$t('scenes.zone_toolbar.properties')"
      :title="$t('scenes.zone_toolbar.properties')"
      @click="toggleElementPanel"
    >
      <Settings class="size-3.5" />
    </button>
  </ToolbarTooltip>
</template>
