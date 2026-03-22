<script setup>
import { computed } from "vue";
import { Image, Lock } from "lucide-vue-next";
import BlockToolbar from "../BlockToolbar.vue";
import GalleryBlockContent from "../GalleryBlock.vue";
import { useBlockActions } from "./useBlockActions";

const props = defineProps({
	block: { type: Object, required: true },
	canEdit: { type: Boolean, default: false },
	inherited: { type: Boolean, default: false },
});

const {
	live,
	label,
	editingLabel,
	localLabel,
	labelInput,
	startEditLabel,
	saveLabel,
	isSelected,
	onBlockClick,
} = useBlockActions(props);
</script>

<template>
  <div
    class="group relative rounded-lg border p-4 pt-5 transition-colors"
    :class="isSelected ? 'border-primary ring-1 ring-primary/30' : 'border-border hover:border-foreground/20'"
    @click="onBlockClick"
  >
    <BlockToolbar v-if="canEdit"
      :show-constant="false" :show-config="false"
      :show-scope="!inherited"
      :scope="block.scope || 'self'" :required="block.required"
      @change-scope="(s) => live.pushEvent('change_block_scope', { id: block.id, scope: s })"
      @toggle-required="live.pushEvent('toggle_required', { id: block.id })"
    />

    <div class="flex items-center justify-between mb-2">
      <div class="flex items-center gap-1.5 text-sm">
        <Image class="size-3.5 text-muted-foreground" />
        <input v-if="canEdit && editingLabel" ref="labelInput" v-model="localLabel" class="font-medium bg-transparent outline-none border-none px-0 text-sm" @blur="saveLabel" @keydown.enter.prevent="saveLabel" />
        <span v-else class="font-medium" :class="canEdit && 'cursor-text'" @click="startEditLabel">{{ label }}</span>
        <span v-if="block.required" class="text-[10px] text-destructive font-medium">required</span>
      </div>
      <slot name="menu" />
    </div>

    <GalleryBlockContent
      :block-id="block.id"
      :images="block.gallery_images || []"
      :can-edit="canEdit"
    />
  </div>
</template>
