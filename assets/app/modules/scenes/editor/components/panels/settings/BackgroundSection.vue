<script setup lang="ts">
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import { ImagePlus, RefreshCw, Trash2, X } from "lucide-vue-next";
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
  clearError: clearUploadError,
  uploadWithDecision,
  confirmDecision,
  cancelDecision,
} = useAssetDecisionUpload();
const { t } = useI18n();

const uploadErrorMessage = computed(() => formatUploadError(uploadError.value));

function formatUploadError(value: string | null): string | null {
  switch (value) {
    case null:
      return null;
    case "too_large":
      return t("common.assets.api_file_too_large");
    case "not_accepted":
      return t("common.assets.file_not_accepted");
    case "storage_limit_reached":
      return t("common.assets.storage_limit_reached");
    case "upload_failed":
      return t("common.assets.upload_failed");
    default:
      return t("common.assets.upload_failed");
  }
}

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

    <div
      v-if="uploadErrorMessage"
      role="alert"
      class="mt-2 flex items-start gap-2 text-xs text-destructive"
    >
      <span>{{ uploadErrorMessage }}</span>
      <button
        type="button"
        class="rounded p-0.5 text-destructive/70 transition-colors hover:bg-destructive/10 hover:text-destructive"
        :aria-label="$t('common.dismiss')"
        @click="clearUploadError"
      >
        <X class="size-3" />
      </button>
    </div>

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
