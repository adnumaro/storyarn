<script setup lang="ts">
import ExportPanel from "@modules/projects/settings/export-import/components/ExportPanel.vue";
import ImportPanel from "@modules/projects/settings/export-import/components/ImportPanel.vue";
import type { ExportConfig, ImportState } from "@modules/projects/settings/export-import/types";
import type { UploadConfig } from "live_vue";

const { exportConfig, projectId, canImport, currentUserId, importState, uploadConfig } =
  defineProps<{
    exportConfig: ExportConfig;
    projectId: number;
    /** `:edit_content` — export is available to editors. */
    canEdit: boolean;
    /** `:manage_project` — import rewrites project content, so it is owner-only. */
    canImport: boolean;
    currentUserId: number;
    importState: ImportState;
    uploadConfig?: UploadConfig | null;
  }>();
</script>

<template>
  <div class="space-y-10">
    <ImportPanel
      :project-id="projectId"
      :can-edit="canEdit"
      :can-import="canImport"
      :current-user-id="currentUserId"
      :import-state="importState"
      :upload-config="uploadConfig"
    />

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
