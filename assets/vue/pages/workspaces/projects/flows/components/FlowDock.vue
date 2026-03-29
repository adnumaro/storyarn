<script setup>
import {
	ArrowRightToLine,
	Box,
	Bug,
	Clapperboard,
	GitBranch,
	History,
	LogIn,
	LogOut,
	MessageSquare,
	Play,
	StickyNote,
	Zap,
} from "lucide-vue-next";
import { ref } from "vue";
import {
	Popover,
	PopoverContent,
	PopoverTrigger,
} from "@/vue/components/ui/popover/index.js";
import { useLive } from "@/vue/composables/useLive.js";

const props = defineProps({
	canEdit: { type: Boolean, default: false },
	compact: { type: Boolean, default: false },
	debugPanelOpen: { type: Boolean, default: false },
	workspaceSlug: { type: String, required: true },
	projectSlug: { type: String, required: true },
	flowId: { type: [String, Number], required: true },
});

const live = useLive();

const narrativeOpen = ref(false);
const logicOpen = ref(false);
const navigationOpen = ref(false);

const narrativeNodes = [
	{
		type: "dialogue",
		icon: MessageSquare,
		title: "Dialogue",
		description: "Character speech and player responses",
	},
	{
		type: "slug_line",
		icon: Clapperboard,
		title: "Slug Line",
		description: "Scene heading or location marker",
	},
];

const logicNodes = [
	{
		type: "condition",
		icon: GitBranch,
		title: "Condition",
		description: "Branch based on variable conditions",
	},
	{
		type: "instruction",
		icon: Zap,
		title: "Instruction",
		description: "Set or modify variable values",
	},
];

const navigationNodes = [
	{
		type: "exit",
		icon: ArrowRightToLine,
		title: "Exit",
		description: "End point of a flow",
	},
	{
		type: "hub",
		icon: LogIn,
		title: "Hub",
		description: "Named junction for jump targets",
	},
	{
		type: "jump",
		icon: LogOut,
		title: "Jump",
		description: "Jump to a hub in any flow",
	},
	{
		type: "subflow",
		icon: Box,
		title: "Subflow",
		description: "Embed another flow as a node",
	},
];

function addNode(type) {
	live.pushEvent("add_node", { type });
	narrativeOpen.value = false;
	logicOpen.value = false;
	navigationOpen.value = false;
}

function addAnnotation() {
	live.pushEvent("add_annotation", {});
}

function openVersions() {
	live.pushEvent("open_versions_panel", {});
}

function toggleDebug() {
	live.pushEvent(props.debugPanelOpen ? "debug_stop" : "debug_start", {});
}

const playUrl = `/workspaces/${props.workspaceSlug}/projects/${props.projectSlug}/flows/${props.flowId}/play`;
</script>

