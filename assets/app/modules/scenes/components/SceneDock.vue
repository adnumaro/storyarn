<script setup lang="ts">
import { Cable, Hand, MousePointer2, Ruler, StickyNote } from "lucide-vue-next";
import { useLive } from "@composables/useLive";
import DockToolButton from "./dock-panels/DockToolButton.vue";
import ZonesDropdown from "./dock-panels/ZonesDropdown.vue";
import PinsDropdown from "./dock-panels/PinsDropdown.vue";
import DockActions from "./dock-panels/DockActions.vue";
import PendingSheetIndicator from "./dock-panels/PendingSheetIndicator.vue";

interface PendingSheetData {
  id: number | string;
  name: string;
}

interface ProjectSheet {
  id: number | string;
  name: string;
  shortcut?: string;
}

const {
  activeTool = "select",
  editMode = true,
  compact = false,
  pendingSheet = null,
  projectSheets = [],
  workspaceSlug,
  projectSlug,
  sceneId,
} = defineProps<{
  activeTool: string;
  editMode: boolean;
  compact: boolean;
  pendingSheet: PendingSheetData | null;
  projectSheets: ProjectSheet[];
  workspaceSlug: string;
  projectSlug: string;
  sceneId: string | number;
}>();

const live = useLive();

function setTool(type: string): void {
  live.pushEvent("set_tool", { type });
}

function selectSheet(sheetId: number | string): void {
  live.pushEvent("start_pin_from_sheet", { "sheet-id": sheetId });
}

function cancelPendingSheet(): void {
  live.pushEvent("cancel_sheet_picker", {});
}

function openVersions(): void {
  live.pushEvent("open_versions_panel", {});
}

const playUrl = `/workspaces/${workspaceSlug}/projects/${projectSlug}/scenes/${sceneId}/explore`;
</script>

<template>
  <div v-if="editMode">
    <div
      class="absolute bottom-3 left-1/2 -translate-x-1/2 z-30 flex items-center gap-1 v2-surface-panel px-2 py-2"
    >
      <!-- Navigation group -->
      <DockToolButton
        :icon="MousePointer2"
        :active="activeTool === 'select'"
        tooltip-title="Select"
        tooltip-description="Select elements on the canvas"
        @click="setTool('select')"
      />

      <DockToolButton
        :icon="Hand"
        :active="activeTool === 'pan'"
        tooltip-title="Pan"
        tooltip-description="Pan and scroll around the map"
        @click="setTool('pan')"
      />

      <!-- Separator -->
      <div class="w-px h-6 bg-border mx-0.5 shrink-0" />

      <!-- Creation group -->
      <ZonesDropdown :active-tool="activeTool" @set-tool="setTool" />

      <PinsDropdown
        :active-tool="activeTool"
        :project-sheets="projectSheets"
        @set-tool="setTool"
        @select-sheet="selectSheet"
      />

      <!-- Annotation -->
      <DockToolButton
        :icon="StickyNote"
        :active="activeTool === 'annotation'"
        tooltip-title="Annotation"
        tooltip-description="Add text notes directly on the canvas"
        @click="setTool('annotation')"
      />

      <!-- Separator -->
      <div class="w-px h-6 bg-border mx-0.5 shrink-0" />

      <!-- Connector -->
      <DockToolButton
        :icon="Cable"
        :active="activeTool === 'connector'"
        tooltip-title="Connector"
        tooltip-description="Draw connections between two pins. Click the source pin, then the target."
        @click="setTool('connector')"
      />

      <!-- Separator -->
      <div class="w-px h-6 bg-border mx-0.5 shrink-0" />

      <!-- Ruler -->
      <DockToolButton
        :icon="Ruler"
        :active="activeTool === 'ruler'"
        tooltip-title="Ruler"
        tooltip-description="Measure distances between two points on the map"
        @click="setTool('ruler')"
      />

      <!-- Actions group (not in compact mode) -->
      <DockActions v-if="!compact" :play-url="playUrl" @open-versions="openVersions" />
    </div>

    <!-- Pending sheet indicator -->
    <PendingSheetIndicator
      v-if="pendingSheet"
      :pending-sheet="pendingSheet"
      @cancel="cancelPendingSheet"
    />
  </div>
</template>
