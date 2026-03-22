import { ref, computed, watch, inject } from "vue";
import { useLive } from "@/vue/composables/useLive";

/**
 * Shared composable for block label editing and common actions.
 * Used by all block type components.
 */
export function useBlockActions(props) {
	const live = useLive();

	// ── Selection ──
	const selectedBlockId = inject("selectedBlockId", ref(null));
	const selectBlockFn = inject("selectBlock", () => {});
	const isSelected = computed(() => selectedBlockId.value === props.block.id);

	function onBlockClick() {
		selectBlockFn(props.block.id);
	}

	// ── Label ──
	const label = computed(() => props.block.config?.label || "Untitled");
	const editingLabel = ref(false);
	const localLabel = ref(label.value);
	const labelInput = ref(null);

	watch(label, (v) => {
		localLabel.value = v;
	});

	function startEditLabel() {
		if (!props.canEdit) return;
		editingLabel.value = true;
		setTimeout(() => labelInput.value?.focus(), 0);
	}

	function saveLabel() {
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

	function deleteBlock() {
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