<template>
  <div v-if="canEdit">
    <div
      class="absolute bottom-3 left-1/2 -translate-x-1/2 z-30 flex items-center gap-1 v2-surface-panel px-2 py-2"
    >
      <!-- Annotation -->
      <div class="v2-dock-item group relative">
        <button type="button" class="v2-dock-btn" @click="addAnnotation">
          <StickyNote class="size-5" />
        </button>
        <div class="v2-dock-tooltip">
          <div class="text-sm font-semibold mb-0.5">Note</div>
          <div class="text-xs text-muted-foreground leading-relaxed">
            Add a sticky note to the canvas
          </div>
        </div>
      </div>

      <!-- Separator -->
      <div class="w-px h-6 bg-border mx-0.5 shrink-0" />

      <!-- Narrative dropdown -->
      <div class="v2-dock-item group relative">
        <Popover v-model:open="narrativeOpen">
          <PopoverTrigger as-child>
            <button type="button" class="v2-dock-btn">
              <MessageSquare class="size-5" />
            </button>
          </PopoverTrigger>
          <PopoverContent side="top" :side-offset="12" class="w-56 p-3">
            <div class="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-2 px-1">
              Narrative
            </div>
            <div class="flex flex-col gap-0.5">
              <button
                v-for="n in narrativeNodes"
                :key="n.type"
                type="button"
                class="w-full flex items-start gap-2.5 px-2.5 py-2 rounded-lg text-sm text-start cursor-pointer hover:bg-accent transition-colors"
                @click="addNode(n.type)"
              >
                <component :is="n.icon" class="size-4 mt-0.5 shrink-0" />
                <div>
                  <div class="font-medium">{{ n.title }}</div>
                  <div class="text-xs text-muted-foreground">{{ n.description }}</div>
                </div>
              </button>
            </div>
          </PopoverContent>
        </Popover>
        <div v-if="!narrativeOpen" class="v2-dock-tooltip">
          <div class="text-sm font-semibold mb-0.5">Narrative</div>
          <div class="text-xs text-muted-foreground leading-relaxed">
            Story and dialogue nodes
          </div>
        </div>
      </div>

      <!-- Logic dropdown -->
      <div class="v2-dock-item group relative">
        <Popover v-model:open="logicOpen">
          <PopoverTrigger as-child>
            <button type="button" class="v2-dock-btn">
              <Zap class="size-5" />
            </button>
          </PopoverTrigger>
          <PopoverContent side="top" :side-offset="12" class="w-56 p-3">
            <div class="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-2 px-1">
              Logic
            </div>
            <div class="flex flex-col gap-0.5">
              <button
                v-for="n in logicNodes"
                :key="n.type"
                type="button"
                class="w-full flex items-start gap-2.5 px-2.5 py-2 rounded-lg text-sm text-start cursor-pointer hover:bg-accent transition-colors"
                @click="addNode(n.type)"
              >
                <component :is="n.icon" class="size-4 mt-0.5 shrink-0" />
                <div>
                  <div class="font-medium">{{ n.title }}</div>
                  <div class="text-xs text-muted-foreground">{{ n.description }}</div>
                </div>
              </button>
            </div>
          </PopoverContent>
        </Popover>
        <div v-if="!logicOpen" class="v2-dock-tooltip">
          <div class="text-sm font-semibold mb-0.5">Logic</div>
          <div class="text-xs text-muted-foreground leading-relaxed">
            Conditions and instructions
          </div>
        </div>
      </div>

      <!-- Navigation dropdown -->
      <div class="v2-dock-item group relative">
        <Popover v-model:open="navigationOpen">
          <PopoverTrigger as-child>
            <button type="button" class="v2-dock-btn">
              <ArrowRightToLine class="size-5" />
            </button>
          </PopoverTrigger>
          <PopoverContent side="top" :side-offset="12" class="w-56 p-3">
            <div class="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-2 px-1">
              Navigation
            </div>
            <div class="flex flex-col gap-0.5">
              <button
                v-for="n in navigationNodes"
                :key="n.type"
                type="button"
                class="w-full flex items-start gap-2.5 px-2.5 py-2 rounded-lg text-sm text-start cursor-pointer hover:bg-accent transition-colors"
                @click="addNode(n.type)"
              >
                <component :is="n.icon" class="size-4 mt-0.5 shrink-0" />
                <div>
                  <div class="font-medium">{{ n.title }}</div>
                  <div class="text-xs text-muted-foreground">{{ n.description }}</div>
                </div>
              </button>
            </div>
          </PopoverContent>
        </Popover>
        <div v-if="!navigationOpen" class="v2-dock-tooltip">
          <div class="text-sm font-semibold mb-0.5">Navigation</div>
          <div class="text-xs text-muted-foreground leading-relaxed">
            Flow control and routing
          </div>
        </div>
      </div>

      <!-- Actions group (not in compact mode) -->
      <template v-if="!compact">
        <!-- Separator -->
        <div class="w-px h-6 bg-border mx-0.5 shrink-0" />

        <!-- Version History -->
        <div class="v2-dock-item group relative">
          <button type="button" class="v2-dock-btn" @click="openVersions">
            <History class="size-5" />
          </button>
          <div class="v2-dock-tooltip">
            <div class="text-sm font-semibold mb-0.5">Version History</div>
            <div class="text-xs text-muted-foreground leading-relaxed">
              View and manage version history
            </div>
          </div>
        </div>

        <!-- Play -->
        <div class="v2-dock-item group relative">
          <a
            :href="playUrl"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="v2-dock-btn"
          >
            <Play class="size-5" />
          </a>
          <div class="v2-dock-tooltip">
            <div class="text-sm font-semibold mb-0.5">Play</div>
            <div class="text-xs text-muted-foreground leading-relaxed">
              Run this flow in story player
            </div>
          </div>
        </div>

        <!-- Debug -->
        <div class="v2-dock-item group relative">
          <button
            type="button"
            class="v2-dock-btn"
            :class="{ 'v2-dock-btn-active': debugPanelOpen }"
            @click="toggleDebug"
          >
            <Bug class="size-5" />
          </button>
          <div class="v2-dock-tooltip">
            <div class="text-sm font-semibold mb-0.5">Debug</div>
            <div class="text-xs text-muted-foreground leading-relaxed">
              Step through flow execution
            </div>
          </div>
        </div>
      </template>
    </div>
  </div>
</template>
