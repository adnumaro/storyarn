<script setup>
import { Separator } from "@components/ui/separator/index.js";
import ExportPanel from "./ExportPanel.vue";
import ImportPanel from "./ImportPanel.vue";

defineProps({
  // Export props
  formats: { type: Array, required: true },
  selectedFormat: { type: String, required: true },
  selectedExtension: { type: String, required: true },
  supportedSections: { type: Array, required: true },
  sections: { type: Array, required: true },
  entityCounts: { type: Object, default: () => ({}) },
  assetMode: { type: String, required: true },
  validateBeforeExport: { type: Boolean, required: true },
  prettyPrint: { type: Boolean, required: true },
  validationResult: { type: Object, default: null },
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
      :formats="formats"
      :selected-format="selectedFormat"
      :selected-extension="selectedExtension"
      :supported-sections="supportedSections"
      :sections="sections"
      :entity-counts="entityCounts"
      :asset-mode="assetMode"
      :validate-before-export="validateBeforeExport"
      :pretty-print="prettyPrint"
      :validation-result="validationResult"
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
