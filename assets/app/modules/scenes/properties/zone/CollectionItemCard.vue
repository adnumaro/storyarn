<script setup lang="ts">
import { Trash2 } from "lucide-vue-next";
import ConditionBuilder from "@components/builders/ConditionBuilder.vue";
import type { ConditionData } from "@components/builders/types";
import { EntityCombobox, TextField } from "@components/form-fields";
import type { Variable } from "@modules/shared/variables";
import { useLive } from "@composables/useLive";

interface CollectionItem {
  id: string;
  sheet_id?: number | string | null;
  label?: string;
  condition?: ConditionData | null;
}

interface EntityOption {
  id: number | string;
  name: string;
  shortcut?: string;
}

const {
  item,
  idx,
  zoneId,
  canEdit = false,
  projectSheets = [],
  projectVariables = [],
} = defineProps<{
  item: CollectionItem;
  idx: number;
  zoneId: number | string;
  canEdit?: boolean;
  projectSheets?: EntityOption[];
  projectVariables?: Variable[];
}>();

const live = useLive();

function updateField(field: string, value: string | number | null | undefined) {
  live.pushEvent("update_collection_item", {
    "zone-id": String(zoneId),
    "item-id": item.id,
    field,
    value: value === null || value === undefined ? "" : String(value),
  });
}

function updateCondition(condition: unknown) {
  live.pushEvent("update_collection_item_condition", {
    "zone-id": String(zoneId),
    "item-id": item.id,
    condition,
  });
}
function remove() {
  live.pushEvent("remove_collection_item", {
    "zone-id": String(zoneId),
    "item-id": item.id,
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
      :label="$t('scenes.collection_editor.sheet')"
      :placeholder="$t('scenes.collection_editor.sheet_placeholder')"
      :options="projectSheets"
      :selected-id="item.sheet_id"
      :disabled="!canEdit"
      @update:selected-id="(id) => updateField('sheet_id', id)"
    />

    <TextField
      :label="$t('scenes.collection_editor.label')"
      :value="item.label || ''"
      :placeholder="$t('scenes.collection_editor.label_placeholder')"
      :disabled="!canEdit"
      @update="(v) => updateField('label', v)"
    />

    <div class="space-y-1">
      <label class="text-xs font-medium text-foreground/70">{{ $t("scenes.collection_editor.condition") }}</label>
      <ConditionBuilder
        :condition="item.condition"
        :variables="projectVariables"
        :disabled="!canEdit"
        @update:condition="updateCondition"
      />
    </div>
  </div>
</template>
