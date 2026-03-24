<script setup>
import { Plus } from "lucide-vue-next";
import { computed } from "vue";
import { TextField, ToggleField } from "@/vue/components/form-fields";
import { useLive } from "@/vue/composables/useLive";
import CollectionItemCard from "./CollectionItemCard.vue";

const props = defineProps({
	zoneId: { type: Number, required: true },
	actionData: { type: Object, default: () => ({}) },
	canEdit: { type: Boolean, default: false },
	projectSheets: { type: Array, default: () => [] },
	projectVariables: { type: Array, default: () => [] },
});

const live = useLive();

const items = computed(() => props.actionData?.items || []);
const collectAllEnabled = computed(
	() => props.actionData?.collect_all_enabled || false,
);
const emptyMessage = computed(() => props.actionData?.empty_message || "");

function updateSetting(field, value) {
	live.pushEvent("update_collection_settings", {
		"zone-id": String(props.zoneId),
		field,
		value: value === null || value === undefined ? "" : String(value),
	});
}

function addItem() {
	live.pushEvent("add_collection_item", {
		"zone-id": String(props.zoneId),
	});
}
</script>

<template>
  <div class="space-y-3">
    <ToggleField
      label="Collect all"
      :checked="collectAllEnabled"
      :disabled="!canEdit"
      @toggle="updateSetting('collect_all_enabled', !collectAllEnabled ? 'true' : 'false')"
    />

    <TextField
      label="Empty message"
      :value="emptyMessage"
      placeholder="Nothing to collect..."
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
      Add item
    </button>
  </div>
</template>
