<script setup>
import { Hash } from "lucide-vue-next";
import { computed, ref, watch } from "vue";
import { Input } from "@/vue/components/ui/input/index.js";
import { useBlockActions } from "../../composables/useBlockActions.js";
import BlockLabel from "../BlockLabel.vue";
import BlockToolbar from "../BlockToolbar.vue";

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

const content = computed(() => props.block.value?.content);
const localNumber = ref(content.value ?? "");
watch(content, (v) => {
	localNumber.value = v ?? "";
});

function save() {
	const raw = localNumber.value;
	const val = raw === "" || raw === null ? null : Number(raw);
	if (!Number.isNaN(val) && val !== content.value) {
		live.pushEvent("update_block_value", { id: props.block.id, value: val });
	}
}

function onKeydown(e) {
	if (e.key === "e" || e.key === "E" || e.key === "+") e.preventDefault();
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
        <div class="grid grid-cols-3 gap-2">
          <div class="space-y-1"><label class="text-xs font-medium">Min</label>
            <Input type="number" :model-value="block.config?.min ?? ''" class="h-7 text-xs"
              @blur="(e) => live.pushEvent('update_block_config', { id: block.id, field: 'min', value: e.target.value === '' ? null : Number(e.target.value) })" /></div>
          <div class="space-y-1"><label class="text-xs font-medium">Max</label>
            <Input type="number" :model-value="block.config?.max ?? ''" class="h-7 text-xs"
              @blur="(e) => live.pushEvent('update_block_config', { id: block.id, field: 'max', value: e.target.value === '' ? null : Number(e.target.value) })" /></div>
          <div class="space-y-1"><label class="text-xs font-medium">Step</label>
            <Input type="number" :model-value="block.config?.step ?? ''" class="h-7 text-xs"
              @blur="(e) => live.pushEvent('update_block_config', { id: block.id, field: 'step', value: e.target.value === '' ? null : Number(e.target.value) })" /></div>
        </div>
        <div class="space-y-1"><label class="text-xs font-medium">Placeholder</label>
          <Input :model-value="block.config?.placeholder || ''" placeholder="0" class="h-7 text-xs"
            @blur="(e) => live.pushEvent('update_block_config', { id: block.id, field: 'placeholder', value: e.target.value })" /></div>
      </template>
    </BlockToolbar>

    <BlockLabel :icon="Hash" :label="label" :can-edit="canEdit" :is-constant="block.is_constant" :required="block.required" :detached="block.detached" @save="saveLabel">
      <slot name="menu" />
    </BlockLabel>

    <Input v-if="canEdit" v-model="localNumber" type="number" :placeholder="block.config?.placeholder || '0'"
      :min="block.config?.min" :max="block.config?.max" :step="block.config?.step || 'any'"
      class="h-9 w-full" @blur="save" @keydown.enter="save" @keydown="onKeydown" />
    <p v-else class="text-sm tabular-nums">{{ content ?? "—" }}</p>
  </div>
</template>
