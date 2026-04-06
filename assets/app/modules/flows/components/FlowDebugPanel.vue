<script setup>
/**
 * Flow debug panel — bottom-docked panel for step-through execution.
 * Tabs: Console, Variables, History.
 */

import {
  Bug,
  ChevronDown,
  Pause,
  Play,
  RotateCcw,
  SkipForward,
  Square,
  StepBack,
} from "lucide-vue-next";
import { computed, ref } from "vue";
import { Badge } from "@components/ui/badge/index.js";
import { Button } from "@components/ui/button/index.js";
import { Input } from "@components/ui/input/index.js";
import { Slider } from "@components/ui/slider/index.js";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@components/ui/tabs/index.js";
import { useLive } from "@composables/useLive.js";

const { open, state, nodes, controls } = defineProps({
  open: { type: Boolean, default: false },
  state: { type: Object, default: null },
  nodes: { type: Object, default: () => ({}) },
  controls: {
    type: Object,
    default: () => ({
      activeTab: "console",
      autoPlaying: false,
      speed: 800,
      varFilter: "",
      varChangedOnly: false,
      flowName: "",
      stepLimitReached: false,
    }),
  },
});

const live = useLive();
const height = ref(280);
const varFilter = ref(controls.varFilter);

const status = computed(() => state?.status || "idle");
const stepCount = computed(() => state?.execution_path?.length || 0);
const currentNodeId = computed(() => state?.current_node_id);
const variables = computed(() => state?.variables || {});
const executionPath = computed(() => state?.execution_path || []);
const pendingChoices = computed(() => state?.pending_choices || []);

const filteredVariables = computed(() => {
  const vars = Object.entries(variables.value);
  let filtered = vars;
  if (varFilter.value) {
    const q = varFilter.value.toLowerCase();
    filtered = filtered.filter(([key]) => key.toLowerCase().includes(q));
  }
  if (controls.varChangedOnly) {
    filtered = filtered.filter(([, v]) => v.changed);
  }
  return filtered;
});

function formatSpeed(ms) {
  return ms >= 1000 ? `${(ms / 1000).toFixed(1)}s` : `${ms}ms`;
}

function step() {
  live.pushEvent("debug_step", {});
}
function stepBack() {
  live.pushEvent("debug_step_back", {});
}
function reset() {
  live.pushEvent("debug_reset", {});
}
function stop() {
  live.pushEvent("debug_stop", {});
}
function togglePlay() {
  live.pushEvent(controls.autoPlaying ? "debug_pause" : "debug_play", {});
}
function setSpeed(val) {
  live.pushEvent("debug_set_speed", { speed: val[0] });
}
function selectChoice(choiceId) {
  live.pushEvent("debug_select_choice", { choice_id: choiceId });
}
function switchTab(tab) {
  live.pushEvent("debug_switch_tab", { tab });
}
</script>

