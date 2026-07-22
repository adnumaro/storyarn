<script setup lang="ts">
import { DnDProvider } from "@vue-dnd-kit/core";
import { ArrowUpRight, Link2Off } from "lucide-vue-next";
import { onMounted, onUnmounted, provide, ref } from "vue";
import UserAvatar from "../../../../../components/UserAvatar.vue";
import { useLive } from "../../../../../shared/composables/useLive";
import type { BlockLock, FormulaEditing, InheritedBlockGroup, LayoutItem } from "../../../types";
import AddBlockMenu from "./AddBlockMenu.vue";
import BooleanBlock from "./fields/BooleanBlock.vue";
import DateBlock from "./fields/DateBlock.vue";
import FormulaPanel from "../../panels/FormulaPanel.vue";
import GalleryBlock from "./fields/galleryBlock/GalleryBlock.vue";
import MultiSelectBlock from "./fields/MultiSelectBlock.vue";
import NumberBlock from "./fields/NumberBlock.vue";
import ReferenceBlock from "./fields/ReferenceBlock.vue";
import RichTextBlock from "./fields/richText/RichTextBlock.vue";
import SelectBlock from "./fields/SelectBlock.vue";
import TableBlock from "./fields/table/TableBlock.vue";
import TextBlock from "./fields/TextBlock.vue";
import BlockDndRoot from "../dnd/BlockDndRoot.vue";

const blockComponents: Record<string, typeof TextBlock> = {
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

const {
  blocks = [],
  inheritedGroups = [],
  canEdit = false,
  workspaceSlug = "",
  projectSlug = "",
  formulaEditing = null,
  blockLocks = {},
  currentUserId = null,
} = defineProps<{
  blocks?: LayoutItem[];
  inheritedGroups?: InheritedBlockGroup[];
  canEdit?: boolean;
  workspaceSlug?: string;
  projectSlug?: string;
  formulaEditing?: FormulaEditing | null;
  blockLocks?: Record<string, BlockLock>;
  currentUserId?: number | null;
}>();

const live = useLive();

// ── Block locking ──
let lockHeartbeatInterval: ReturnType<typeof setInterval> | null = null;
const lockedBlockId = ref<number | string | null>(null);

function isLockedByOther(blockId: number | string): boolean {
  const lock = blockLocks[String(blockId)];
  return !!lock && lock.userId !== currentUserId;
}

function lockInfo(blockId: number | string): BlockLock | null {
  return blockLocks[String(blockId)] || null;
}

function acquireLock(blockId: number | string): void {
  if (!canEdit || isLockedByOther(blockId)) {
    return;
  }
  lockedBlockId.value = blockId;
  live.pushEvent("acquire_block_lock", { block_id: blockId });
  if (lockHeartbeatInterval) {
    clearInterval(lockHeartbeatInterval);
  }
  lockHeartbeatInterval = setInterval(() => {
    live.pushEvent("refresh_block_lock", { block_id: blockId });
  }, 10000);
}

function releaseLock(): void {
  if (lockedBlockId.value) {
    live.pushEvent("release_block_lock", { block_id: lockedBlockId.value });
    lockedBlockId.value = null;
  }
  if (lockHeartbeatInterval) {
    clearInterval(lockHeartbeatInterval);
    lockHeartbeatInterval = null;
  }
}

provide("blockLocks", () => blockLocks);
provide("currentUserId", () => currentUserId);
provide("isLockedByOther", isLockedByOther);
provide("lockInfo", lockInfo);

// ── Block selection ──
const selectedBlockId = ref<number | string | null>(null);

function selectBlock(id: number | string): void {
  if (isLockedByOther(id)) {
    return;
  }
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

function deselectBlock(): void {
  releaseLock();
  selectedBlockId.value = null;
}

provide("selectedBlockId", selectedBlockId);
provide("selectBlock", selectBlock);

function isInputFocused(): boolean {
  const el = document.activeElement;
  if (!el) {
    return false;
  }
  const tag = el.tagName;
  return (
    tag === "INPUT" ||
    tag === "TEXTAREA" ||
    tag === "SELECT" ||
    (el as HTMLElement).isContentEditable
  );
}

function onKeydown(e: KeyboardEvent): void {
  if (!selectedBlockId.value || !canEdit || isInputFocused()) {
    return;
  }

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

function onUndoRedo(e: KeyboardEvent): void {
  if (!(e.metaKey || e.ctrlKey) || isInputFocused()) {
    return;
  }

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

function addBlock({ type, scope }: { type: string; scope: string }): void {
  live.pushEvent("add_block", { type, scope });
}

function detachBlock(id: number | string): void {
  live.pushEvent("detach_block", { id });
}

function resolveComponent(type: string): typeof TextBlock | null {
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
          <span>{{ $t("sheets.block_list.inherited_from") }}</span>
          <a
            :href="`/workspaces/${workspaceSlug}/projects/${projectSlug}/sheets/${group.sourceSheet.id}`"
            data-phx-link="patch"
            data-phx-link-state="push"
            class="text-primary hover:underline font-medium normal-case"
          >
            {{ group.sourceSheet.name }}
          </a>
          <span class="text-muted-foreground/50">({{ group.blocks.length }})</span>
        </div>

        <div class="border-l-2 border-blue-400/30 ml-1 pl-3 space-y-3">
          <div
            v-for="block in group.blocks"
            :id="`sheet-block-${block.id}`"
            :key="block.id"
            :data-sheet-block-id="block.id"
            class="relative scroll-mt-8 transition-shadow"
          >
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
                    :title="$t('sheets.block_list.detach')"
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
        <span class="text-xs text-muted-foreground uppercase tracking-wider">{{
          $t("sheets.block_list.own_properties")
        }}</span>
        <div class="h-px flex-1 bg-border" />
      </div>

      <!-- ═══ OWN BLOCKS ═══ -->
      <BlockDndRoot :layout-items="blocks" :can-edit="canEdit" />

      <div
        v-if="blocks.length === 0 && inheritedGroups.length === 0 && !canEdit"
        class="py-8 text-center text-sm text-muted-foreground"
      >
        {{ $t("sheets.block_list.empty") }}
      </div>

      <AddBlockMenu v-if="canEdit" @select="addBlock" />
    </div>

    <FormulaPanel :formula-editing="formulaEditing" />
  </DnDProvider>
</template>
