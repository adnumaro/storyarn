import { onUnmounted, ref } from "vue";
import { useI18n } from "vue-i18n";
import { useAssetDecisionUpload } from "@shared/composables/useAssetDecisionUpload";
import type { SequenceAssetEntry } from "@modules/flows/sequence/types";

// Matches the existing project upload policy; other image formats are rejected there.
export const SEQUENCE_IMAGE_ACCEPT = "image/jpeg,image/png,image/gif,image/webp";
const IMAGE_TYPES = new Set(SEQUENCE_IMAGE_ACCEPT.split(","));

export function useSequenceImageImport(canUpload: () => boolean) {
  const {
    uploadWithDecision,
    dialog,
    uploading,
    progress,
    error,
    confirmDecision,
    cancelDecision,
  } = useAssetDecisionUpload();
  const { t } = useI18n();
  const importing = ref(false);
  const fileName = ref("");
  const errors = ref<string[]>([]);
  let active = true;

  onUnmounted(() => {
    active = false;
  });

  async function importImage(
    file: File,
    onUploaded: (asset: SequenceAssetEntry) => Promise<void> | void,
  ) {
    fileName.value = file.name;
    if (!IMAGE_TYPES.has(file.type)) {
      errors.value.push(t("flows.sequence_library.unsupported_image", { name: file.name }));
      return;
    }
    try {
      const asset = await uploadWithDecision(file, "scene_background");
      if (active && asset) await onUploaded({ ...asset, filename: file.name });
      else if (active && error.value) errors.value.push(`${file.name}: ${error.value}`);
    } catch (reason) {
      if (!active) return;
      const message = reason instanceof Error ? reason.message : t("common.assets.upload_failed");
      errors.value.push(`${file.name}: ${message}`);
    }
  }

  async function importImages(
    files: File[],
    onUploaded: (asset: SequenceAssetEntry) => Promise<void> | void,
  ) {
    if (!active || !canUpload() || importing.value || files.length === 0) return;
    importing.value = true;
    errors.value = [];
    try {
      for (const file of files) {
        if (!active || !canUpload()) break;
        await importImage(file, onUploaded);
      }
    } finally {
      importing.value = false;
      fileName.value = "";
    }
  }

  return {
    importing,
    fileName,
    errors,
    importImages,
    dialog,
    uploading,
    progress,
    error,
    confirmDecision,
    cancelDecision,
  };
}
