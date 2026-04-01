<script setup>
import { DnDProvider } from "@vue-dnd-kit/core";
import { ArrowUpRight, Link2Off } from "lucide-vue-next";
import { onMounted, onUnmounted, provide, ref } from "vue";
import UserAvatar from "@components/layout/UserAvatar.vue";
import { useLive } from "@composables/useLive.js";
import AddBlockMenu from "./AddBlockMenu.vue";
import BooleanBlock from "./blocks/BooleanBlock.vue";
import DateBlock from "./blocks/DateBlock.vue";
import FormulaPanel from "./blocks/FormulaPanel.vue";
import GalleryBlock from "./blocks/galleryBlock/GalleryBlock.vue";
import MultiSelectBlock from "./blocks/MultiSelectBlock.vue";
import NumberBlock from "./blocks/NumberBlock.vue";
import ReferenceBlock from "./blocks/ReferenceBlock.vue";
import RichTextBlock from "./blocks/richText/RichTextBlock.vue";
import SelectBlock from "./blocks/SelectBlock.vue";
import TableBlock from "./blocks/table/TableBlock.vue";
// Block type components (for inherited blocks, rendered without sortable)
import TextBlock from "./blocks/table/TextBlock.vue";
import SortableBlockList from "./sortable/SortableBlockList.vue";

const blockComponents = {
  text: TextBlock,
  number: NumberBlock,
  boolean: BooleanBlock,
  select: SelectBlock,
  multi_select: MultiSelectBlock,
  date: DateBlock,
  rich_text: RichTextBlock,
  gallery: GalleryBlock,
  table: TableBlock,
  reference: ReferenceBlock,
};

const { blocks, inheritedGroups, canEdit, workspaceSlug, projectSlug, formulaEditing, blockLocks, currentUserId } = defineProps({
  blocks: { type: Array, default: () => [] },
  inheritedGroups: { type: Array, default: () => [] },
  canEdit: { type: Boolean, default: false },
  workspaceSlug: { type: String, default: "" },
  projectSlug: { type: String, default: "" },
  formulaEditing: { type: Object, default: null },
  blockLocks: { type: Object, default: () => ({}) },
  currentUserId: { type: Number, default: null },
});

const live = useLive();

// ── Block locking ──
let lockHeartbeatInterval = null;
const lockedBlockId = ref(null);

function isLockedByOther(blockId) {
  const lock = blockLocks[String(blockId)];
  return lock && lock.userId !== currentUserId;
}

function lockInfo(blockId) {
  return blockLocks[String(blockId)] || null;
}

function acquireLock(blockId) {
  if (!canEdit || isLockedByOther(blockId)) return;
  lockedBlockId.value = blockId;
  live.pushEvent("acquire_block_lock", { block_id: blockId });
  clearInterval(lockHeartbeatInterval);
  lockHeartbeatInterval = setInterval(() => {
    live.pushEvent("refresh_block_lock", { block_id: blockId });
  }, 10000);
}

function releaseLock() {
  if (lockedBlockId.value) {
    live.pushEvent("release_block_lock", { block_id: lockedBlockId.value });
    lockedBlockId.value = null;
  }
  clearInterval(lockHeartbeatInterval);
  lockHeartbeatInterval = null;
}

provide("blockLocks", () => blockLocks);
provide("currentUserId", () => currentUserId);
provide("isLockedByOther", isLockedByOther);
provide("lockInfo", lockInfo);

// ── Block selection ──
const selectedBlockId = ref(null);

function selectBlock(id) {
  if (isLockedByOther(id)) return;
  // Release previous lock
  if (selectedBlockId.value && selectedBlockId.value !== id) {
    releaseLock();
  }
  selectedBlockId.value = selectedBlockId.value === id ? null : id;
  if (selectedBlockId.value && canEdit) {
    acquireLock(selectedBlockId.value);
  } else {
    releaseLock();
  }
}

function deselectBlock() {
  releaseLock();
  selectedBlockId.value = null;
}

provide("selectedBlockId", selectedBlockId);
provide("selectBlock", selectBlock);

function isInputFocused() {
  const el = document.activeElement;
  if (!el) return false;
  const tag = el.tagName;
  return tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT" || el.isContentEditable;
}

function onKeydown(e) {
  if (!selectedBlockId.value || !canEdit || isInputFocused()) return;

  if (e.key === "Backspace" || e.key === "Delete") {
    e.preventDefault();
    live.pushEvent("delete_block", { id: selectedBlockId.value });
    selectedBlockId.value = null;
  }

  if ((e.metaKey || e.ctrlKey) && e.key === "d") {
    e.preventDefault();
    live.pushEvent("duplicate_block", { id: selectedBlockId.value });
  }

  if (e.key === "Escape") {
    deselectBlock();
  }
}

