<script setup lang="ts">
import { FileText } from "lucide-vue-next";
import { computed } from "vue";
import { useBlockActions } from "../../../composables/useBlockActions";
import type { Block } from "../../../types";
import BlockLabel from "../../BlockLabel.vue";
import BlockToolbar from "../../BlockToolbar.vue";
import RichTextEditor from "./RichTextEditor.vue";
import { Input } from '@components/ui/input'
import { useId } from 'reka-ui'

const {
  block,
  canEdit = false,
  inherited = false,
} = defineProps<{
  block: Block;
  canEdit?: boolean;
  inherited?: boolean;
}>();

const { live, label, isSelected, onBlockClick } = useBlockActions({
  get block() {
    return block;
  },
  get canEdit() {
    return canEdit;
  },
});

function saveLabel(val: string): void {
  live.pushEvent("update_block_config", {
    id: block.id,
    field: "label",
    value: val,
  });
}

const content = computed(() => (block.value?.content as string) || "");
</script>

<template>
  <div
    class="group relative rounded-lg border p-4 pt-5 transition-colors"
    :class="
      isSelected
        ? 'border-primary ring-1 ring-primary/30'
        : 'border-border hover:border-foreground/20'
    "
    @click="onBlockClick"
  >
    <BlockToolbar
      v-if="canEdit"
      :block-id="block.id"
      :is-constant="block.is_constant"
      :is-variable="!block.is_constant && !!block.variable_name"
      :variable-name="block.variable_name || ''"
      :show-scope="!inherited"
      :scope="block.scope || 'self'"
      :required="block.required"
      @toggle-constant="live.pushEvent('toggle_constant', { id: block.id })"
      @update-variable-name="
        (v) => live.pushEvent('update_variable_name', { id: block.id, variable_name: v })
      "
      @change-scope="(s) => live.pushEvent('change_block_scope', { id: block.id, scope: s })"
      @toggle-required="live.pushEvent('toggle_required', { id: block.id })"
    >
      <template #config>
        <div class="space-y-1">
          <label :for="`placeholder-${useId()}`" class="text-xs font-medium">Placeholder</label>
          <Input
            :id="`placeholder-${useId()}`"
            :value="block.config?.placeholder || ''"
            placeholder="Write something..."
            size="xs"
            class="bg-background dark:bg-background"
            @blur="
             (e: Event) =>
                live.pushEvent('update_block_config', {
                  id: block.id,
                  field: 'placeholder',
                  value: (e.target as HTMLInputElement).value,
                })
            "
          />
        </div>
      </template>
    </BlockToolbar>

    <BlockLabel
      :icon="FileText"
      :label="label"
      :can-edit="canEdit"
      :is-constant="block.is_constant"
      :required="block.required"
      :detached="block.detached"
      @save="saveLabel"
    >
      <slot name="menu" />
    </BlockLabel>

    <RichTextEditor
      :content="content"
      :editable="canEdit"
      :placeholder="block.config?.placeholder || 'Write something...'"
      @update="(html) => live.pushEvent('update_block_value', { id: block.id, value: html })"
    />
  </div>
</template>
