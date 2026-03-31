<script setup>
import { Trash2 } from "lucide-vue-next";
import ConditionBuilder from "@components/builders/ConditionBuilder.vue";
import { EntityCombobox, TextField } from "@components/form-fields";
import { useLive } from "@composables/useLive";

const props = defineProps({
  item: { type: Object, required: true },
  idx: { type: Number, required: true },
  zoneId: { type: Number, required: true },
  canEdit: { type: Boolean, default: false },
  projectSheets: { type: Array, default: () => [] },
  projectVariables: { type: Array, default: () => [] },
});

const live = useLive();

function updateField(field, value) {
  live.pushEvent("update_collection_item", {
    "zone-id": String(props.zoneId),
    "item-id": props.item.id,
    field,
    value: value === null || value === undefined ? "" : String(value),
  });
}

function updateCondition(condition) {
  live.pushEvent("update_collection_item_condition", {
    "zone-id": String(props.zoneId),
    "item-id": props.item.id,
    condition,
  });
}

function updateInstruction(assignments) {
  live.pushEvent("update_collection_item_instruction", {
    "zone-id": String(props.zoneId),
    "item-id": props.item.id,
    assignments,
  });
}

function remove() {
  live.pushEvent("remove_collection_item", {
    "zone-id": String(props.zoneId),
    "item-id": props.item.id,
  });
}
</script>

<template>
  <div class="border border-border rounded-md p-2 space-y-2">
    <div class="flex items-center justify-between">
      <span class="text-xs font-medium text-foreground/70">#{{ idx + 1 }}</span>
      <button
        v-if="canEdit"
        type="button"
        class="text-muted-foreground hover:text-destructive transition-colors"
        @click="remove"
      >
        <Trash2 class="size-3" />
      </button>
    </div>

    <EntityCombobox
      label="Sheet"
      placeholder="Select sheet..."
      :options="projectSheets"
      :selected-id="item.sheet_id"
      :disabled="!canEdit"
      @update:selected-id="(id) => updateField('sheet_id', id)"
    />

    <TextField
      label="Label"
      :value="item.label || ''"
      placeholder="Item label..."
      :disabled="!canEdit"
      @update="(v) => updateField('label', v)"
    />

    <div class="space-y-1">
      <label class="text-xs font-medium text-foreground/70">Condition</label>
      <ConditionBuilder
        :condition="item.condition"
        :variables="projectVariables"
        :disabled="!canEdit"
        @update:condition="updateCondition"
      />
    </div>
  </div>
</template>