function onUndoRedo(e) {
  if (!(e.metaKey || e.ctrlKey) || isInputFocused()) return;

  if (e.key === "z" && !e.shiftKey) {
    e.preventDefault();
    live.pushEvent("undo", {});
  }

  if ((e.key === "z" && e.shiftKey) || e.key === "y") {
    e.preventDefault();
    live.pushEvent("redo", {});
  }
}

onMounted(() => {
  document.addEventListener("keydown", onKeydown);
  document.addEventListener("keydown", onUndoRedo);

  live.handleEvent("block_lock_denied", ({ blockId }) => {
    if (selectedBlockId.value === blockId) {
      selectedBlockId.value = null;
      lockedBlockId.value = null;
    }
  });
});
onUnmounted(() => {
  document.removeEventListener("keydown", onKeydown);
  document.removeEventListener("keydown", onUndoRedo);
  releaseLock();
});

function addBlock({ type, scope }) {
  live.pushEvent("add_block", { type, scope });
}

function deleteBlock(id) {
  live.pushEvent("delete_block", { id });
}

function detachBlock(id) {
  live.pushEvent("detach_block", { id });
}

function resolveComponent(type) {
  return blockComponents[type] || null;
}
</script>

<template>
  <DnDProvider>
    <div class="space-y-3">
      <!-- ═══ INHERITED BLOCKS (grouped by source sheet) ═══ -->
      <div v-for="group in inheritedGroups" :key="group.sourceSheet.id" class="mb-4">
        <div
          class="flex items-center gap-2 mb-2 text-xs text-muted-foreground uppercase tracking-wider"
        >
          <ArrowUpRight class="size-3 text-blue-400" />
          <span>Inherited from</span>
          <a
            :href="`/workspaces/${workspaceSlug}/projects/${projectSlug}/sheets/${group.sourceSheet.id}`"
            class="text-primary hover:underline font-medium normal-case"
          >
            {{ group.sourceSheet.name }}
          </a>
          <span class="text-muted-foreground/50">({{ group.blocks.length }})</span>
        </div>

        <div class="border-l-2 border-blue-400/30 ml-1 pl-3 space-y-3">
          <div v-for="block in group.blocks" :key="block.id" class="relative">
            <component
              :is="resolveComponent(block.type)"
              :block="block"
              :can-edit="canEdit && !isLockedByOther(block.id)"
              :inherited="true"
            >
              <template #menu>
                <div class="flex items-center gap-0.5">
                  <button
                    v-if="canEdit && !isLockedByOther(block.id)"
                    type="button"
                    class="size-6 rounded flex items-center justify-center text-blue-500 hover:bg-blue-500/10 transition-colors"
                    title="Detach from parent"
                    @click.stop="detachBlock(block.id)"
                  >
                    <Link2Off class="size-3.5" />
                  </button>
                  <UserAvatar
                    v-if="isLockedByOther(block.id)"
                    :email="lockInfo(block.id)?.userEmail"
                    :color="lockInfo(block.id)?.userColor"
                    size="xs"
                  />
                </div>
              </template>
            </component>
            <div
              v-if="isLockedByOther(block.id)"
              class="absolute inset-0 rounded-lg border-2 pointer-events-none"
              :style="{ borderColor: lockInfo(block.id)?.userColor }"
            />
          </div>
        </div>
      </div>

      <!-- ═══ OWN PROPERTIES SEPARATOR ═══ -->
      <div v-if="inheritedGroups.length > 0" class="flex items-center gap-3 py-2">
        <div class="h-px flex-1 bg-border" />
        <span class="text-xs text-muted-foreground uppercase tracking-wider">Own properties</span>
        <div class="h-px flex-1 bg-border" />
      </div>

      <!-- ═══ OWN BLOCKS (sortable) ═══ -->
      <SortableBlockList :layout-items="blocks" :can-edit="canEdit" />

      <div
        v-if="blocks.length === 0 && inheritedGroups.length === 0 && !canEdit"
        class="py-8 text-center text-sm text-muted-foreground"
      >
        No blocks yet.
      </div>

      <AddBlockMenu v-if="canEdit" @select="addBlock" />
    </div>

    <FormulaPanel :formula-editing="formulaEditing" />
  </DnDProvider>
</template>
