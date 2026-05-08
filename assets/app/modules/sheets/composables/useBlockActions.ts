import { computed, inject, ref, watch } from "vue";
import type { ComputedRef, Ref } from "vue";
import { useLive } from "../../../shared/composables/useLive";
import type { Block } from "../types";

interface BlockActionProps {
  block: Block;
  canEdit: boolean;
}

interface BlockActionsReturn {
  live: ReturnType<typeof useLive>;
  label: ComputedRef<string>;
  editingLabel: Ref<boolean>;
  localLabel: Ref<string>;
  labelInput: Ref<HTMLInputElement | null>;
  startEditLabel: () => void;
  saveLabel: () => void;
  deleteBlock: () => void;
  isSelected: ComputedRef<boolean>;
  onBlockClick: () => void;
}

/**
 * Shared composable for block label editing and common actions.
 * Used by all block type components.
 */
export function useBlockActions(props: BlockActionProps): BlockActionsReturn {
  const live = useLive();

  // ── Selection ──
  const selectedBlockId = inject<Ref<number | string | null>>("selectedBlockId", ref(null));
  const selectBlockFn = inject<(id: number | string) => void>("selectBlock", () => {});
  const isSelected = computed(() => selectedBlockId.value === props.block.id);

  function onBlockClick(): void {
    selectBlockFn(props.block.id);
  }

  // ── Label ──
  const label = computed(() => props.block.config?.label || "Untitled");
  const editingLabel = ref(false);
  const localLabel = ref(label.value);
  const labelInput = ref<HTMLInputElement | null>(null);

  watch(label, (v: string) => {
    localLabel.value = v;
  });

  function startEditLabel(): void {
    if (!props.canEdit) {
      return;
    }
    editingLabel.value = true;
    setTimeout(() => labelInput.value?.focus(), 0);
  }

  function saveLabel(): void {
    editingLabel.value = false;
    const val = localLabel.value?.trim();
    if (val && val !== label.value) {
      live.pushEvent("update_block_config", {
        id: props.block.id,
        field: "label",
        value: val,
      });
    }
  }

  function deleteBlock(): void {
    live.pushEvent("delete_block", { id: props.block.id });
  }

  return {
    live,
    label,
    editingLabel,
    localLabel,
    labelInput,
    startEditLabel,
    saveLabel,
    deleteBlock,
    isSelected,
    onBlockClick,
  };
}
