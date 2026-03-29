<script setup>
import { EyeOff, Image } from "lucide-vue-next";
import ConditionBuilder from "@/vue/components/ConditionBuilder.vue";
import {
	ButtonGroupField,
	EntityCombobox,
	TextField,
	ToggleField,
} from "@/vue/components/form-fields";
import { useLive } from "@/vue/composables/useLive";
import PinPatrolSection from "./pin/PinPatrolSection.vue";
import PinPlayableSection from "./pin/PinPlayableSection.vue";

const CONDITION_EFFECTS = [
	{ id: "hide", name: "Hide" },
	{ id: "disable", name: "Disable" },
];

const props = defineProps({
	element: { type: Object, required: true },
	canEdit: { type: Boolean, default: false },
	projectSheets: { type: Array, default: () => [] },
	projectFlows: { type: Array, default: () => [] },
	projectVariables: { type: Array, default: () => [] },
});

const live = useLive();

function update(field, value) {
	live.pushEvent("update_pin", {
		id: String(props.element.id),
		field,
		value: value === null || value === undefined ? "" : String(value),
	});
}

function uploadIcon() {
	const input = document.createElement("input");
	input.type = "file";
	input.accept = "image/jpeg,image/png,image/gif,image/webp,image/svg+xml";
	input.onchange = (e) => {
		const file = e.target.files[0];
		if (!file) return;
		const reader = new FileReader();
		reader.onload = () => {
			live.pushEvent("upload_pin_icon", {
				id: String(props.element.id),
				filename: file.name,
				content_type: file.type,
				data: reader.result,
			});
		};
		reader.readAsDataURL(file);
	};
	input.click();
}

function toggle(field, currentValue) {
	live.pushEvent("update_pin", {
		id: String(props.element.id),
		field,
		toggle: String(!currentValue),
	});
}
</script>

<template>
  <div class="space-y-3">
    <!-- Shortcut -->
    <div v-if="element.shortcut" class="space-y-1">
      <label class="block text-xs font-medium text-foreground/70">Shortcut</label>
      <div class="text-xs font-mono text-muted-foreground bg-accent/50 rounded px-2 py-1">
        {{ element.shortcut }}
      </div>
    </div>

    <!-- Tooltip -->
    <TextField
      label="Tooltip"
      :value="element.tooltip || ''"
      placeholder="Hover text..."
      :disabled="!canEdit"
      @update="(v) => update('tooltip', v)"
    />

    <!-- Sheet -->
    <div class="pt-3 border-t border-border">
      <EntityCombobox
        label="Sheet"
        placeholder="Select sheet..."
        :options="projectSheets"
        :selected-id="element.sheetId"
        :disabled="!canEdit"
        @update:selected-id="(id) => update('sheet_id', id)"
      />
    </div>

    <!-- Custom icon -->
    <div v-if="canEdit" class="pt-3 border-t border-border">
      <button
        type="button"
        class="flex items-center gap-2 w-full px-2 py-1.5 text-sm rounded-md hover:bg-accent transition-colors"
        @click="uploadIcon"
      >
        <Image class="size-3.5" />
        Change Icon
      </button>
    </div>

    <!-- Playable / Leader -->
    <div class="pt-3 border-t border-border">
      <PinPlayableSection
        :is-playable="!!element.isPlayable"
        :is-leader="!!element.isLeader"
        :disabled="!canEdit"
        @toggle-playable="toggle('is_playable', element.isPlayable)"
        @toggle-leader="toggle('is_leader', element.isLeader)"
      />
    </div>

    <!-- Patrol (only for non-playable) -->
    <div v-if="!element.isPlayable" class="pt-3 border-t border-border">
      <PinPatrolSection
        :patrol-mode="element.patrolMode"
        :patrol-speed="element.patrolSpeed"
        :patrol-pause-ms="element.patrolPauseMs"
        :disabled="!canEdit"
        @update-mode="(v) => update('patrol_mode', v)"
        @update-speed="(v) => update('patrol_speed', v)"
        @update-pause="(v) => update('patrol_pause_ms', v)"
      />
    </div>

    <!-- Flow -->
    <div class="pt-3 border-t border-border">
      <EntityCombobox
        label="Flow"
        placeholder="Select flow..."
        :options="projectFlows"
        :selected-id="element.flowId"
        :disabled="!canEdit"
        @update:selected-id="(id) => update('flow_id', id)"
      />
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
            :class="(element.conditionEffect || 'hide') === opt.id
              ? 'bg-muted text-foreground font-medium'
              : 'text-muted-foreground hover:text-foreground'"
            :disabled="!canEdit"
            @click="live.pushEvent('update_pin_condition_effect', { id: String(element.id), effect: opt.id })"
          >
            {{ opt.name }}
          </button>
        </div>
      </div>
      <ConditionBuilder
        :condition="element.condition"
        :variables="projectVariables"
        :disabled="!canEdit"
        @update:condition="(c) => live.pushEvent('update_pin_condition', { 'pin-id': String(element.id), condition: c })"
      />
    </div>

  </div>
</template>
