<script setup lang="ts">
import { Separator } from "@components/ui/separator";
import type { UploadConfig } from "live_vue";
import ExportPanel from "./ExportPanel.vue";
import ImportPanel from "./ImportPanel.vue";

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

interface ImportPreview {
  counts?: Record<string, number>;
  has_conflicts?: boolean;
  conflicts?: Record<string, string[]>;
}

interface ImportResult {
  assets?: unknown[];
  sheets?: unknown[];
  flows?: unknown[];
  scenes?: unknown[];
  screenplays?: unknown[];
  localization?: unknown[];
}

interface ImportState {
  step: string;
  preview?: ImportPreview;
  result?: ImportResult;
  error?: string;
  conflictStrategy?: string;
}

const {
  exportConfig,
  canEdit,
  importState,
  uploadConfig = null,
} = defineProps<{
  exportConfig: ExportConfig;
  canEdit: boolean;
  importState: ImportState;
  uploadConfig?: UploadConfig | null;
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

    <Separator />

    <ImportPanel :can-edit="canEdit" :import-state="importState" :upload-config="uploadConfig" />
  </div>
</template>
