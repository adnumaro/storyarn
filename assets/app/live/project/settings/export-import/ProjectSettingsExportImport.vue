<script setup lang="ts">
import ExportPanel from "@modules/projects/settings/export-import/components/ExportPanel.vue";

interface FormatOption {
  format: string;
  label: string;
}

interface FormatConfig {
  selected: string;
  formats: FormatOption[];
  extension: string;
}

interface SectionConfig {
  selected: string[];
  supported: string[];
  entityCounts: Record<string, number>;
}

interface ExportOptions {
  assetMode: string;
  validateBeforeExport: boolean;
  prettyPrint: boolean;
}

interface ValidationFinding {
  message: string;
}

interface ValidationResult {
  status: string;
  errors?: ValidationFinding[];
  warnings?: ValidationFinding[];
  info?: ValidationFinding[];
}

interface ExportConfig {
  formatConfig: FormatConfig;
  sectionConfig: SectionConfig;
  options: ExportOptions;
  validation: ValidationResult | null;
  downloadUrl: string;
}

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
