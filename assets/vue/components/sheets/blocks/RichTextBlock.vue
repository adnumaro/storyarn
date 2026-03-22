<script setup>
import { computed } from "vue";
import { FileText } from "lucide-vue-next";
import BlockToolbar from "../BlockToolbar.vue";
import BlockLabel from "./BlockLabel.vue";
import RichTextEditor from "../RichTextEditor.vue";
import { useBlockActions } from "./useBlockActions";

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

const content = computed(() => props.block.value?.content || "");
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
        <div class="space-y-1"><label class="text-xs font-medium">Placeholder</label>
          <input :value="block.config?.placeholder || ''" placeholder="Write something..." class="h-7 w-full text-xs rounded-md border border-input bg-background px-2"
            @blur="(e) => live.pushEvent('update_block_config', { id: block.id, field: 'placeholder', value: e.target.value })" /></div>
      </template>
    </BlockToolbar>

    <BlockLabel :icon="FileText" :label="label" :can-edit="canEdit" :is-constant="block.is_constant" :required="block.required" :detached="block.detached" @save="saveLabel">
      <slot name="menu" />
    </BlockLabel>

    <RichTextEditor :content="content" :editable="canEdit" :placeholder="block.config?.placeholder || 'Write something...'"
      @update="(html) => live.pushEvent('update_block_value', { id: block.id, value: html })" />
  </div>
</template>
