<script setup lang="ts">
import {
  AlertTriangle,
  ArrowLeft,
  ArrowRight,
  Check,
  ChevronDown,
  CircleCheck,
  Info,
  Map as MapIcon,
  ScanSearch,
  Text,
  TriangleAlert,
  X,
} from "lucide-vue-next";
import { computed, onUnmounted, ref } from "vue";
import EditableText from "@components/forms/EditableText.vue";
import ToolbarTooltip from "@components/toolbar/ToolbarTooltip.vue";
import { Badge } from "@components/ui/badge";
import { Popover, PopoverAnchor, PopoverContent, PopoverTrigger } from "@components/ui/popover";
import { registerPaletteCommands } from "@shared/command-palette/registry";
import { useLive } from "@shared/composables/useLive";

interface NavEntry {
  flow_name: string;
}

interface NavHistory {
  back: NavEntry | null;
  forward: NavEntry | null;
}

interface HealthNode {
  id: number | string | null;
  label: string;
  reason?: string;
  reasons?: string[];
}

interface StructuralSummary {
  errorCount: number;
  warningCount: number;
}

interface FlowHealth {
  wordCount: number;
  errorNodes: HealthNode[];
  warningNodes: HealthNode[];
  infoNodes: HealthNode[];
  structural: StructuralSummary;
}

interface SceneSelected {
  name: string | null;
  inherited: boolean;
}

interface ProjectScene {
  id: number | string;
  name: string;
}

const {
  flowName = "",
  flowShortcut = "",
  isMain = false,
  canEdit = false,
  saveStatus = "idle",
  navHistory = { back: null, forward: null },
  flowHealth = {
    wordCount: 0,
    errorNodes: [],
    warningNodes: [],
    infoNodes: [],
    structural: { errorCount: 0, warningCount: 0 },
  },
  sceneSelected = { name: null, inherited: false },
  projectScenes = [],
} = defineProps<{
  flowName: string;
  flowShortcut: string;
  isMain: boolean;
  canEdit: boolean;
  saveStatus: string;
  navHistory: NavHistory;
  flowHealth: FlowHealth;
  sceneSelected: SceneSelected;
  projectScenes: ProjectScene[];
}>();

const live = useLive();
const sceneOpen = ref(false);
const healthOpen = ref(false);

// Ordinary non-AI palette command: registration lifetime scopes it to the
// normal flow editor (the only v1 analysis surface). The server reauthorizes
// the read when the panel opens.
const unregisterPaletteCommands = registerPaletteCommands("flows", [
  {
    id: "flows.analyze",
    labelKey: "flows.analysis.command",
    groupKey: "palette.groups.actions",
    icon: ScanSearch,
    run: () => live.pushEvent("open_analysis_panel", {}),
  },
]);
onUnmounted(unregisterPaletteCommands);

const errorCount = computed(
  () => findingCount(flowHealth.errorNodes) + flowHealth.structural.errorCount,
);
const warningCount = computed(
  () => findingCount(flowHealth.warningNodes) + flowHealth.structural.warningCount,
);
const infoCount = computed(() => findingCount(flowHealth.infoNodes));
const structuralCount = computed(
  () => flowHealth.structural.errorCount + flowHealth.structural.warningCount,
);
const showScene = computed(() => canEdit || sceneSelected.name != null);

function nodeReasons(node: HealthNode): string[] {
  if (node.reasons?.length) return node.reasons;
  return node.reason ? [node.reason] : [];
}

function findingCount(nodes: HealthNode[]): number {
  return nodes.reduce((count, node) => count + nodeReasons(node).length, 0);
}

function saveName(name: string): void {
  live.pushEvent("save_name", { name });
}

function saveShortcut(shortcut: string): void {
  live.pushEvent("save_shortcut", { shortcut });
}

function selectScene(sceneId: number | string | null): void {
  live.pushEvent("update_scene", { scene_id: sceneId || "" });
  sceneOpen.value = false;
}

function navigateToNode(nodeId: number | string | null): void {
  if (nodeId == null) return;
  live.pushEvent("navigate_to_node", { id: nodeId });
  healthOpen.value = false;
}

function openAnalysisPanel(): void {
  live.pushEvent("open_analysis_panel", {});
  healthOpen.value = false;
}
</script>

