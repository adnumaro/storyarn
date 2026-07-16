<script setup lang="ts">
import ExportPanel from "@modules/projects/settings/export-import/components/ExportPanel.vue";
import ImportPanel from "@modules/projects/settings/export-import/components/ImportPanel.vue";
import type { ExportConfig } from "@modules/projects/settings/export-import/types";
import type { UploadConfig } from "live_vue";

interface ImportPreview {
  counts?: Record<string, number>;
  has_conflicts?: boolean;
  conflicts?: Record<string, string[]>;
}

interface ImportState {
  step: string;
  attemptId?: number | null;
  preview?: ImportPreview | null;
  error?: string | null;
  conflictStrategy?: string;
  warningCodes?: string[];
  status?: string | null;
}

const { exportConfig, canEdit, importState, uploadConfig } = defineProps<{
  exportConfig: ExportConfig;
  canEdit: boolean;
  importState: ImportState;
  uploadConfig?: UploadConfig | null;
}>();
</script>

<template>
  <div class="space-y-10">
    <ImportPanel :can-edit="canEdit" :import-state="importState" :upload-config="uploadConfig" />

    <div class="divider" />

    <ExportPanel
      :format-config="exportConfig.formatConfig"
      :section-config="exportConfig.sectionConfig"
      :options="exportConfig.options"
      :validation="exportConfig.validation"
      :export-download-url="exportConfig.downloadUrl"
    />
  </div>
</template>
