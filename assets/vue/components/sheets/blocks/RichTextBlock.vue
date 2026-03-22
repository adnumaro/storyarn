<script setup>
import { computed } from "vue";
import { FileText, Lock } from "lucide-vue-next";
import BlockToolbar from "../BlockToolbar.vue";
import RichTextEditor from "../RichTextEditor.vue";
import { useBlockActions } from "./useBlockActions";

const props = defineProps({
	block: { type: Object, required: true },
	canEdit: { type: Boolean, default: false },
	inherited: { type: Boolean, default: false },
});

const {
	live,
	label,
	editingLabel,
	localLabel,
	labelInput,
	startEditLabel,
	saveLabel,
	isSelected,
	onBlockClick,
} = useBlockActions(props);
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

    <div class="flex items-center justify-between mb-2">
      <div class="flex items-center gap-1.5 text-sm">
        <FileText class="size-3.5 text-muted-foreground" />
        <input v-if="canEdit && editingLabel" ref="labelInput" v-model="localLabel" class="font-medium bg-transparent outline-none border-none px-0 text-sm" @blur="saveLabel" @keydown.enter.prevent="saveLabel" />
        <span v-else class="font-medium" :class="canEdit && 'cursor-text'" @click="startEditLabel">{{ label }}</span>
        <Lock v-if="block.is_constant" class="size-3 text-muted-foreground/50" />
        <span v-if="block.required" class="text-[10px] text-destructive font-medium">required</span>
      </div>
      <slot name="menu" />
    </div>

    <RichTextEditor :content="content" :editable="canEdit" :placeholder="block.config?.placeholder || 'Write something...'"
      @update="(html) => live.pushEvent('update_block_value', { id: block.id, value: html })" />
  </div>
</template>