<template>
  <div class="flex items-stretch gap-2 h-8">
    <!-- Nav history -->
    <div v-if="navHistory.back || navHistory.forward" class="flex items-center gap-0.5 px-1">
      <ToolbarTooltip v-if="navHistory.back" :label="$t('flows.header.nav_back')" side="bottom">
        <button
          type="button"
          class="toolbar-btn gap-1 text-muted-foreground max-w-35"
          @click="live.pushEvent('nav_back', {})"
        >
          <ArrowLeft class="size-3.5 shrink-0" />
          <span class="truncate text-xs">{{ navHistory.back.flow_name }}</span>
        </button>
      </ToolbarTooltip>
      <ToolbarTooltip
        v-if="navHistory.forward"
        :label="$t('flows.header.nav_forward')"
        side="bottom"
      >
        <button
          type="button"
          class="toolbar-btn gap-1 text-muted-foreground max-w-35"
          @click="live.pushEvent('nav_forward', {})"
        >
          <span class="truncate text-xs">{{ navHistory.forward.flow_name }}</span>
          <ArrowRight class="size-3.5 shrink-0" />
        </button>
      </ToolbarTooltip>
    </div>

    <!-- Flow title pill -->
    <div class="flex items-center gap-1.5 px-3 h-full">
      <EditableText
        :model-value="flowName"
        :placeholder="$t('flows.header.untitled')"
        tag="span"
        class="text-xs font-medium max-w-50 truncate"
        :disabled="!canEdit"
        @save="saveName"
      />
      <EditableText
        v-if="flowShortcut || canEdit"
        :model-value="flowShortcut"
        :placeholder="$t('flows.header.add_shortcut')"
        tag="span"
        class="text-[0.70rem] text-muted-foreground max-w-30 truncate"
        :disabled="!canEdit"
        @save="saveShortcut"
      />
      <Badge
        v-if="isMain"
        variant="default"
        class="text-[0.70rem] px-1.5 py-0 rounded-full shrink-0"
      >
        {{ $t("flows.header.main") }}
      </Badge>
    </div>

    <!-- Stats + Scene panel -->
    <div class="hidden lg:flex items-center gap-1 px-1 py-1 text-xs">
      <!-- Scene selector -->
      <template v-if="showScene">
        <Popover v-model:open="sceneOpen">
          <PopoverAnchor as-child>
            <ToolbarTooltip :label="$t('flows.header.scene_backdrop')" side="bottom">
              <PopoverTrigger
                class="toolbar-btn gap-1.5"
                :class="sceneSelected.name ? 'text-foreground' : 'text-muted-foreground'"
              >
                <MapIcon class="size-3.5" />
                <span v-if="sceneSelected.name" class="truncate max-w-30">{{
                  sceneSelected.name
                }}</span>
                <span v-else>{{ $t("flows.header.no_scene") }}</span>
                <span v-if="sceneSelected.inherited" class="text-muted-foreground text-[10px]">{{
                  $t("flows.header.inherited")
                }}</span>
                <ChevronDown v-if="canEdit" class="size-3 opacity-50" />
              </PopoverTrigger>
            </ToolbarTooltip>
          </PopoverAnchor>
          <PopoverContent v-if="canEdit" side="bottom" :side-offset="4" class="w-56 p-1">
            <button
              type="button"
              class="w-full flex items-center gap-2 px-2 py-1.5 rounded-md text-xs hover:bg-accent transition-colors"
              :class="{ 'bg-accent': !sceneSelected.name }"
              @click="selectScene(null)"
            >
              <X class="size-3 opacity-60" />
              <span class="text-muted-foreground">{{ $t("flows.header.no_scene_inherit") }}</span>
            </button>
            <button
              v-for="scene in projectScenes"
              :key="scene.id"
              type="button"
              class="w-full flex items-center gap-2 px-2 py-1.5 rounded-md text-xs hover:bg-accent transition-colors"
              @click="selectScene(scene.id)"
            >
              <MapIcon class="size-3 opacity-60" />
              <span class="truncate">{{ scene.name }}</span>
            </button>
          </PopoverContent>
        </Popover>
        <div class="w-px h-5 bg-border" />
      </template>

      <!-- Word count -->
      <ToolbarTooltip
        :label="
          $t('flows.header.word_count', { count: flowHealth.wordCount }, flowHealth.wordCount)
        "
        side="bottom"
      >
        <div class="toolbar-btn gap-1.5 text-muted-foreground">
          <Text class="size-3.5" />
          <span>{{ flowHealth.wordCount }}</span>
        </div>
      </ToolbarTooltip>

      <!-- Flow health indicator -->
      <template v-if="errorCount > 0 || warningCount > 0 || infoCount > 0">
        <Popover v-model:open="healthOpen">
          <PopoverAnchor as-child>
            <ToolbarTooltip :label="$t('flows.header.flow_health')" side="bottom">
              <PopoverTrigger data-testid="flow-health-trigger" class="toolbar-btn gap-0">
                <span v-if="errorCount > 0" class="flex items-center gap-1.5 text-destructive">
                  <TriangleAlert class="size-3.5" />
                  <span data-testid="flow-health-error-count">{{ errorCount }}</span>
                </span>
                <span
                  v-if="warningCount > 0"
                  class="flex items-center gap-1.5 text-yellow-500"
                  :class="{ 'ml-2': errorCount > 0 }"
                >
                  <AlertTriangle class="size-3.5" />
                  <span data-testid="flow-health-warning-count">{{ warningCount }}</span>
                </span>
                <span
                  v-if="infoCount > 0"
                  class="flex items-center gap-1.5 text-blue-500"
                  :class="{ 'ml-2': errorCount > 0 || warningCount > 0 }"
                >
                  <Info class="size-3.5" />
                  <span data-testid="flow-health-info-count">{{ infoCount }}</span>
                </span>
                <ChevronDown class="size-3 opacity-50 ml-1" />
              </PopoverTrigger>
            </ToolbarTooltip>
          </PopoverAnchor>
          <PopoverContent side="bottom" :side-offset="4" class="w-max max-h-60 overflow-y-auto p-1">
            <button
              type="button"
              data-testid="flow-health-open-analysis"
              class="w-full flex items-center gap-1.5 px-2 py-1.5 rounded-md text-xs transition-colors hover:bg-accent"
              @click="openAnalysisPanel"
            >
              <ScanSearch class="size-3.5 shrink-0" />
              <span class="flex-1 text-left">
                {{
                  structuralCount > 0
                    ? $t("flows.analysis.open_from_health", { count: structuralCount })
                    : $t("flows.analysis.open_from_health_clean")
                }}
              </span>
            </button>
            <div v-if="flowHealth.errorNodes.length > 0">
              <div
                data-testid="flow-health-errors"
                class="px-2 py-1 text-[10px] text-muted-foreground font-medium uppercase"
              >
                {{ $t("flows.header.errors") }}
              </div>
              <button
                v-for="(node, index) in flowHealth.errorNodes"
                :key="'e-' + (node.id ?? `flow-${index}`)"
                type="button"
                :data-health-node-id="node.id"
                data-health-severity="error"
                :disabled="node.id == null"
                class="w-full flex flex-col items-start gap-0.5 px-2 py-1.5 rounded-md text-xs transition-colors enabled:hover:bg-accent disabled:cursor-default"
                @click="navigateToNode(node.id)"
              >
                <span class="truncate">{{ node.label }}</span>
                <span
                  v-for="reason in nodeReasons(node)"
                  :key="reason"
                  class="text-[11px] text-muted-foreground"
                >
                  {{ reason }}
                </span>
              </button>
            </div>
            <div v-if="flowHealth.warningNodes.length > 0">
              <div
                data-testid="flow-health-warnings"
                class="px-2 py-1 text-[10px] text-muted-foreground font-medium uppercase mt-1"
              >
                {{ $t("flows.header.warnings") }}
              </div>
              <button
                v-for="(node, index) in flowHealth.warningNodes"
                :key="'w-' + (node.id ?? `flow-${index}`)"
                type="button"
                :data-health-node-id="node.id"
                data-health-severity="warning"
                :disabled="node.id == null"
                class="w-full flex flex-col items-start gap-0.5 px-2 py-1.5 rounded-md text-xs transition-colors enabled:hover:bg-accent disabled:cursor-default"
                @click="navigateToNode(node.id)"
              >
                <span class="truncate">{{ node.label }}</span>
                <span
                  v-for="reason in nodeReasons(node)"
                  :key="reason"
                  class="text-[11px] text-muted-foreground"
                >
                  {{ reason }}
                </span>
              </button>
            </div>
            <div v-if="flowHealth.infoNodes.length > 0">
              <div
                data-testid="flow-health-info"
                class="px-2 py-1 text-[10px] text-muted-foreground font-medium uppercase mt-1"
              >
                {{ $t("flows.header.info") }}
              </div>
              <button
                v-for="(node, index) in flowHealth.infoNodes"
                :key="'i-' + (node.id ?? `flow-${index}`)"
                type="button"
                :data-health-node-id="node.id"
                data-health-severity="info"
                :disabled="node.id == null"
                class="w-full flex flex-col items-start gap-0.5 px-2 py-1.5 rounded-md text-xs transition-colors enabled:hover:bg-accent disabled:cursor-default"
                @click="navigateToNode(node.id)"
              >
                <span class="truncate">{{ node.label }}</span>
                <span
                  v-for="reason in nodeReasons(node)"
                  :key="reason"
                  class="text-[11px] text-muted-foreground"
                >
                  {{ reason }}
                </span>
              </button>
            </div>
          </PopoverContent>
        </Popover>
      </template>
      <ToolbarTooltip v-else :label="$t('flows.header.looks_great')" side="bottom">
        <button
          type="button"
          class="toolbar-btn text-green-500/60"
          data-testid="flow-health-clean-open-analysis"
          @click="openAnalysisPanel"
        >
          <CircleCheck class="size-3.5" />
        </button>
      </ToolbarTooltip>
    </div>

    <!-- Save indicator -->
    <div
      v-if="canEdit && (saveStatus === 'saving' || saveStatus === 'saved')"
      class="flex items-center surface-panel px-2"
    >
      <div
        v-if="saveStatus === 'saving'"
        class="flex items-center gap-1 text-xs text-muted-foreground"
      >
        <div
          class="size-3 border-2 border-muted-foreground/20 border-t-muted-foreground/60 rounded-full animate-spin"
        />
        <span>{{ $t("flows.header.saving") }}</span>
      </div>
      <div
        v-else-if="saveStatus === 'saved'"
        class="flex items-center gap-1 text-xs text-green-500/70"
      >
        <Check class="size-3" />
        <span>{{ $t("flows.header.saved") }}</span>
      </div>
    </div>
  </div>
</template>
