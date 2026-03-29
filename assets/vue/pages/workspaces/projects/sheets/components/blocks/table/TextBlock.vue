<script setup>
import { Type } from "lucide-vue-next";
import { computed, ref, watch } from "vue";
import { Input } from "@/vue/components/ui/input/index.js";
import { useLive } from "@/vue/composables/useLive.js";
import { useBlockActions } from "../../../composables/useBlockActions.js";
import BlockLabel from "../../BlockLabel.vue";
import BlockToolbar from "../../BlockToolbar.vue";

const props = defineProps({
	block: { type: Object, required: true },
	canEdit: { type: Boolean, default: false },
	inherited: { type: Boolean, default: false },
});

const { live, label, isSelected, onBlockClick } = useBlockActions(props);

const content = computed(() => props.block.value?.content ?? "");
const localText = ref(content.value);
watch(content, (v) => {
	localText.value = v;
});

function save() {
	if (localText.value !== content.value) {
		live.pushEvent("update_block_value", {
			id: props.block.id,
			value: localText.value,
		});
	}
}

function saveLabel(val) {
	live.pushEvent("update_block_config", {
		id: props.block.id,
		field: "label",
		value: val,
	});
}
</script>

<template>
  <div
    class="group relative rounded-lg border p-4 pt-5 transition-colors"
    :class="isSelected ? 'border-primary ring-1 ring-primary/30' : 'border-border hover:border-foreground/20'"
    @click="onBlockClick"
  >
    <BlockToolbar
      v-if="canEdit"
      :is-constant="block.is_constant"
      :is-variable="!block.is_constant && !!block.variable_name"
      :variable-name="block.variable_name || ''"
      :show-scope="!inherited"
      :scope="block.scope || 'self'"
      :required="block.required"
      @toggle-constant="live.pushEvent('toggle_constant', { id: block.id })"
      @update-variable-name="(v) => live.pushEvent('update_variable_name', { id: block.id, variable_name: v })"
      @change-scope="(s) => live.pushEvent('change_block_scope', { id: block.id, scope: s })"
      @toggle-required="live.pushEvent('toggle_required', { id: block.id })"
    >
      <template #config>
        <div class="space-y-1">
          <label class="text-xs font-medium">Placeholder</label>
          <Input
            :model-value="block.config?.placeholder || ''"
            placeholder="Placeholder text..."
            class="h-7 text-xs"
            @blur="(e) => live.pushEvent('update_block_config', { id: block.id, field: 'placeholder', value: e.target.value })"
          />
        </div>
      </template>
    </BlockToolbar>

    <BlockLabel
      :icon="Type"
      :label="label"
      :can-edit="canEdit"
      :is-constant="block.is_constant"
      :required="block.required"
      :detached="block.detached"
      @save="saveLabel"
    >
      <slot name="menu" />
    </BlockLabel>

    <Input v-if="canEdit" v-model="localText" :placeholder="block.config?.placeholder || 'Enter text...'" class="h-9 w-full"
      @blur="save" @keydown.enter="save" />
    <p v-else class="text-sm">{{ content || "—" }}</p>
  </div>
</template>
