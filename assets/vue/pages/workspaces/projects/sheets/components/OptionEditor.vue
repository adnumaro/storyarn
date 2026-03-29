<script setup>
/**
 * Shared option editor for select/multi_select blocks.
 * Renders editable key+label rows with add/remove.
 */
import { Plus, X } from "lucide-vue-next";
import { useLive } from "@/vue/composables/useLive.js";

const props = defineProps({
	blockId: { type: [Number, String], required: true },
	options: { type: Array, default: () => [] },
});

const live = useLive();

function addOption() {
	live.pushEvent("add_select_option", { "block-id": props.blockId });
}

function removeOption(index) {
	live.pushEvent("remove_select_option", {
		"block-id": props.blockId,
		index,
	});
}

function updateOption(index, field, value) {
	live.pushEvent("update_select_option", {
		"block-id": props.blockId,
		index,
		field,
		value,
	});
}
</script>

<template>
	<div>
		<label class="text-xs font-medium mb-1 block">Options</label>
		<div class="space-y-1">
			<div v-for="(opt, idx) in options" :key="opt.key" class="flex items-center gap-1">
				<input
					:value="opt.key"
					class="h-7 w-14 text-xs font-mono rounded-md border border-input bg-background px-1.5 shrink-0"
					placeholder="key"
					@blur="(e) => updateOption(idx, 'key', e.target.value)"
				/>
				<input
					:value="opt.value"
					class="h-7 flex-1 min-w-0 text-xs rounded-md border border-input bg-background px-1.5"
					placeholder="Label"
					@blur="(e) => updateOption(idx, 'value', e.target.value)"
				/>
				<button
					type="button"
					class="size-6 rounded flex items-center justify-center text-destructive hover:bg-destructive/10 shrink-0"
					@click="removeOption(idx)"
				>
					<X class="size-3" />
				</button>
			</div>
		</div>
		<button
			type="button"
			class="flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground mt-1 px-1 py-0.5"
			@click="addOption"
		>
			<Plus class="size-3" />
			Add option
		</button>
	</div>
</template>
