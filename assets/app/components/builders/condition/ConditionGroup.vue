<script setup lang="ts">
/**
 * Condition group — colored left border, group-level AND/OR, ungroup action.
 */

import { Plus, Ungroup } from "lucide-vue-next";
import { generateId } from "@modules/shared/variables";
import type { Variable } from "@modules/shared/variables";
import type {
  ConditionBlock as ConditionBlockType,
  ConditionGroup as ConditionGroupType,
} from "../types";
import ConditionBlock from "./ConditionBlock.vue";
import LogicToggle from "./LogicToggle.vue";

const {
  group,
  variables = [],
  disabled = false,
} = defineProps<{
  group: ConditionGroupType;
  variables?: Variable[];
  disabled?: boolean;
}>();

const emit = defineEmits<{
  "update:group": [group: ConditionGroupType];
  ungroup: [];
}>();

function updateBlock(index: number, updatedBlock: ConditionBlockType) {
  const blocks = [...group.blocks];
  blocks[index] = updatedBlock;
  emit("update:group", { ...group, blocks });
}

function removeBlock(index: number) {
  const blocks = group.blocks.filter((_, i) => i !== index);
  emit("update:group", { ...group, blocks });
}

function addBlock() {
  const newBlock: ConditionBlockType = {
    id: generateId("block"),
    type: "block",
    logic: "all",
    rules: [
      {
        id: generateId("rule"),
        sheet: null,
        variable: null,
        operator: "equals",
        value: null,
      },
    ],
  };
  const blocks = [...group.blocks, newBlock];
  emit("update:group", { ...group, blocks });
}

function updateLogic(newLogic: "all" | "any") {
  emit("update:group", { ...group, logic: newLogic });
}
</script>

<template>
  <div class="border-l-4 border-primary/30 pl-3 py-1 rounded-r-lg bg-muted/30">
    <div class="flex items-center justify-between mb-2">
      <div class="flex items-center gap-2">
        <LogicToggle
          v-if="group.blocks.length >= 2"
          :logic="group.logic"
          of-label="of the blocks in the group"
          :disabled="disabled"
          @update:logic="updateLogic"
        />
        <span v-else class="text-xs text-muted-foreground font-medium">Group</span>
      </div>
      <button
        v-if="!disabled"
        type="button"
        class="inline-flex items-center gap-1 px-2 py-1 text-xs text-muted-foreground rounded hover:bg-accent transition-colors"
        @click="emit('ungroup')"
      >
        <Ungroup class="size-3" />
        Ungroup
      </button>
    </div>

    <div class="space-y-2">
      <ConditionBlock
        v-for="(block, index) in group.blocks"
        :key="block.id"
        :block="block"
        :variables="variables"
        :disabled="disabled"
        :switch-mode="false"
        @update:block="(b) => updateBlock(index, b)"
        @remove="removeBlock(index)"
      />
    </div>

    <button
      v-if="!disabled"
      type="button"
      class="inline-flex items-center gap-1 mt-1 px-2 py-1 text-xs text-muted-foreground border border-dashed border-border rounded hover:bg-accent/50 transition-colors"
      @click="addBlock"
    >
      <Plus class="size-3" />
      Add block
    </button>
  </div>
</template>
