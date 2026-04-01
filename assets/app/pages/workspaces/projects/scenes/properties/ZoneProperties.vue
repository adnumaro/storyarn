<script setup>
import { EyeOff, Footprints } from "lucide-vue-next";
import ConditionBuilder from "@components/builders/ConditionBuilder.vue";
import ExpressionEditor from "@components/ExpressionEditor.vue";
import { EntityCombobox, TextField, ToggleField } from "@components/form-fields";
import { useLive } from "@composables/useLive";
import CollectionItemsEditor from "./zone/CollectionItemsEditor.vue";
import TargetPicker from "./zone/TargetPicker.vue";

const CONDITION_EFFECTS = [
  { id: "hide", name: "Hide" },
  { id: "disable", name: "Disable" },
];

const { element, canEdit, projectScenes, projectSheets, projectFlows, projectVariables } = defineProps({
  element: { type: Object, required: true },
  canEdit: { type: Boolean, default: false },
  projectScenes: { type: Array, default: () => [] },
  projectSheets: { type: Array, default: () => [] },
  projectFlows: { type: Array, default: () => [] },
  projectVariables: { type: Array, default: () => [] },
});

const live = useLive();

function update(field, value) {
  live.pushEvent("update_zone", {
    id: String(element.id),
    field,
    value: value === null || value === undefined ? "" : String(value),
  });
}

function toggle(field, currentValue) {
  live.pushEvent("update_zone", {
    id: String(element.id),
    field,
    toggle: String(!currentValue),
  });
}

function updateTarget({ targetType, targetId }) {
  live.pushEvent("update_zone", {
    id: String(element.id),
    field: "target_type",
    value: targetType || "",
  });
  if (targetId !== undefined) {
    live.pushEvent("update_zone", {
      id: String(element.id),
      field: "target_id",
      value: targetId ? String(targetId) : "",
    });
  }
}

function updateAssignments(assignments) {
  live.pushEvent("update_zone_assignments", {
    "zone-id": String(element.id),
    assignments,
  });
}

function selectDisplayVar(varRef) {
  live.pushEvent(`select_zone_display_var:${element.id}`, {
    id: varRef,
  });
}
</script>

<template>
  <div class="space-y-3">
    <!-- Walkable (only if action_type is not "walkable") -->
    <ToggleField
      v-if="element.actionType !== 'walkable'"
      label="Walkable area"
      :icon="Footprints"
      :checked="!!element.isWalkable"
      :disabled="!canEdit"
      @toggle="toggle('is_walkable', element.isWalkable)"
    />

    <!-- Shortcut -->
    <div v-if="element.shortcut" class="space-y-1">
      <label class="block text-xs font-medium text-foreground/70">Shortcut</label>
      <div class="text-xs font-mono text-muted-foreground bg-accent/50 rounded px-2 py-1">
        {{ element.shortcut }}
      </div>
    </div>

    <!-- Hidden in exploration -->
    <div class="pt-3 border-t border-border">
      <ToggleField
        label="Hidden in exploration"
        :icon="EyeOff"
        :checked="!!element.hidden"
        :disabled="!canEdit"
        @toggle="toggle('hidden', element.hidden)"
      />
    </div>

    <!-- Tooltip -->
    <div class="pt-3 border-t border-border">
      <TextField
        label="Tooltip"
        :value="element.tooltip || ''"
        placeholder="Hover text..."
        :disabled="!canEdit"
        @update="(v) => update('tooltip', v)"
      />
    </div>

    <!-- Link to -->
    <div class="pt-3 border-t border-border">
      <TargetPicker
        :target-type="element.targetType"
        :target-id="element.targetId"
        :scenes="projectScenes"
        :flows="projectFlows"
        :disabled="!canEdit"
        @update:target="updateTarget"
      />
    </div>

    <!-- Action-type-specific section -->
    <div v-if="element.actionType === 'instruction'" class="pt-3 border-t border-border space-y-1">
      <label class="block text-xs font-medium text-foreground/70">Instruction</label>
      <ExpressionEditor
        :assignments="element.actionData?.assignments || []"
        :variables="projectVariables"
        :disabled="!canEdit"
        mode="instruction"
        @update:assignments="updateAssignments"
      />
    </div>

    <div v-if="element.actionType === 'display'" class="pt-3 border-t border-border">
      <EntityCombobox
        label="Display variable"
        placeholder="Select variable..."
        :options="
          projectVariables.map((v) => ({
            id: v.ref || `${v.sheet_shortcut}.${v.variable_name}`,
            name: v.label || `${v.sheet_shortcut}.${v.variable_name}`,
          }))
        "
        :selected-id="element.actionData?.variable_ref"
        :disabled="!canEdit"
        @update:selected-id="selectDisplayVar"
      />
    </div>

    <div v-if="element.actionType === 'collection'" class="pt-3 border-t border-border space-y-1">
      <label class="block text-xs font-medium text-foreground/70">Collection</label>
      <CollectionItemsEditor
        :zone-id="element.id"
        :action-data="element.actionData || {}"
        :can-edit="canEdit"
        :project-sheets="projectSheets"
        :project-variables="projectVariables"
      />
    </div>

    <!-- Condition -->
    <div class="pt-3 border-t border-border space-y-2">
      <div class="flex items-center justify-between">
        <label class="text-xs font-medium text-foreground/70">Condition</label>
        <div class="flex gap-0.5">
          <button
            v-for="opt in CONDITION_EFFECTS"
            :key="opt.id"
            type="button"
            class="px-1.5 py-0.5 text-[10px] rounded transition-colors"
            :class="
              (element.conditionEffect || 'hide') === opt.id
                ? 'bg-muted text-foreground font-medium'
                : 'text-muted-foreground hover:text-foreground'
            "
            :disabled="!canEdit"
            @click="
              live.pushEvent('update_zone_condition_effect', {
                id: String(element.id),
                effect: opt.id,
              })
            "
          >
            {{ opt.name }}
          </button>
        </div>
      </div>
      <ConditionBuilder
        :condition="element.condition"
        :variables="projectVariables"
        :disabled="!canEdit"
        @update:condition="
          (c) =>
            live.pushEvent('update_zone_condition', { 'zone-id': String(element.id), condition: c })
        "
      />
    </div>
  </div>
</template>
