<script setup lang="ts">
import {
  ArrowLeft,
  ArrowRight,
  Check,
  ChevronDown,
  CircleCheck,
  Info,
  Map as MapIcon,
  Save,
  Text,
  TriangleAlert,
  X,
} from "lucide-vue-next";
import { computed, ref } from "vue";
import EditableText from "@components/forms/EditableText.vue";
import { Badge } from "@components/ui/badge";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";
import { useLive } from "@shared/composables/useLive";

interface NavEntry {
  flow_name: string;
}

interface NavHistory {
  back: NavEntry | null;
  forward: NavEntry | null;
}

interface HealthNode {
  id: number | string;
  label: string;
  reason?: string;
}

interface FlowHealth {
  wordCount: number;
  errorNodes: HealthNode[];
  infoNodes: HealthNode[];
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
  flowHealth = { wordCount: 0, errorNodes: [], infoNodes: [] },
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

const errorCount = computed(() => flowHealth.errorNodes.length);
const infoCount = computed(() => flowHealth.infoNodes.length);
const showScene = computed(() => canEdit || sceneSelected.name != null);

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

function navigateToNode(nodeId: number | string): void {
  live.pushEvent("navigate_to_node", { id: nodeId });
  healthOpen.value = false;
}
</script>

<template>
  <div class="flex items-stretch gap-2 h-8">
    <!-- Nav history -->
    <div
      v-if="navHistory.back || navHistory.forward"
      class="flex items-center gap-0.5 surface-panel px-1"
    >
      <button
        v-if="navHistory.back"
        type="button"
        class="toolbar-btn gap-1 text-muted-foreground max-w-35"
        :title="$t('flows.header.nav_back')"
        @click="live.pushEvent('nav_back', {})"
      >
        <ArrowLeft class="size-3.5 shrink-0" />
        <span class="truncate text-xs">{{ navHistory.back.flow_name }}</span>
      </button>
      <button
        v-if="navHistory.forward"
        type="button"
        class="toolbar-btn gap-1 text-muted-foreground max-w-35"
        :title="$t('flows.header.nav_forward')"
        @click="live.pushEvent('nav_forward', {})"
      >
        <span class="truncate text-xs">{{ navHistory.forward.flow_name }}</span>
        <ArrowRight class="size-3.5 shrink-0" />
      </button>
    </div>

    <!-- Flow title pill -->
    <div class="flex items-center gap-1.5 surface-panel px-3 h-full">
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
    <div class="hidden lg:flex items-center gap-1 px-1 py-1 surface-panel text-xs">
      <!-- Scene selector -->
      <template v-if="showScene">
        <Popover v-model:open="sceneOpen">
          <PopoverTrigger as-child>
            <button
              type="button"
              class="toolbar-btn gap-1.5"
              :class="sceneSelected.name ? 'text-foreground' : 'text-muted-foreground'"
              :title="$t('flows.header.scene_backdrop')"
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
            </button>
          </PopoverTrigger>
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
      <div
        class="toolbar-btn gap-1.5 text-muted-foreground"
        :title="`${flowHealth.wordCount} words in this flow`"
      >
        <Text class="size-3.5" />
        <span>{{ flowHealth.wordCount }}</span>
      </div>

      <!-- Flow health indicator -->
      <template v-if="errorCount > 0 || infoCount > 0">
        <Popover v-model:open="healthOpen">
          <PopoverTrigger as-child>
            <button type="button" class="toolbar-btn gap-0">
              <span v-if="errorCount > 0" class="flex items-center gap-1.5 text-destructive">
                <TriangleAlert class="size-3.5" />
                <span>{{ errorCount }}</span>
              </span>
              <span v-if="infoCount > 0" class="flex items-center gap-1.5 ml-2 text-blue-500">
                <Info class="size-3.5" />
                <span>{{ infoCount }}</span>
              </span>
              <ChevronDown class="size-3 opacity-50 ml-1" />
            </button>
          </PopoverTrigger>
          <PopoverContent side="bottom" :side-offset="4" class="w-max max-h-60 overflow-y-auto p-1">
            <div v-if="flowHealth.errorNodes.length > 0">
              <div
                v-if="flowHealth.infoNodes.length > 0"
                class="px-2 py-1 text-[10px] text-muted-foreground font-medium uppercase"
              >
                Errors
              </div>
              <button
                v-for="node in flowHealth.errorNodes"
                :key="'e-' + node.id"
                type="button"
                class="w-full flex items-center gap-2 px-2 py-1.5 rounded-md text-xs hover:bg-accent transition-colors"
                @click="navigateToNode(node.id)"
              >
                <span class="truncate">{{ node.label }}</span>
              </button>
            </div>
            <div v-if="flowHealth.infoNodes.length > 0">
              <div
                v-if="flowHealth.errorNodes.length > 0"
                class="px-2 py-1 text-[10px] text-muted-foreground font-medium uppercase mt-1"
              >
                Info
              </div>
              <button
                v-for="node in flowHealth.infoNodes"
                :key="'i-' + node.id"
                type="button"
                class="w-full flex flex-col items-start gap-0.5 px-2 py-1.5 rounded-md text-xs hover:bg-accent transition-colors"
                @click="navigateToNode(node.id)"
              >
                <span class="truncate">{{ node.label }}</span>
                <span v-if="node.reason" class="text-[11px] text-muted-foreground">{{
                  node.reason
                }}</span>
              </button>
            </div>
          </PopoverContent>
        </Popover>
      </template>
      <div v-else class="toolbar-btn text-green-500/60" :title="$t('flows.header.looks_great')">
        <CircleCheck class="size-3.5" />
      </div>
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
