<script setup>
import {
  ArrowLeft,
  ArrowRight,
  Check,
  ChevronDown,
  CircleCheck,
  GitBranch,
  Info,
  Map as MapIcon,
  Save,
  Text,
  TriangleAlert,
  X,
} from "lucide-vue-next";
import { computed, ref } from "vue";
import EditableText from "@components/EditableText.vue";
import { Badge } from "@components/ui/badge/index.js";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover/index.js";
import { useLive } from "@composables/useLive.js";

const { flowName, flowShortcut, isMain, canEdit, saveStatus, isDraft, backEntry, forwardEntry, flowWordCount, flowErrorNodes, flowInfoNodes, sceneName, sceneInherited, availableScenes } = defineProps({
  flowName: { type: String, default: "" },
  flowShortcut: { type: String, default: "" },
  isMain: { type: Boolean, default: false },
  canEdit: { type: Boolean, default: false },
  saveStatus: { type: String, default: "idle" },
  isDraft: { type: Boolean, default: false },
  // Nav history
  backEntry: { type: Object, default: null },
  forwardEntry: { type: Object, default: null },
  // Stats
  flowWordCount: { type: Number, default: 0 },
  flowErrorNodes: { type: Array, default: () => [] },
  flowInfoNodes: { type: Array, default: () => [] },
  // Scene
  sceneName: { type: String, default: null },
  sceneInherited: { type: Boolean, default: false },
  availableScenes: { type: Array, default: () => [] },
});

const live = useLive();
const sceneOpen = ref(false);
const healthOpen = ref(false);

const errorCount = computed(() => flowErrorNodes.length);
const infoCount = computed(() => flowInfoNodes.length);
const showScene = computed(() => canEdit || sceneName != null);

function saveName(name) {
  live.pushEvent("save_name", { name });
}

function saveShortcut(shortcut) {
  live.pushEvent("save_shortcut", { shortcut });
}

function selectScene(sceneId) {
  live.pushEvent("update_scene", { scene_id: sceneId || "" });
  sceneOpen.value = false;
}

function navigateToNode(nodeId) {
  live.pushEvent("navigate_to_node", { id: nodeId });
  healthOpen.value = false;
}
</script>

