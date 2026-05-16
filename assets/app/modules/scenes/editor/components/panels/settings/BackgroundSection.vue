<script setup lang="ts">
import { ref } from "vue";
import { ImagePlus, RefreshCw, Trash2 } from "lucide-vue-next";
import AssetUploadDecisionDialog from "@shared/components/assets/AssetUploadDecisionDialog.vue";
import { useAssetDecisionUpload } from "@shared/composables/useAssetDecisionUpload.ts";
import { useLive } from "@shared/composables/useLive.ts";

const { backgroundUrl = null, canEdit = false } = defineProps<{
  backgroundUrl?: string | null;
  canEdit?: boolean;
}>();

const live = useLive();
const inputRef = ref<HTMLInputElement | null>(null);
const {
  dialog: uploadDialog,
  uploading,
  progress,
  error: uploadError,
  uploadWithDecision,
  confirmDecision,
  cancelDecision,
} = useAssetDecisionUpload();

function triggerUpload() {
  inputRef.value?.click();
}

function removeBackground() {
  live.pushEvent("remove_background", {});
}

async function onFileSelected(event: Event): Promise<void> {
  const input = event.target as HTMLInputElement;
  const file = input.files?.[0];

  if (file) {
    const result = await uploadWithDecision(file, "scene_background");
    if (result) live.pushEvent("attach_background_asset", { asset_id: result.id });
  }

  input.value = "";
}
</script>

<template>
  <div>
    <input
      ref="inputRef"
      type="file"
      accept="image/jpeg,image/png,image/gif,image/webp"
      class="hidden"
      @change="onFileSelected"
    />
    <label class="text-xs font-medium text-foreground">
      {{ $t("scenes.settings.background") }}
    </label>
    <div v-if="backgroundUrl" class="space-y-2 mt-1.5">
      <div class="rounded border border-border overflow-hidden">
        <img :src="backgroundUrl" alt="Scene background" class="w-full h-32 object-cover" />
      </div>
      <div v-if="canEdit" class="flex gap-2">
        <button
          type="button"
          class="flex-1 inline-flex items-center justify-center gap-1.5 h-7 px-2 text-xs rounded-md bg-transparent hover:bg-accent text-foreground transition-colors"
          :disabled="uploading"
          @click="triggerUpload"
        >
          <RefreshCw class="size-3" />
          {{ $t("scenes.settings.bg_change") }}
        </button>
        <button
          type="button"
          class="flex-1 inline-flex items-center justify-center gap-1.5 h-7 px-2 text-xs rounded-md border border-destructive/30 text-destructive hover:bg-destructive/10 transition-colors"
          @click="removeBackground"
        >
          <Trash2 class="size-3" />
          {{ $t("scenes.settings.bg_remove") }}
        </button>
      </div>
    </div>
    <button
      v-else-if="canEdit"
      type="button"
      class="mt-1.5 w-full inline-flex items-center justify-center gap-1.5 h-8 px-3 text-xs rounded-md border border-dashed border-border hover:bg-accent text-muted-foreground transition-colors"
      :disabled="uploading"
      @click="triggerUpload"
    >
      <ImagePlus class="size-4" />
      {{ $t("scenes.settings.bg_upload") }}
    </button>

    <AssetUploadDecisionDialog
      :state="uploadDialog"
      :uploading="uploading"
      :progress="progress"
      :error="uploadError"
      @confirm="confirmDecision"
      @cancel="cancelDecision"
    />
  </div>
</template>
