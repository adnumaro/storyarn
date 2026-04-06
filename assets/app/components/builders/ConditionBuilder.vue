<script setup>
/**
 * Variable condition editor — block-format condition builder.
 * Wraps in .condition-builder for sentence-flow CSS.
 */

import { Group, Plus } from "lucide-vue-next";
import { computed, ref, watch } from "vue";
import { generateId } from "@modules/shared/variables.js";
import ConditionBlock from "@components/builders/condition/ConditionBlock.vue";
import ConditionGroup from "@components/builders/condition/ConditionGroup.vue";
import LogicToggle from "@components/builders/condition/LogicToggle.vue";

const { condition, variables, disabled, switchMode } = defineProps({
  condition: { type: [Object, Array, null], default: null },
  variables: { type: Array, default: () => [] },
  disabled: { type: Boolean, default: false },
  switchMode: { type: Boolean, default: false },
});

const emit = defineEmits(["update:condition"]);

function ensureBlockFormat(condition) {
  if (!condition) return { logic: "all", blocks: [] };
  if (condition.blocks) return condition;
  const rules = condition.rules || [];
  if (rules.length === 0) return { logic: "all", blocks: [] };
  return {
    logic: "all",
    blocks: [
      {
        id: generateId("block"),
        type: "block",
        logic: condition.logic || "all",
        rules: [...rules],
      },
    ],
  };
}

const internalCondition = ref(ensureBlockFormat(condition));
watch(
  () => condition,
  (v) => {
    internalCondition.value = ensureBlockFormat(v);
  },
  { deep: true },
);

const selectionMode = ref(false);
const selectedBlockIds = ref(new Set());
const blocks = computed(() => internalCondition.value.blocks || []);
const standAloneBlockCount = computed(() => blocks.value.filter((b) => b.type === "block").length);

function emitUpdate() {
  emit("update:condition", { ...internalCondition.value });
}

function updateTopLogic(logic) {
  internalCondition.value = { ...internalCondition.value, logic };
  emitUpdate();
}

function updateBlock(index, updatedBlock) {
  const b = [...blocks.value];
  b[index] = updatedBlock;
  internalCondition.value = { ...internalCondition.value, blocks: b };
  emitUpdate();
}

function removeBlock(index) {
  internalCondition.value = {
    ...internalCondition.value,
    blocks: blocks.value.filter((_, i) => i !== index),
  };
  emitUpdate();
}

function addBlock() {
  const newBlock = {
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
  if (switchMode) newBlock.label = "";
  internalCondition.value = {
    ...internalCondition.value,
    blocks: [...blocks.value, newBlock],
  };
  emitUpdate();
}

function ungroupGroup(index) {
  const inner = blocks.value[index].blocks || [];
  const b = [...blocks.value];
  b.splice(index, 1, ...inner);
  internalCondition.value = { ...internalCondition.value, blocks: b };
  emitUpdate();
}

function enterSelectionMode() {
  selectionMode.value = true;
  selectedBlockIds.value = new Set();
}
function cancelSelectionMode() {
  selectionMode.value = false;
  selectedBlockIds.value = new Set();
}

function toggleBlockSelection(blockId) {
  const ids = new Set(selectedBlockIds.value);
  if (ids.has(blockId)) {
    ids.delete(blockId);
  } else {
    ids.add(blockId);
  }
  selectedBlockIds.value = ids;
}

function groupSelectedBlocks() {
  if (selectedBlockIds.value.size < 2) return;
  const selected = [],
    remaining = [];
  let insertIdx = -1;
  blocks.value.forEach((block, i) => {
    if (block.type === "block" && selectedBlockIds.value.has(block.id)) {
      selected.push(block);
      if (insertIdx === -1) insertIdx = i;
    } else remaining.push(block);
  });
  if (selected.length < 2) return;
  remaining.splice(insertIdx, 0, {
    id: generateId("group"),
    type: "group",
    logic: "all",
    blocks: selected,
  });
  internalCondition.value = { ...internalCondition.value, blocks: remaining };
  selectionMode.value = false;
  selectedBlockIds.value = new Set();
  emitUpdate();
}
</script>

<template>
  <div class="condition-builder space-y-2">
    <LogicToggle
      v-if="blocks.length >= 2 && !switchMode"
      :logic="internalCondition.logic"
      of-label="of the blocks"
      :disabled="disabled"
      class="mb-2"
      @update:logic="updateTopLogic"
    />

    <p v-if="switchMode && blocks.length > 0" class="text-xs text-muted-foreground mb-2">
      Each condition creates an output. First match wins.
    </p>

    <div class="space-y-2">
      <div v-for="(item, index) in blocks" :key="item.id" class="relative">
        <!-- Selection mode -->
        <label
          v-if="selectionMode && item.type === 'block'"
          class="flex items-start gap-2 cursor-pointer"
        >
          <input
            type="checkbox"
            class="mt-2 size-3.5 accent-primary"
            :checked="selectedBlockIds.has(item.id)"
            @change="toggleBlockSelection(item.id)"
          />
          <div class="flex-1">
            <ConditionBlock
              :block="item"
              :variables="variables"
              :disabled="disabled"
              :switch-mode="switchMode"
              @update:block="(b) => updateBlock(index, b)"
              @remove="removeBlock(index)"
            />
          </div>
        </label>

        <!-- Normal -->
        <template v-else>
          <ConditionGroup
            v-if="item.type === 'group'"
            :group="item"
            :variables="variables"
            :disabled="disabled"
            @update:group="(g) => updateBlock(index, g)"
            @ungroup="ungroupGroup(index)"
          />
          <ConditionBlock
            v-else
            :block="item"
            :variables="variables"
            :disabled="disabled"
            :switch-mode="switchMode"
            @update:block="(b) => updateBlock(index, b)"
            @remove="removeBlock(index)"
          />
        </template>
      </div>
    </div>

    <div v-if="!disabled" class="flex items-center gap-2 mt-2">
      <template v-if="selectionMode">
        <button
          type="button"
          class="inline-flex items-center gap-1 px-2 py-1 text-xs rounded bg-primary text-primary-foreground hover:bg-primary/90 disabled:opacity-50"
          :disabled="selectedBlockIds.size < 2"
          @click="groupSelectedBlocks"
        >
          <Group class="size-3" /> Group selected ({{ selectedBlockIds.size }})
        </button>
        <button
          type="button"
          class="inline-flex items-center px-2 py-1 text-xs text-muted-foreground rounded hover:bg-accent transition-colors"
          @click="cancelSelectionMode"
        >
          Cancel
        </button>
      </template>
      <template v-else>
        <button
          type="button"
          class="inline-flex items-center gap-1 px-2 py-1 text-xs text-muted-foreground border border-dashed border-border rounded hover:bg-accent/50 transition-colors"
          @click="addBlock"
        >
          <Plus class="size-3" /> Add block
        </button>
        <button
          v-if="!switchMode && standAloneBlockCount >= 2"
          type="button"
          class="inline-flex items-center gap-1 px-2 py-1 text-xs text-muted-foreground rounded hover:bg-accent transition-colors"
          @click="enterSelectionMode"
        >
          <Group class="size-3" /> Group
        </button>
      </template>
    </div>

    <p v-if="blocks.length === 0 && disabled" class="text-xs text-muted-foreground italic">
      No conditions set
    </p>
  </div>
</template>
