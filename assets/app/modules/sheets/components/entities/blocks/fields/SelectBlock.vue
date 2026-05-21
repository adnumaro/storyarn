<script setup lang="ts">
import { ChevronDown, CircleDot, Check } from "lucide-vue-next";
import { computed } from "vue";
import { Input } from "@components/ui/input";
import { useBlockActions } from "../../../../composables/useBlockActions";
import type { Block } from "../../../../types";
import BlockLabel from "../BlockLabel.vue";
import BlockToolbar from "../BlockToolbar.vue";
import OptionEditor from "../OptionEditor.vue";
import { useId } from "reka-ui";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";
import { generateId } from "../../../../../../shared/domain/variables.ts";

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

const content = computed(() => block.value?.content);
const options = computed(() => block.config?.options || []);
const placeholder = computed(() => block.config?.placeholder || "");

const displayValue = computed(() => {
  if (!content.value) return null;
  const opt = options.value.find((o) => o.key === content.value);
  return opt?.value || content.value;
});

function onChange(val: string | string[]): void {
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
          <label :for="`placeholder-${useId()}`" class="text-xs font-medium">{{
            $t("sheets.select_block.placeholder_label")
          }}</label>
          <Input
            :id="`placeholder-${useId()}`"
            :model-value="block.config?.placeholder || ''"
            :placeholder="$t('sheets.select_block.placeholder')"
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
        <OptionEditor scope="block" :id="block.id" :options="options" />
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

    <Popover v-if="canEdit">
      <PopoverTrigger as-child>
        <button
          :id="`select-trigger-${block.id}-${generateId()}`"
          class="flex justify-between flex-wrap gap-1 min-h-9 w-full rounded-md border border-input bg-card px-3 py-2 text-sm items-center"
        >
          <span>
            <span v-if="content">{{ options.find((opt) => opt.key === content)?.value }}</span>
            <span v-else class="text-muted-foreground">{{
              placeholder || $t("sheets.select_block.placeholder")
            }}</span>
          </span>
          <ChevronDown class="h-4 w-4 opacity-50" />
        </button>
      </PopoverTrigger>
      <PopoverContent align="start" class="w-(--reka-popover-trigger-width) p-1">
        <div class="max-h-48 overflow-y-auto">
          <div v-if="options.length === 0" class="text-muted-foreground p-2">
            {{ $t("sheets.select_block.no_options") }}
          </div>
          <button
            v-else
            type="button"
            class="flex items-center gap-2 w-full px-2 py-1.5 text-sm rounded hover:bg-accent transition-colors"
            @click="onChange(' ')"
          >
            <span class="text-muted-foreground">{{ $t("sheets.select_block.none") }}</span>
          </button>
          <button
            v-for="opt in options"
            :key="opt.key"
            type="button"
            class="flex items-center justify-between gap-2 w-full px-2 py-1.5 text-sm rounded hover:bg-accent transition-colors"
            @click="onChange(opt.key)"
          >
            {{ opt.value }}
            <Check v-if="content === opt.key" class="h-4 w-4 opacity-50" />
          </button>
        </div>
      </PopoverContent>
    </Popover>
    <p v-else class="text-sm">{{ displayValue || "\u2014" }}</p>
  </div>
</template>
