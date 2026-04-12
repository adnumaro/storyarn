<script setup lang="ts">
import { Hash } from "lucide-vue-next";
import { computed, ref, watch } from "vue";
import { Input } from "@components/ui/input/index.ts";
import { useBlockActions } from "../../composables/useBlockActions";
import type { Block } from "../../types";
import BlockLabel from "../BlockLabel.vue";
import BlockToolbar from "../BlockToolbar.vue";
import { useId } from 'reka-ui'
import { generateId } from '@modules/shared/variables.ts'

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

const content = computed(() => {
  const raw = block.value?.content;
  if (typeof raw === "string" || typeof raw === "number") return raw;
  return null;
});
const localNumber = ref<string | number>(content.value ?? "");
watch(content, (v) => {
  localNumber.value = v ?? "";
});

function save(): void {
  const raw = localNumber.value;
  const val = raw === "" || raw === null ? null : Number(raw);
  if (!Number.isNaN(val) && val !== content.value) {
    live.pushEvent("update_block_value", { id: block.id, value: val });
  }
}

function onKeydown(e: KeyboardEvent): void {
  if (e.key === "e" || e.key === "E" || e.key === "+") e.preventDefault();
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
            :model-value="block.config?.placeholder || ''"
            placeholder="Default value..."
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
        <div class="grid grid-cols-3 gap-2">
          <div class="space-y-1">
            <label :for="`min-${useId()}`" class="text-xs font-medium">Min</label>
            <Input
              :id="`min-${useId()}`"
              type="number"
              :model-value="block.config?.min ?? ''"
              size="xs"
              @blur="
                (e: Event) =>
                  live.pushEvent('update_block_config', {
                    id: block.id,
                    field: 'min',
                    value:
                      (e.target as HTMLInputElement).value === ''
                        ? null
                        : Number((e.target as HTMLInputElement).value),
                  })
              "
            />
          </div>
          <div class="space-y-1">
            <label :for="`max-${useId()}`" class="text-xs font-medium">Max</label>
            <Input
              :id="`max-${useId()}`"
              type="number"
              :model-value="block.config?.max ?? ''"
              size="xs"
              @blur="
                (e: Event) =>
                  live.pushEvent('update_block_config', {
                    id: block.id,
                    field: 'max',
                    value:
                      (e.target as HTMLInputElement).value === ''
                        ? null
                        : Number((e.target as HTMLInputElement).value),
                  })
              "
            />
          </div>
          <div class="space-y-1">
            <label :for="`step-${useId()}`" class="text-xs font-medium">Step</label>
            <Input
              :id="`step-${useId()}`"
              type="number"
              :model-value="block.config?.step ?? 1"
              size="xs"
              @blur="
                (e: Event) =>
                  live.pushEvent('update_block_config', {
                    id: block.id,
                    field: 'step',
                    value:
                      (e.target as HTMLInputElement).value === ''
                        ? null
                        : Number((e.target as HTMLInputElement).value),
                  })
              "
            />
          </div>
        </div>
      </template>
    </BlockToolbar>

    <BlockLabel
      :icon="Hash"
      :label="label"
      :can-edit="canEdit"
      :is-constant="block.is_constant"
      :required="block.required"
      :detached="block.detached"
      @save="saveLabel"
    >
      <slot name="menu" />
    </BlockLabel>

    <Input
      v-if="canEdit"
      v-model="localNumber"
      type="number"
      :placeholder="block.config?.placeholder || '0'"
      :min="block.config?.min"
      :max="block.config?.max"
      :step="block.config?.step || 'any'"
      class="w-full"
      @blur="save"
      @keydown.enter="save"
      @keydown="onKeydown"
    />
    <p v-else class="text-sm tabular-nums">{{ content ?? "\u2014" }}</p>
  </div>
</template>
