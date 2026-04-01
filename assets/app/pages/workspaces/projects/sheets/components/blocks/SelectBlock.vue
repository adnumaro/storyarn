<script setup>
import { CircleDot } from "lucide-vue-next";
import { computed } from "vue";
import { Input } from "@components/ui/input/index.js";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@components/ui/select/index.js";
import { useBlockActions } from "../../composables/useBlockActions.js";
import BlockLabel from "../BlockLabel.vue";
import BlockToolbar from "../BlockToolbar.vue";
import OptionEditor from "../OptionEditor.vue";

const { block, canEdit, inherited } = defineProps({
  block: { type: Object, required: true },
  canEdit: { type: Boolean, default: false },
  inherited: { type: Boolean, default: false },
});

const { live, label, isSelected, onBlockClick } = useBlockActions({ get block() { return block; }, get canEdit() { return canEdit; } });

function saveLabel(val) {
  live.pushEvent("update_block_config", {
    id: block.id,
    field: "label",
    value: val,
  });
}

const content = computed(() => block.value?.content);
const options = computed(() => block.config?.options || []);
const placeholder = computed(() => block.config?.placeholder || "Select...");

const displayValue = computed(() => {
  if (!content.value) return null;
  const opt = options.value.find((o) => o.key === content.value);
  return opt?.value || content.value;
});

function onChange(val) {
  live.pushEvent("update_block_value", {
    id: block.id,
    value: val === " " ? null : val,
  });
}
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
        <OptionEditor :block-id="block.id" :options="options" />
        <div class="space-y-1">
          <label class="text-xs font-medium">Placeholder</label>
          <Input
            :model-value="block.config?.placeholder || ''"
            placeholder="Select..."
            class="h-7 text-xs"
            @blur="
              (e) =>
                live.pushEvent('update_block_config', {
                  id: block.id,
                  field: 'placeholder',
                  value: e.target.value,
                })
            "
          />
        </div>
      </template>
    </BlockToolbar>

    <BlockLabel
      :icon="CircleDot"
      :label="label"
      :can-edit="canEdit"
      :is-constant="block.is_constant"
      :required="block.required"
      :detached="block.detached"
      @save="saveLabel"
    >
      <slot name="menu" />
    </BlockLabel>

    <Select v-if="canEdit" :model-value="content || ''" @update:model-value="onChange">
      <SelectTrigger class="h-9 w-full"><SelectValue :placeholder="placeholder" /></SelectTrigger>
      <SelectContent>
        <SelectItem value=" "><span class="text-muted-foreground">None</span></SelectItem>
        <SelectItem v-for="opt in options" :key="opt.key" :value="opt.key">{{
          opt.value
        }}</SelectItem>
      </SelectContent>
    </Select>
    <p v-else class="text-sm">{{ displayValue || "—" }}</p>
  </div>
</template>