<template>
  <div
    v-if="open && state"
    class="border-t border-border bg-background shrink-0"
    :style="{ height: `${height}px` }"
  >
    <!-- Controls bar -->
    <div class="flex items-center gap-2 px-3 py-1.5 border-b border-border">
      <Bug class="size-4 text-muted-foreground" />

      <!-- Play/Pause -->
      <Button variant="ghost" size="icon-sm" class="size-7" @click="togglePlay">
        <Pause v-if="controls.autoPlaying" class="size-3.5" />
        <Play v-else class="size-3.5" />
      </Button>

      <!-- Step -->
      <Button variant="ghost" size="icon-sm" class="size-7" title="Step (F10)" @click="step">
        <SkipForward class="size-3.5" />
      </Button>

      <!-- Step Back -->
      <Button
        variant="ghost"
        size="icon-sm"
        class="size-7"
        title="Step Back (F9)"
        @click="stepBack"
      >
        <StepBack class="size-3.5" />
      </Button>

      <!-- Reset -->
      <Button variant="ghost" size="icon-sm" class="size-7" title="Reset (F6)" @click="reset">
        <RotateCcw class="size-3.5" />
      </Button>

      <!-- Stop -->
      <Button variant="ghost" size="icon-sm" class="size-7" title="Stop" @click="stop">
        <Square class="size-3.5" />
      </Button>

      <div class="w-px h-5 bg-border mx-1" />

      <!-- Status + step count -->
      <Badge variant="secondary" class="text-[10px]">
        {{ status }}
      </Badge>
      <span class="text-xs text-muted-foreground">Step {{ stepCount }}</span>

      <div class="w-px h-5 bg-border mx-1" />

      <!-- Speed slider -->
      <span class="text-xs text-muted-foreground">{{ formatSpeed(controls.speed) }}</span>
      <Slider
        :model-value="[controls.speed]"
        :min="200"
        :max="3000"
        :step="100"
        class="w-24"
        @update:model-value="setSpeed"
      />

      <!-- Flow name -->
      <span class="ml-auto text-xs text-muted-foreground truncate max-w-[150px]">
        {{ controls.flowName }}
      </span>
    </div>

    <!-- Step limit warning -->
    <div
      v-if="controls.stepLimitReached"
      class="px-3 py-1.5 bg-amber-500/10 text-amber-600 text-xs flex items-center gap-2"
    >
      Step limit reached. Reset to continue.
    </div>

    <!-- Tab content -->
    <Tabs
      :model-value="controls.activeTab"
      class="h-[calc(100%-44px)]"
      @update:model-value="switchTab"
    >
      <TabsList class="px-3 pt-1">
        <TabsTrigger value="console" class="text-xs">Console</TabsTrigger>
        <TabsTrigger value="variables" class="text-xs">Variables</TabsTrigger>
        <TabsTrigger value="history" class="text-xs">History</TabsTrigger>
      </TabsList>

      <!-- Console -->
      <TabsContent value="console" class="overflow-y-auto px-3 pb-3 h-full">
        <!-- Pending choices -->
        <div v-if="pendingChoices.length > 0" class="space-y-1 mb-3">
          <div class="text-xs text-muted-foreground font-medium">Choose a response:</div>
          <button
            v-for="choice in pendingChoices"
            :key="choice.id"
            type="button"
            class="w-full text-left text-sm px-3 py-2 rounded-md border border-border hover:bg-accent transition-colors"
            @click="selectChoice(choice.id)"
          >
            {{ choice.text || "(empty)" }}
          </button>
        </div>
        <div v-else class="text-xs text-muted-foreground py-4 text-center">
          Waiting for execution...
        </div>
      </TabsContent>

      <!-- Variables -->
      <TabsContent value="variables" class="overflow-y-auto px-3 pb-3 h-full">
        <Input
          v-model="varFilter"
          type="search"
          placeholder="Filter variables..."
          class="h-7 text-xs mb-2"
        />
        <div class="space-y-0.5">
          <div
            v-for="[key, val] in filteredVariables"
            :key="key"
            class="flex items-center justify-between text-xs py-1 px-2 rounded"
            :class="val.changed ? 'bg-amber-500/10' : ''"
          >
            <span class="font-mono truncate">{{ key }}</span>
            <span class="text-muted-foreground ml-2 truncate max-w-[150px]">{{
              val.value ?? "nil"
            }}</span>
          </div>
        </div>
      </TabsContent>

      <!-- History -->
      <TabsContent value="history" class="overflow-y-auto px-3 pb-3 h-full">
        <div
          v-for="(nodeId, i) in executionPath"
          :key="i"
          class="flex items-center gap-2 text-xs py-1"
        >
          <span class="text-muted-foreground w-6 text-right">{{ i + 1 }}</span>
          <span class="font-mono">{{ nodes[nodeId]?.label || nodeId }}</span>
        </div>
      </TabsContent>
    </Tabs>
  </div>
</template>
