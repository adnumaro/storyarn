<script setup>
import { Separator } from "@components/ui/separator/index.js";
import ExportPanel from "./ExportPanel.vue";
import ImportPanel from "./ImportPanel.vue";

const {
  formatConfig, sectionConfig, options, validation, exportDownloadUrl,
  canEdit, importStep, importPreview, importResult, importError, conflictStrategy, uploadConfig,
} = defineProps({
  // Export props (grouped)
  formatConfig: { type: Object, required: true },
  sectionConfig: { type: Object, required: true },
  options: { type: Object, required: true },
  validation: { type: Object, default: null },
  exportDownloadUrl: { type: String, required: true },

  // Import props
  canEdit: { type: Boolean, required: true },
  importStep: { type: String, required: true },
  importPreview: { type: Object, default: null },
  importResult: { type: Object, default: null },
  importError: { type: String, default: null },
  conflictStrategy: { type: String, required: true },
  uploadConfig: { type: Object, default: null },
});
</script>

<template>
  <div class="space-y-8">
    <ExportPanel
      :format-config="formatConfig"
      :section-config="sectionConfig"
      :options="options"
      :validation="validation"
      :export-download-url="exportDownloadUrl"
    />

    <Separator />

    <ImportPanel
      :can-edit="canEdit"
      :import-step="importStep"
      :import-preview="importPreview"
      :import-result="importResult"
      :import-error="importError"
      :conflict-strategy="conflictStrategy"
      :upload-config="uploadConfig"
    />
  </div>
</template>
