<script setup>
import { computed } from "@/vue/index.js";
import { ListChecks } from "lucide-vue-next";
import { Badge } from "@/vue/components/ui/badge/index.js";
import { Checkbox } from "@/vue/components/ui/checkbox/index.js";
import { Input } from "@/vue/components/ui/input/index.js";
import {
	Popover,
	PopoverContent,
	PopoverTrigger,
} from "@/vue/components/ui/popover/index.js";
import BlockToolbar from "../BlockToolbar.vue";
import BlockLabel from "./BlockLabel.vue";
import OptionEditor from "./OptionEditor.vue";
import { useBlockActions } from "./useBlockActions.js";

const props = defineProps({
	block: { type: Object, required: true },
	canEdit: { type: Boolean, default: false },
	inherited: { type: Boolean, default: false },
});

const { live, label, isSelected, onBlockClick } = useBlockActions(props);

function saveLabel(val) {
	live.pushEvent("update_block_config", {
		id: props.block.id,
		field: "label",
		value: val,
	});
}

const content = computed(() => props.block.value?.content || []);
const options = computed(() => props.block.config?.options || []);
const placeholder = computed(
	() => props.block.config?.placeholder || "Select...",
);

const selectedOptions = computed(() =>
	(Array.isArray(content.value) ? content.value : [])
		.map((key) => options.value.find((o) => o.key === key))
		.filter(Boolean),
);

function toggle(key) {
	live.pushEvent("toggle_multi_select", { id: props.block.id, key });
}
</script>

<template>
  <div
    class="group relative rounded-lg border p-4 pt-5 transition-colors"
    :class="isSelected ? 'border-primary ring-1 ring-primary/30' : 'border-border hover:border-foreground/20'"
    @click="onBlockClick"
  >
    <BlockToolbar v-if="canEdit"
      :is-constant="block.is_constant" :is-variable="!block.is_constant && !!block.variable_name"
      :variable-name="block.variable_name || ''" :show-scope="!inherited"
      :scope="block.scope || 'self'" :required="block.required"
      @toggle-constant="live.pushEvent('toggle_constant', { id: block.id })"
      @update-variable-name="(v) => live.pushEvent('update_variable_name', { id: block.id, variable_name: v })"
      @change-scope="(s) => live.pushEvent('change_block_scope', { id: block.id, scope: s })"
      @toggle-required="live.pushEvent('toggle_required', { id: block.id })"
    >
      <template #config>
        <OptionEditor :block-id="block.id" :options="options" />
        <div class="space-y-1">
          <label class="text-xs font-medium">Placeholder</label>
          <Input :model-value="block.config?.placeholder || ''" placeholder="Select..." class="h-7 text-xs"
            @blur="(e) => live.pushEvent('update_block_config', { id: block.id, field: 'placeholder', value: e.target.value })" />
        </div>
      </template>
    </BlockToolbar>

    <BlockLabel :icon="ListChecks" :label="label" :can-edit="canEdit" :is-constant="block.is_constant" :required="block.required" :detached="block.detached" @save="saveLabel">
      <slot name="menu" />
    </BlockLabel>

    <Popover v-if="canEdit">
      <PopoverTrigger as-child>
        <button class="flex flex-wrap gap-1 min-h-[36px] w-full rounded-md border border-input bg-background px-3 py-2 text-sm items-center">
          <Badge v-for="opt in selectedOptions" :key="opt.key" variant="secondary" class="text-xs">{{ opt.value }}</Badge>
          <span v-if="selectedOptions.length === 0" class="text-muted-foreground">{{ placeholder }}</span>
        </button>
      </PopoverTrigger>
      <PopoverContent align="start" class="w-[var(--reka-popover-trigger-width)] p-1">
        <div class="max-h-48 overflow-y-auto">
          <button v-for="opt in options" :key="opt.key" type="button"
            class="flex items-center gap-2 w-full px-2 py-1.5 text-sm rounded hover:bg-accent transition-colors" @click="toggle(opt.key)">
            <Checkbox :checked="Array.isArray(content) && content.includes(opt.key)" class="pointer-events-none" />
            {{ opt.value }}
          </button>
        </div>
      </PopoverContent>
    </Popover>
    <div v-else class="flex flex-wrap gap-1">
      <Badge v-for="opt in selectedOptions" :key="opt.key" variant="secondary" class="text-xs">{{ opt.value }}</Badge>
      <span v-if="selectedOptions.length === 0" class="text-sm text-muted-foreground">—</span>
    </div>
  </div>
</template>
