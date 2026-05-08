<script setup lang="ts">
import { Plus } from "lucide-vue-next";
import { computed } from "vue";
import { TextField, ToggleField } from "@components/forms/fields";
import type { Variable } from "@modules/shared/variables";
import { useLive } from "@shared/composables/useLive";
import type { ConditionData } from "@components/builders/types";
import CollectionItemCard from "./CollectionItemCard.vue";

interface CollectionActionData {
  items?: {
    id: string;
    sheet_id?: number | string | null;
    label?: string;
    condition?: ConditionData | null;
  }[];
  collect_all_enabled?: boolean;
  empty_message?: string;
}

interface EntityOption {
  id: number | string;
  name: string;
  shortcut?: string;
}

const {
  zoneId,
  actionData = {},
  canEdit = false,
  projectSheets = [],
  projectVariables = [],
} = defineProps<{
  zoneId: number | string;
  actionData?: CollectionActionData;
  canEdit?: boolean;
  projectSheets?: EntityOption[];
  projectVariables?: Variable[];
}>();

const live = useLive();

const items = computed(() => actionData?.items || []);
const collectAllEnabled = computed(() => actionData?.collect_all_enabled || false);
const emptyMessage = computed(() => actionData?.empty_message || "");

function updateSetting(field: string, value: string | null | undefined) {
  live.pushEvent("update_collection_settings", {
    "zone-id": String(zoneId),
    field,
    value: value === null || value === undefined ? "" : String(value),
  });
}

function addItem() {
  live.pushEvent("add_collection_item", {
    "zone-id": String(zoneId),
  });
}
</script>

<template>
  <div class="space-y-3">
    <ToggleField
      :label="$t('scenes.collection_editor.collect_all')"
      :checked="collectAllEnabled"
      :disabled="!canEdit"
      @toggle="updateSetting('collect_all_enabled', !collectAllEnabled ? 'true' : 'false')"
    />

    <TextField
      :label="$t('scenes.collection_editor.empty_message')"
      :value="emptyMessage"
      :placeholder="$t('scenes.collection_editor.empty_placeholder')"
      :disabled="!canEdit"
      @update="(v) => updateSetting('empty_message', v)"
    />

    <div class="space-y-2">
      <CollectionItemCard
        v-for="(item, idx) in items"
        :key="item.id"
        :item="item"
        :idx="idx"
        :zone-id="zoneId"
        :can-edit="canEdit"
        :project-sheets="projectSheets"
        :project-variables="projectVariables"
      />
    </div>

    <button
      v-if="canEdit"
      type="button"
      class="flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground transition-colors"
      @click="addItem"
    >
      <Plus class="size-3" />
      {{ $t("scenes.collection_editor.add_item") }}
    </button>
  </div>
</template>
