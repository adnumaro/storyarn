<script setup lang="ts">
import {
  ArrowLeft,
  ArrowRight,
  Check,
  ChevronDown,
  Map as MapIcon,
  MessageCircle,
  Text,
  X,
} from "@lucide/vue";
import { computed, ref } from "vue";
import EditableText from "@components/forms/EditableText.vue";
import ToolbarTooltip from "@components/toolbar/ToolbarTooltip.vue";
import { Badge } from "@components/ui/badge";
import { Popover, PopoverAnchor, PopoverContent, PopoverTrigger } from "@components/ui/popover";
import { useLive } from "@shared/composables/useLive";
import type { FlowHealth } from "@modules/flows/types/health";
import FlowHealthStatus from "@modules/flows/editor/components/chrome/header/FlowHealthStatus.vue";

interface NavEntry {
  flow_name: string;
}

interface NavHistory {
  back: NavEntry | null;
  forward: NavEntry | null;
}

interface FlowHealthProp {
  wordCount: number;
  health: FlowHealth;
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
    health: { errorItems: [], warningItems: [], infoItems: [] },
  },
  sceneSelected = { name: null, inherited: false },
  projectScenes = [],
  comments = { count: 0, open: false },
} = defineProps<{
  flowName: string;
  flowShortcut: string;
  isMain: boolean;
  canEdit: boolean;
  saveStatus: string;
  navHistory: NavHistory;
  flowHealth: FlowHealthProp;
  sceneSelected: SceneSelected;
  projectScenes: ProjectScene[];
  comments?: { count: number; open: boolean };
}>();

const live = useLive();
const sceneOpen = ref(false);
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

      <!-- Flow health: the shared popover, same as sheets and scenes -->
      <FlowHealthStatus :health="flowHealth.health" />
    </div>

    <ToolbarTooltip :label="$t('flows.comments.title')" side="bottom">
      <button
        id="flow-comments-toggle"
        type="button"
        class="toolbar-btn h-full gap-1.5 px-2"
        :class="comments.open ? 'text-primary' : 'text-muted-foreground'"
        :aria-label="$t('flows.comments.title')"
        :aria-expanded="comments.open"
        aria-controls="flow-comments-panel"
        @click="live.pushEvent(comments.open ? 'comments_close' : 'comments_open', {})"
      >
        <MessageCircle class="size-3.5" />
        <span class="hidden sm:inline">{{ $t("flows.comments.title") }}</span>
        <span v-if="comments.count" class="text-xs tabular-nums">{{ comments.count }}</span>
      </button>
    </ToolbarTooltip>

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
