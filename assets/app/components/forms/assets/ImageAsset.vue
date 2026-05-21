<script setup lang="ts">
import { type Component, computed, ref } from "vue";
import { Image as ImageIcon, Loader2, Upload, X } from "lucide-vue-next";

import AssetPicker from "@components/forms/assets/AssetPicker.vue";
import { Button } from "@components/ui/button";
import { useUpload } from "../../../shared/composables/useUpload";

interface AssetItem {
  id: number | string;
  filename: string;
  url?: string | null;
}

const {
  label,
  icon = ImageIcon,
  assetId = null,
  imageAssets = [],
  canEdit = false,
  pickPlaceholder,
  searchPlaceholder,
  clearTitle,
  uploadTitle,
  previewPosition = "center",
  previewFit = "cover",
  // eslint-disable-next-line vue/max-props -- Public asset-field API keeps picker labels, uploads and preview controls explicit.
} = defineProps<{
  label?: string;
  icon?: Component;
  assetId?: number | string | null;
  imageAssets?: AssetItem[];
  canEdit?: boolean;
  pickPlaceholder?: string;
  searchPlaceholder?: string;
  clearTitle?: string;
  uploadTitle?: string;
  previewPosition?: string;
  previewFit?: "cover" | "contain" | "fill";
}>();

const emit = defineEmits<{
  select: [asset: AssetItem];
  clear: [];
}>();

const hasImage = computed(() => assetId != null);

const currentAsset = computed<AssetItem | null>(() => {
  if (!hasImage.value) return null;
  return imageAssets.find((a) => String(a.id) === String(assetId)) ?? null;
});

const previewStyle = computed(() => {
  if (!currentAsset.value?.url) return undefined;
  return {
    backgroundImage: `url(${currentAsset.value.url})`,
    backgroundPosition: previewPosition.replace("-", " "),
    backgroundSize: previewFit === "fill" ? "100% 100%" : previewFit,
    backgroundRepeat: "no-repeat",
  } as const;
});

// Upload — multipart via useUpload composable. After success the new asset
// is emitted via `select` so the parent's existing attach flow runs.
const { uploadFile } = useUpload();
const isUploading = ref(false);

function triggerUpload() {
  const input = document.createElement("input");
  input.type = "file";
  input.accept = "image/*";
  input.onchange = async (e) => {
    const file = (e.target as HTMLInputElement).files?.[0];
    if (!file) return;
    isUploading.value = true;
    try {
      const result = await uploadFile(file, "image");
      if (result) {
        emit("select", { id: result.id, url: result.url, filename: file.name });
      }
    } finally {
      isUploading.value = false;
    }
  };
  input.click();
}
</script>

<template>
  <div class="flex flex-col gap-1.5 border border-border rounded p-2">
    <div class="flex items-center gap-2">
      <component :is="icon" class="size-3.5 opacity-70 shrink-0" />
      <span class="text-xs font-medium flex-1">{{ label }}</span>
      <div class="flex items-center">
        <Button
          v-if="canEdit"
          variant="ghost"
          size="icon-xs"
          :title="uploadTitle || $t('common.assets.image.upload')"
          :disabled="isUploading"
          @click="triggerUpload"
        >
          <Loader2 v-if="isUploading" class="size-3 animate-spin" />
          <Upload v-else class="size-3" />
        </Button>
        <slot name="header-actions" />
        <Button
          v-if="hasImage && canEdit"
          variant="ghost"
          size="icon-xs"
          :title="clearTitle || $t('common.assets.image.clear')"
          @click="emit('clear')"
        >
          <X class="size-3" />
        </Button>
      </div>
    </div>

    <AssetPicker
      kind="image"
      :assets="imageAssets"
      :selected-id="assetId"
      :search-placeholder="searchPlaceholder || $t('common.assets.image.search')"
      @select="(asset) => emit('select', asset)"
    >
      <template #trigger>
        <Button
          variant="outline"
          class="justify-between text-xs h-auto py-1.5"
          :disabled="!canEdit"
        >
          <span class="truncate">
            {{ currentAsset?.filename || pickPlaceholder || $t("common.assets.image.pick") }}
          </span>
          <ImageIcon class="size-3.5 shrink-0 opacity-50" />
        </Button>
      </template>
    </AssetPicker>

    <div
      v-if="previewStyle"
      class="aspect-video rounded border border-border bg-muted/40 overflow-hidden"
      :style="previewStyle"
    />
  </div>
</template>
