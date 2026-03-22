<script setup>
/**
 * Shared block label: icon + editable name + lock/required/detached badges.
 * Used by all block types except TableBlock (which has its own accordion header).
 *
 * Default slot: rendered after the label row (e.g. menu button).
 */
import { ref, nextTick, watch } from "vue";
import { Lock } from "lucide-vue-next";

const props = defineProps({
	icon: { type: [Object, Function], required: true },
	label: { type: String, default: "" },
	canEdit: { type: Boolean, default: false },
	isConstant: { type: Boolean, default: false },
	required: { type: Boolean, default: false },
	detached: { type: Boolean, default: false },
});

const emit = defineEmits(["save"]);

const editing = ref(false);
const localLabel = ref(props.label);
const inputRef = ref(null);

watch(
	() => props.label,
	(v) => {
		localLabel.value = v;
	},
);

function startEdit() {
	if (!props.canEdit) return;
	editing.value = true;
	nextTick(() => inputRef.value?.focus());
}

function save() {
	editing.value = false;
	const val = localLabel.value?.trim();
	if (val && val !== props.label) {
		emit("save", val);
	}
}
</script>

<template>
	<div class="flex items-center justify-between mb-2">
		<div class="flex items-center gap-1.5 text-sm">
			<component :is="icon" class="size-3.5 text-muted-foreground" />
			<input
				v-if="canEdit && editing"
				ref="inputRef"
				v-model="localLabel"
				class="font-medium bg-transparent outline-none border-none px-0 text-sm"
				@blur="save"
				@keydown.enter.prevent="save"
			/>
			<span
				v-else
				class="font-medium"
				:class="canEdit && 'cursor-text'"
				@click="startEdit"
			>{{ localLabel }}</span>
			<Lock v-if="isConstant" class="size-3 text-muted-foreground/50" />
			<span v-if="required" class="text-[10px] text-destructive font-medium">required</span>
			<span v-if="detached" class="text-[10px] text-amber-500 font-medium">detached</span>
		</div>
		<slot />
	</div>
</template>
