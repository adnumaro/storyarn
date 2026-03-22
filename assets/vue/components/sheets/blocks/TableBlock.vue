<script setup>
import { computed } from "vue";
import { Table2, ChevronRight, ChevronDown, Lock } from "lucide-vue-next";
import BlockToolbar from "../BlockToolbar.vue";
import TableGrid from "./TableGrid.vue";
import { useBlockActions } from "./useBlockActions";
import BlockLabel from '@/vue/components/sheets/blocks/BlockLabel.vue'

const props = defineProps({
	block: { type: Object, required: true },
	canEdit: { type: Boolean, default: false },
	inherited: { type: Boolean, default: false },
});

const {
	live,
	label,
	isSelected,
	onBlockClick,
} = useBlockActions(props);

// can_manage: can modify table structure (add/delete/rename columns/rows, collapse)
// When inherited (schema_locked): structure is locked but cell values are still editable
const canManage = computed(() => props.canEdit && !props.inherited);

const collapsed = computed(() => props.block.collapsed || false);
const columns = computed(() => props.block.columns || []);
const rows = computed(() => props.block.rows || []);

const summary = computed(() => {
	const c = columns.value.length;
	const r = rows.value.length;
	return `${r} row${r !== 1 ? "s" : ""}, ${c} column${c !== 1 ? "s" : ""}`;
});

function saveLabel(val) {
  live.pushEvent("update_block_config", {
    id: props.block.id,
    field: "label",
    value: val,
  });
}

function toggleCollapse() {
	live.pushEvent("toggle_table_collapse", { "block-id": props.block.id });
}
</script>

<template>
  <div
    class="group relative rounded-lg border p-4 pt-5 transition-colors"
    :class="isSelected ? 'border-primary ring-1 ring-primary/30' : 'border-border hover:border-foreground/20'"
    @click="onBlockClick"
  >
    <BlockToolbar v-if="canManage"
      :is-constant="block.is_constant" :is-variable="!block.is_constant && !!block.variable_name"
      :variable-name="block.variable_name || ''" :show-scope="!inherited"
      :scope="block.scope || 'self'" :required="block.required"
      @toggle-constant="live.pushEvent('toggle_constant', { id: block.id })"
      @update-variable-name="(v) => live.pushEvent('update_variable_name', { id: block.id, variable_name: v })"
      @change-scope="(s) => live.pushEvent('change_block_scope', { id: block.id, scope: s })"
      @toggle-required="live.pushEvent('toggle_required', { id: block.id })"
    />

    <!-- Header: chevron + icon + label (canManage mode) -->
    <div v-if="canManage" class="flex items-center gap-1.5 text-sm mb-1 group/header mb-2">
      <button
        type="button"
        class="flex items-center justify-center shrink-0 cursor-pointer size-5"
        @click.stop="toggleCollapse"
      >
        <component :is="collapsed ? ChevronRight : ChevronDown" class="size-3 text-muted-foreground/40 hover:text-muted-foreground/70" />
      </button>
      <BlockLabel
        :icon="Table2"
        :label="label"
        :can-edit="canEdit"
        :is-constant="block.is_constant"
        :required="block.required"
        :detached="block.detached"
        class="m-0!"
        @save="saveLabel"
      >
        <slot name="menu" />
      </BlockLabel>
    </div>

    <!-- Header: read-only (inherited or viewer) -->
    <label v-if="!canManage && label" class="text-sm text-muted-foreground/70 mb-1 flex items-center gap-1.5">
      <Table2 class="size-3.5 text-muted-foreground/50" />
      <span>{{ label }}</span>
    </label>

    <!-- Table grid (only when not collapsed, or when not canManage) -->
    <TableGrid
      v-if="!collapsed || !canManage"
      :block-id="block.id"
      :columns="columns"
      :rows="rows"
      :can-edit="canEdit"
      :can-manage="canManage"
    />
  </div>
</template>