<template>
  <div class="flex items-stretch gap-2">
    <!-- Nav history -->
    <div v-if="backEntry || forwardEntry" class="flex items-center gap-0.5 v2-surface-panel px-1">
      <button
        v-if="backEntry"
        type="button"
        class="v2-toolbar-btn gap-1 text-muted-foreground max-w-[140px]"
        title="Alt+Left"
        @click="live.pushEvent('nav_back', {})"
      >
        <ArrowLeft class="size-3.5 shrink-0" />
        <span class="truncate text-xs">{{ backEntry.flow_name }}</span>
      </button>
      <button
        v-if="forwardEntry"
        type="button"
        class="v2-toolbar-btn gap-1 text-muted-foreground max-w-[140px]"
        title="Alt+Right"
        @click="live.pushEvent('nav_forward', {})"
      >
        <span class="truncate text-xs">{{ forwardEntry.flow_name }}</span>
        <ArrowRight class="size-3.5 shrink-0" />
      </button>
    </div>

    <!-- Flow title pill -->
    <div class="flex items-center gap-1.5 v2-surface-panel px-3 h-full">
      <EditableText
        :model-value="flowName"
        placeholder="Untitled"
        tag="span"
        class="text-sm font-medium max-w-[200px] truncate"
        :disabled="!canEdit"
        @save="saveName"
      />
      <EditableText
        v-if="flowShortcut || canEdit"
        :model-value="flowShortcut"
        placeholder="add-shortcut"
        tag="span"
        class="text-xs text-muted-foreground max-w-[120px] truncate"
        :disabled="!canEdit"
        @save="saveShortcut"
      />
      <Badge v-if="isMain" variant="default" class="text-[10px] px-1.5 py-0 rounded-full shrink-0">
        Main
      </Badge>
    </div>

    <!-- Stats + Scene panel -->
    <div class="hidden lg:flex items-center gap-1 px-1 py-1 v2-surface-panel text-xs">
      <!-- Scene selector -->
      <template v-if="showScene">
        <Popover v-model:open="sceneOpen">
          <PopoverTrigger as-child>
            <button
              type="button"
              class="v2-toolbar-btn gap-1.5"
              :class="sceneName ? 'text-foreground' : 'text-muted-foreground'"
              title="Scene backdrop"
            >
              <MapIcon class="size-3.5" />
              <span v-if="sceneName" class="truncate max-w-[120px]">{{ sceneName }}</span>
              <span v-else>No scene</span>
              <span v-if="sceneInherited" class="text-muted-foreground text-[10px]"
                >(inherited)</span
              >
              <ChevronDown v-if="canEdit" class="size-3 opacity-50" />
            </button>
          </PopoverTrigger>
          <PopoverContent v-if="canEdit" side="bottom" :side-offset="4" class="w-56 p-1">
            <button
              type="button"
              class="w-full flex items-center gap-2 px-2 py-1.5 rounded-md text-xs hover:bg-accent transition-colors"
              :class="{ 'bg-accent': !sceneName }"
              @click="selectScene(null)"
            >
              <X class="size-3 opacity-60" />
              <span class="text-muted-foreground">No scene (inherit)</span>
            </button>
            <button
              v-for="scene in availableScenes"
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
        class="v2-toolbar-btn gap-1.5 text-muted-foreground"
        :title="`${flowWordCount} words in this flow`"
      >
        <Text class="size-3.5" />
        <span>{{ flowWordCount }}</span>
      </div>

      <!-- Flow health indicator -->
      <template v-if="errorCount > 0 || infoCount > 0">
        <Popover v-model:open="healthOpen">
          <PopoverTrigger as-child>
            <button type="button" class="v2-toolbar-btn gap-0">
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
            <div v-if="flowErrorNodes.length > 0">
              <div
                v-if="flowInfoNodes.length > 0"
                class="px-2 py-1 text-[10px] text-muted-foreground font-medium uppercase"
              >
                Errors
              </div>
              <button
                v-for="node in flowErrorNodes"
                :key="'e-' + node.id"
                type="button"
                class="w-full flex items-center gap-2 px-2 py-1.5 rounded-md text-xs hover:bg-accent transition-colors"
                @click="navigateToNode(node.id)"
              >
                <span class="truncate">{{ node.label }}</span>
              </button>
            </div>
            <div v-if="flowInfoNodes.length > 0">
              <div
                v-if="flowErrorNodes.length > 0"
                class="px-2 py-1 text-[10px] text-muted-foreground font-medium uppercase mt-1"
              >
                Info
              </div>
              <button
                v-for="node in flowInfoNodes"
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
      <div v-else class="v2-toolbar-btn text-green-500/60" title="This flow looks great!">
        <CircleCheck class="size-3.5" />
      </div>
    </div>

    <!-- Draft button -->
    <button
      v-if="canEdit && !isDraft"
      type="button"
      class="hidden lg:flex items-center gap-1 v2-toolbar-btn text-muted-foreground v2-surface-panel px-2"
      title="Create a private draft copy"
      @click="live.pushEvent('create_draft', {})"
    >
      <GitBranch class="size-3.5" />
      <span class="text-xs">Draft</span>
    </button>

    <!-- Save indicator -->
    <div v-if="canEdit" class="flex items-center v2-surface-panel px-2">
      <div
        v-if="saveStatus === 'saving'"
        class="flex items-center gap-1 text-xs text-muted-foreground"
      >
        <div
          class="size-3 border-2 border-muted-foreground/20 border-t-muted-foreground/60 rounded-full animate-spin"
        />
        <span>Saving</span>
      </div>
      <div
        v-else-if="saveStatus === 'saved'"
        class="flex items-center gap-1 text-xs text-green-500/70"
      >
        <Check class="size-3" />
        <span>Saved</span>
      </div>
    </div>
  </div>
</template>
