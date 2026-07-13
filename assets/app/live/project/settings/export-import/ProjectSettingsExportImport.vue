<script setup lang="ts">
import ExportPanel from "@modules/projects/settings/export-import/components/ExportPanel.vue";
import type { ExportConfig } from "@modules/projects/settings/export-import/types";

const { exportConfig } = defineProps<{
  exportConfig: ExportConfig;
}>();
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
  </div>
</template>
