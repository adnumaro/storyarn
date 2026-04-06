<script setup>
import { Separator } from "@components/ui/separator/index.ts";
import ExportPanel from "./ExportPanel.vue";
import ImportPanel from "./ImportPanel.vue";

const { exportConfig, canEdit, importState, uploadConfig } = defineProps({
  exportConfig: { type: Object, required: true },
  canEdit: { type: Boolean, required: true },
  importState: { type: Object, required: true },
  uploadConfig: { type: Object, default: null },
});
</script>

<template>
  <div class="space-y-8">
    <ExportPanel
      :format-config="exportConfig.formatConfig"
      :section-config="exportConfig.sectionConfig"
      :options="exportConfig.options"
      :validation="exportConfig.validation"
      :export-download-url="exportConfig.downloadUrl"
    />

    <Separator />

    <ImportPanel :can-edit="canEdit" :import-state="importState" :upload-config="uploadConfig" />
  </div>
</template>
