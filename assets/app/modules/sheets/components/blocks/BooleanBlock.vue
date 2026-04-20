<script setup lang="ts">
import { ToggleLeft } from "lucide-vue-next";
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import BooleanToggle from "@components/BooleanToggle.vue";
import { Badge } from "@components/ui/badge/index.ts";
import { Checkbox } from "@components/ui/checkbox/index.ts";
import { useBlockActions } from "../../composables/useBlockActions";
import type { Block } from "../../types";
import BlockLabel from "../BlockLabel.vue";
import BlockToolbar from "../BlockToolbar.vue";

const {
  block,
  canEdit = false,
  inherited = false,
} = defineProps<{
  block: Block;
  canEdit?: boolean;
  inherited?: boolean;
}>();

const { t } = useI18n();

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
const mode = computed(() => block.config?.mode || "two_state");

const trueLabel = computed(() => block.config?.true_label || t("sheets.boolean_block.yes"));
const falseLabel = computed(() => block.config?.false_label || t("sheets.boolean_block.no"));
const neutralLabel = computed(() => block.config?.neutral_label || "\u2014");

const booleanLabel = computed(() => {
  if (content.value === true) return trueLabel.value;
  if (content.value === false) return falseLabel.value;
  return neutralLabel.value;
});

function onToggle(value: boolean | null): void {
  live.pushEvent("update_block_value", { id: block.id, value });
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
          <label class="flex items-center gap-2 text-xs">
            <Checkbox
              :model-value="mode === 'tri_state'"
              @update:model-value="
                (v) =>
                  live.pushEvent('update_block_config', {
                    id: block.id,
                    field: 'mode',
                    value: v ? 'tri_state' : 'two_state',
                  })
              "
            />
            {{ $t("sheets.boolean_block.three_states") }}
          </label>
        </div>
        <div class="grid grid-cols-2 gap-2">
          <div class="space-y-1">
            <label class="text-xs font-medium">{{ $t("sheets.boolean_block.true_label") }}</label>
            <input
              :value="block.config?.true_label || ''"
              :placeholder="$t('sheets.boolean_block.yes')"
              class="h-7 w-full text-xs rounded-md border border-input bg-background px-2"
              @blur="
                (e) =>
                  live.pushEvent('update_block_config', {
                    id: block.id,
                    field: 'true_label',
                    value: (e.target as HTMLInputElement).value,
                  })
              "
            />
          </div>
          <div class="space-y-1">
            <label class="text-xs font-medium">{{ $t("sheets.boolean_block.false_label") }}</label>
            <input
              :value="block.config?.false_label || ''"
              :placeholder="$t('sheets.boolean_block.no')"
              class="h-7 w-full text-xs rounded-md border border-input bg-background px-2"
              @blur="
                (e) =>
                  live.pushEvent('update_block_config', {
                    id: block.id,
                    field: 'false_label',
                    value: (e.target as HTMLInputElement).value,
                  })
              "
            />
          </div>
        </div>
        <div v-if="mode === 'tri_state'" class="space-y-1">
          <label class="text-xs font-medium">{{ $t("sheets.boolean_block.neutral_label") }}</label>
          <input
            :value="block.config?.neutral_label || ''"
            :placeholder="$t('sheets.boolean_block.neutral')"
            class="h-7 w-full text-xs rounded-md border border-input bg-background px-2"
            @blur="
              (e) =>
                live.pushEvent('update_block_config', {
                  id: block.id,
                  field: 'neutral_label',
                  value: (e.target as HTMLInputElement).value,
                })
            "
          />
        </div>
      </template>
    </BlockToolbar>

    <BlockLabel
      :icon="ToggleLeft"
      :label="label"
      :can-edit="canEdit"
      :is-constant="block.is_constant"
      :required="block.required"
      :detached="block.detached"
      @save="saveLabel"
    >
      <slot name="menu" />
    </BlockLabel>

    <!-- Editable (two-state switch or tri-state cycle button) -->
    <BooleanToggle
      v-if="canEdit"
      :value="content"
      :mode="mode"
      :true-label="trueLabel"
      :false-label="falseLabel"
      :neutral-label="neutralLabel"
      @update:value="onToggle"
    />

    <!-- Read-only -->
    <Badge
      v-else
      :variant="content === true ? 'default' : content === false ? 'destructive' : 'secondary'"
    >
      {{ booleanLabel }}
    </Badge>
  </div>
</template>
