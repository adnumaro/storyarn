<script setup lang="ts">
import { Image } from "lucide-vue-next";
import { useBlockActions } from "../../../composables/useBlockActions";
import type { Block } from "../../../types";
import BlockLabel from "../../BlockLabel.vue";
import BlockToolbar from "../../BlockToolbar.vue";
import GalleryBlockContent from "./GalleryBlockContent.vue";

const {
  block,
  canEdit = false,
  inherited = false,
} = defineProps<{
  block: Block;
  canEdit?: boolean;
  inherited?: boolean;
}>();

const { live, label, isSelected, onBlockClick } = useBlockActions({
  get block() {
    return block;
  },
  get canEdit() {
    return canEdit;
  },
});

function saveLabel(val: string): void {
  live.pushEvent("update_block_config", {
    id: block.id,
    field: "label",
    value: val,
  });
}
</script>

<template>
  <div
    class="group relative rounded-lg border p-4 pt-5 transition-colors"
    :class="
      isSelected
        ? 'border-primary ring-1 ring-primary/30'
        : 'border-border hover:border-foreground/20'
    "
    @click="onBlockClick"
  >
    <BlockToolbar
      v-if="canEdit"
      :block-id="block.id"
      :show-constant="false"
      :show-config="false"
      :show-scope="!inherited"
      :scope="block.scope || 'self'"
      :required="block.required"
      @change-scope="(s) => live.pushEvent('change_block_scope', { id: block.id, scope: s })"
      @toggle-required="live.pushEvent('toggle_required', { id: block.id })"
    />

    <BlockLabel
      :icon="Image"
      :label="label"
      :can-edit="canEdit"
      :required="block.required"
      @save="saveLabel"
    >
      <slot name="menu" />
    </BlockLabel>

    <GalleryBlockContent
      :block-id="block.id"
      :images="block.gallery_images || []"
      :can-edit="canEdit"
    />
  </div>
</template>
