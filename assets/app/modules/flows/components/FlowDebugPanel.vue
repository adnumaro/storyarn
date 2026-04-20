<script setup lang="ts">
/**
 * Flow debug panel — bottom-docked panel for step-through execution.
 * Phase 1: frame, resize, breadcrumb, start-node select, step-limit continue.
 * Tabs Console / Variables / History / Path are minimally rendered pending
 * Phases 2–6.
 */

import {
  ArrowDownRight,
  ArrowRightToLine,
  ArrowUpLeft,
  Box,
  Bug,
  ChevronDown,
  ChevronRight,
  Circle,
  CircleX,
  Clapperboard,
  Diff,
  FastForward,
  Gauge,
  GitBranch,
  Info,
  Layers,
  LogIn,
  LogOut,
  MessageSquare,
  Pause,
  Play,
  RotateCcw,
  Search,
  Square,
  StickyNote,
  TriangleAlert,
  Undo2,
  Zap,
} from "lucide-vue-next";
import { computed, ref } from "vue";
import { Badge } from "@components/ui/badge/index.ts";
import { Button } from "@components/ui/button/index.ts";
import { Checkbox } from "@components/ui/checkbox/index.ts";
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "@components/ui/command/index.ts";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover/index.ts";
import { Slider } from "@components/ui/slider/index.ts";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@components/ui/tabs/index.ts";
import { useDebounceFn } from "@vueuse/core";
import BooleanToggle from "@components/BooleanToggle.vue";
import { useColumnResize } from "@composables/useColumnResize";
import { useLive } from "@composables/useLive";
import { useVerticalResize } from "@composables/useVerticalResize";
import { formatDebugTs, formatDebugValue, stripHtml } from "../lib/debug-format";

type DebugStatus = "paused" | "waiting_input" | "finished" | string;
type VariableSource = "initial" | "user_override" | "instruction" | string;

interface DebugChoice {
  id: string | number;
  text: string;
  valid: boolean;
}

interface VariableOption {
  key: string;
  value: string;
}

interface VariableConstraints {
  mode?: "two_state" | "tri_state";
  max_options?: number | null;
  [key: string]: unknown;
}

type VariableValue = string | number | boolean | string[] | null;

interface DebugVariable {
  value: VariableValue;
  initial_value: VariableValue;
  previous_value: VariableValue;
  source: VariableSource;
  block_type: string;
  variable_name: string;
  sheet_shortcut: string;
  changed: boolean;
  options: VariableOption[] | null;
  constraints: VariableConstraints | null;
}

interface DebugCallStackFrame {
  flow_id: number;
  flow_name?: string;
  return_node_id: number;
}

type ConsoleLevel = "info" | "warning" | "error" | string;

interface ConsoleRuleDetail {
  variable_ref: string;
  operator: string;
  expected_value: unknown;
  actual_value: unknown;
  passed: boolean;
}

interface ConsoleEntry {
  ts: number;
  level: ConsoleLevel;
  node_id: number | null;
  node_label: string;
  message: string;
  rule_details: ConsoleRuleDetail[] | null;
}

type HistorySource = "instruction" | "user_override" | string;

interface HistoryEntry {
  ts: number;
  node_id: number | null;
  node_label: string;
  variable_ref: string;
  old_value: unknown;
  new_value: unknown;
  source: HistorySource;
}

interface ExecutionLogEntry {
  node_id: number;
  depth: number;
}

interface DebugState {
  status: DebugStatus;
  current_node_id: string | number | null;
  start_node_id: number | null;
  step_count: number;
  max_steps: number;
  variables: Record<string, DebugVariable>;
  console: ConsoleEntry[];
  history: HistoryEntry[];
  execution_path: number[];
  execution_log: ExecutionLogEntry[];
  pending_choices: DebugChoice[] | null;
  call_stack: DebugCallStackFrame[];
  breakpoints: number[];
}

type PathEntry =
  | {
      separator: true;
      direction: "enter" | "return";
      depth: number;
    }
  | {
      separator: false;
      step: number;
      node_id: number;
      type: string;
      label: string | null;
      outcome: string | null;
      is_current: boolean;
      depth: number;
    };

interface DebugNodeInfo {
  label?: string;
  type: string;
  data?: Record<string, unknown>;
}

interface DebugControls {
  activeTab: string;
  autoPlaying: boolean;
  speed: number;
  varFilter: string;
  varChangedOnly: boolean;
  flowName: string;
  stepLimitReached: boolean;
}

const {
  open = false,
  state = null,
  nodes = {},
  controls = {
    activeTab: "console",
    autoPlaying: false,
    speed: 800,
    varFilter: "",
    varChangedOnly: false,
    flowName: "",
    stepLimitReached: false,
  },
} = defineProps<{
  open: boolean;
  state: DebugState | null;
  nodes: Record<string, DebugNodeInfo>;
  controls: DebugControls;
}>();

const live = useLive();
const { height, onPointerDown } = useVerticalResize({
  initial: 280,
  min: 120,
  max: 600,
});
const { widths: colWidths, startResize: startColResize } = useColumnResize([
  { id: "variable", default: 220, min: 80 },
  { id: "type", default: 88, min: 60 },
  { id: "initial", default: 140, min: 60 },
  { id: "previous", default: 140, min: 60 },
  { id: "current", default: 180, min: 80 },
]);
const varFilter = ref(controls.varFilter);
const startSelectOpen = ref(false);
const editingVar = ref<string | null>(null);

const pushVarFilterDebounced = useDebounceFn((value: string) => {
  live.pushEvent("debug_var_filter", { filter: value });
}, 150);

const variables = computed(() => state?.variables || {});
const pendingChoices = computed(() => state?.pending_choices || []);
const consoleEntries = computed<ConsoleEntry[]>(() =>
  state?.console ? [...state.console].reverse() : [],
);
const historyEntries = computed<HistoryEntry[]>(() =>
  state?.history ? [...state.history].reverse() : [],
);

const breakpointSet = computed<Set<number>>(() => new Set(state?.breakpoints ?? []));

const pathEntries = computed<PathEntry[]>(() => {
  if (!state) return [];

  const log: ExecutionLogEntry[] =
    state.execution_log && state.execution_log.length > 0
      ? [...state.execution_log].reverse()
      : [...state.execution_path].reverse().map((id) => ({ node_id: Number(id), depth: 0 }));

  const nodeConsole = state.console
    .filter((e) => e.node_id != null)
    .slice()
    .reverse() as (ConsoleEntry & { node_id: number })[];

  const result: PathEntry[] = [];
  const logLength = log.length;
  let prevDepth = 0;
  const remaining = [...nodeConsole];

  log.forEach((logEntry, i) => {
    const step = i + 1;
    const depth = logEntry.depth;

    if (depth > prevDepth) {
      result.push({ separator: true, direction: "enter", depth });
    } else if (depth < prevDepth) {
      result.push({ separator: true, direction: "return", depth });
    }

    const node = nodes[String(logEntry.node_id)];
    let outcome: string | null = null;
    const matchIdx = remaining.findIndex((e) => e.node_id === logEntry.node_id);
    if (matchIdx !== -1) {
      outcome = remaining[matchIdx].message;
      remaining.splice(matchIdx, 1);
    }

    const rawText = node?.data?.text as string | undefined;
    const label = stripHtml(rawText, 30);

    result.push({
      separator: false,
      step,
      node_id: logEntry.node_id,
      type: node?.type ?? "unknown",
      label,
      outcome,
      is_current: step === logLength,
      depth,
    });
    prevDepth = depth;
  });

  return result;
});

const NODE_TYPE_ICON: Record<string, typeof Circle> = {
  entry: Play,
  exit: ArrowRightToLine,
  dialogue: MessageSquare,
  condition: GitBranch,
  instruction: Zap,
  hub: LogIn,
  jump: LogOut,
  subflow: Box,
  slug_line: Clapperboard,
  annotation: StickyNote,
};

function pathIcon(type: string) {
  return NODE_TYPE_ICON[type] ?? Circle;
}

function toggleBreakpoint(nodeId: number) {
  live.pushEvent("debug_toggle_breakpoint", { node_id: nodeId });
}
const callStack = computed<DebugCallStackFrame[]>(() =>
  state?.call_stack ? [...state.call_stack].reverse() : [],
);
const hasCallStack = computed(() => callStack.value.length > 0);

const filteredVariables = computed(() => {
  let filtered = Object.entries(variables.value);
  if (varFilter.value) {
    const q = varFilter.value.toLowerCase();
    filtered = filtered.filter(([key]) => key.toLowerCase().includes(q));
  }
  if (controls.varChangedOnly) {
    filtered = filtered.filter(([, v]) => v.changed);
  }
  return filtered.sort(([a], [b]) => a.localeCompare(b));
});

const totalVariables = computed(() => Object.keys(variables.value).length);

const varSourceColor: Record<VariableSource, string> = {
  instruction: "text-amber-500",
  user_override: "text-sky-500",
  initial: "text-muted-foreground",
};

function sourceColor(source: VariableSource): string {
  return varSourceColor[source] ?? "text-muted-foreground";
}

/**
 * Variable keys shaped as `sheet.table.row.col` (4 parts) are table cells;
 * `sheet.var_name` (2 parts) are block variables. We detect by dot count so
 * the backend doesn't have to ship extra metadata for this MVP.
 */
function isTableCell(key: string): boolean {
  return key.split(".").length === 4;
}

function typeLabel(key: string, blockType: string): string {
  return isTableCell(key) ? `table(${blockType})` : blockType;
}

function displayValue(var_: DebugVariable): string {
  if (var_.block_type === "select" && typeof var_.value === "string" && var_.options) {
    return var_.options.find((o) => o.key === var_.value)?.value ?? var_.value;
  }
  if (var_.block_type === "multi_select" && Array.isArray(var_.value)) {
    const options = var_.options;
    const labels = options
      ? var_.value.map((k) => options.find((o) => o.key === k)?.value ?? k)
      : var_.value;
    return labels.length === 0 ? "" : labels.join(", ");
  }
  return formatDebugValue(var_.value);
}

function isReadOnlyVariable(var_: DebugVariable): boolean {
  return var_.block_type === "formula";
}

function isTriStateBoolean(var_: DebugVariable): boolean {
  return var_.block_type === "boolean" && var_.constraints?.mode === "tri_state";
}

function selectedMultiKeys(var_: DebugVariable): string[] {
  return Array.isArray(var_.value) ? (var_.value as string[]) : [];
}

function onBooleanChange(key: string, value: boolean | null) {
  let serialized: "true" | "false" | "nil";
  if (value === null) serialized = "nil";
  else if (value) serialized = "true";
  else serialized = "false";
  live.pushEvent("debug_set_variable", { key, value: serialized });
}

function toggleMultiOption(var_: DebugVariable, key: string, optionKey: string) {
  const current = selectedMultiKeys(var_);
  const next = current.includes(optionKey)
    ? current.filter((k) => k !== optionKey)
    : [...current, optionKey];
  live.pushEvent("debug_set_variable", { key, value: next });
}

function historySourceLabelKey(source: HistorySource): string | null {
  if (source === "instruction") return "flows.debug.history_source_instruction";
  if (source === "user_override") return "flows.debug.history_source_user";
  return null;
}

function historySourceBadgeClass(source: HistorySource): string {
  if (source === "instruction") return "bg-amber-500/15 text-amber-600 border-amber-500/30";
  if (source === "user_override") return "bg-sky-500/15 text-sky-600 border-sky-500/30";
  return "bg-muted text-muted-foreground border-border";
}

function onVarFilterInput(event: Event) {
  const target = event.target as HTMLInputElement;
  varFilter.value = target.value;
  pushVarFilterDebounced(target.value);
}

function toggleChangedOnly() {
  live.pushEvent("debug_var_toggle_changed", {});
}

function startEdit(var_: DebugVariable, key: string) {
  if (isReadOnlyVariable(var_)) return;
  editingVar.value = key;
}

function cancelEdit() {
  editingVar.value = null;
}

function submitEdit(key: string, value: string | number | boolean) {
  live.pushEvent("debug_set_variable", { key, value: String(value) });
  editingVar.value = null;
}

function onEditBlur(key: string, event: FocusEvent) {
  const input = event.target as HTMLInputElement;
  submitEdit(key, input.value);
}

function onEditEnter(key: string, event: KeyboardEvent) {
  event.preventDefault();
  const input = event.target as HTMLInputElement;
  submitEdit(key, input.value);
}

function formatSpeed(ms: number): string {
  return ms >= 1000 ? `${(ms / 1000).toFixed(1)}s` : `${ms}ms`;
}

function startNodeLabel(node: DebugNodeInfo | undefined, id: string | number): string {
  if (!node) return String(id);
  const typeLabel = node.type.charAt(0).toUpperCase() + node.type.slice(1);
  const name = stripHtml(node.data?.text, 20);
  return name ? `${typeLabel}: ${name}` : `${typeLabel} #${id}`;
}

function cleanResponseText(text: unknown): string | null {
  return stripHtml(text, 40);
}

const LEVEL_ICON: Record<ConsoleLevel, typeof Info> = {
  info: Info,
  warning: TriangleAlert,
  error: CircleX,
};

function levelIcon(level: ConsoleLevel) {
  return LEVEL_ICON[level] ?? Info;
}

function levelColor(level: ConsoleLevel): string {
  if (level === "warning") return "text-amber-500";
  if (level === "error") return "text-destructive";
  if (level === "info") return "text-sky-500";
  return "text-muted-foreground";
}

function levelBg(level: ConsoleLevel): string {
  if (level === "warning") return "bg-amber-500/5";
  if (level === "error") return "bg-destructive/5";
  return "";
}

interface StartNodeOption {
  id: string | number;
  label: string;
  searchText: string;
  isEntry: boolean;
}

const startNodeOptions = computed<StartNodeOption[]>(() => {
  const entries = Object.entries(nodes).map(([id, node]) => {
    const numId: string | number = /^-?\d+$/.test(id) ? Number(id) : id;
    const label = startNodeLabel(node, numId);
    return {
      id: numId,
      label,
      searchText: label.toLowerCase(),
      isEntry: node.type === "entry",
    };
  });
  entries.sort((a, b) => {
    if (a.isEntry !== b.isEntry) return a.isEntry ? -1 : 1;
    return a.label.localeCompare(b.label);
  });
  return entries;
});

const currentStartNodeLabel = computed(() => {
  const current = startNodeOptions.value.find((o) => o.id === state?.start_node_id);
  return current?.label ?? null;
});

function statusBadgeVariant(status: DebugStatus): "secondary" | "default" | "outline" {
  if (status === "finished") return "outline";
  if (status === "waiting_input") return "default";
  return "secondary";
}

const STATUS_KEYS: Record<string, string> = {
  paused: "flows.debug.status_paused",
  waiting_input: "flows.debug.status_waiting",
  finished: "flows.debug.status_finished",
};

function statusKey(status: DebugStatus): string | null {
  return STATUS_KEYS[status] ?? null;
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
function setSpeed(val: number[] | undefined): void {
  if (!val || val.length === 0) return;
  live.pushEvent("debug_set_speed", { speed: val[0] });
}
function selectChoice(choiceId: string | number): void {
  live.pushEvent("debug_choose_response", { id: choiceId });
}
function switchTab(tab: string | number): void {
  live.pushEvent("debug_tab_change", { tab });
}
function changeStartNode(nodeId: string | number) {
  live.pushEvent("debug_change_start_node", { node_id: nodeId });
  startSelectOpen.value = false;
}
function continuePastLimit() {
  live.pushEvent("debug_continue_past_limit", {});
}
</script>

<template>
  <div
    v-if="open && state"
    class="border-t border-border bg-background shrink-0 flex flex-col"
    :style="{ height: `${height}px` }"
  >
    <!-- Resize handle -->
    <div
      class="h-1 cursor-row-resize bg-transparent hover:bg-primary/30 transition-colors shrink-0"
      @pointerdown="onPointerDown"
    />

    <!-- Breadcrumb (sub-flow indicator) -->
    <div
      v-if="hasCallStack"
      class="flex items-center gap-1.5 px-3 py-1 bg-sky-500/10 border-b border-sky-500/20 text-xs text-sky-600 shrink-0"
    >
      <Layers class="size-3 shrink-0" />
      <span
        v-for="(frame, i) in callStack"
        :key="`${frame.flow_id}-${i}`"
        class="flex items-center gap-1"
      >
        <span class="opacity-60">{{ frame.flow_name || $t("flows.debug.flow_label") }}</span>
        <ChevronRight class="size-2.5 opacity-40" />
      </span>
      <span class="font-medium">
        {{ controls.flowName || $t("flows.debug.current_flow") }}
      </span>
    </div>

    <!-- Controls bar -->
    <div class="flex items-center gap-2 px-3 py-1.5 border-b border-border shrink-0">
      <Bug class="size-4 text-muted-foreground" />

      <!-- Play/Pause -->
      <Button
        variant="ghost"
        size="icon-sm"
        class="size-7"
        :title="controls.autoPlaying ? $t('flows.debug.pause') : $t('flows.debug.auto_play')"
        @click="togglePlay"
      >
        <Pause v-if="controls.autoPlaying" class="size-3.5" />
        <FastForward v-else class="size-3.5" />
      </Button>

      <div class="w-px h-5 bg-border mx-0.5" />

      <!-- Step -->
      <Button
        variant="ghost"
        size="icon-sm"
        class="size-7"
        :title="$t('flows.debug.step_key')"
        @click="step"
      >
        <Play class="size-3.5" />
      </Button>

      <!-- Step Back -->
      <Button
        variant="ghost"
        size="icon-sm"
        class="size-7"
        :title="$t('flows.debug.step_back_key')"
        @click="stepBack"
      >
        <Undo2 class="size-3.5" />
      </Button>

      <!-- Reset -->
      <Button
        variant="ghost"
        size="icon-sm"
        class="size-7"
        :title="$t('flows.debug.reset_key')"
        @click="reset"
      >
        <RotateCcw class="size-3.5" />
      </Button>

      <div class="w-px h-5 bg-border mx-0.5" />

      <!-- Stop -->
      <Button
        variant="ghost"
        size="icon-sm"
        class="size-7 text-destructive"
        :title="$t('flows.debug.stop')"
        @click="stop"
      >
        <Square class="size-3.5" />
      </Button>

      <!-- Status + step count + start select -->
      <div class="flex items-center gap-2 ml-1">
        <Badge :variant="statusBadgeVariant(state.status)" class="text-[10px]">
          {{ statusKey(state.status) ? $t(statusKey(state.status)!) : "" }}
        </Badge>
        <span class="text-xs text-muted-foreground tabular-nums">
          {{ $t("flows.debug.step_count", { count: state.step_count }) }}
        </span>

        <!-- Start node select -->
        <div class="flex items-center gap-1">
          <span class="text-xs text-muted-foreground/60">
            {{ $t("flows.debug.start_label") }}
          </span>
          <Popover v-model:open="startSelectOpen">
            <PopoverTrigger as-child>
              <Button
                variant="ghost"
                size="sm"
                class="h-6 px-1.5 font-normal text-xs gap-1"
                :disabled="controls.autoPlaying"
                :title="$t('flows.debug.change_start_node')"
              >
                <span class="truncate max-w-32">
                  {{ currentStartNodeLabel ?? $t("flows.debug.select_start_node") }}
                </span>
                <ChevronDown class="size-3 shrink-0 opacity-50" />
              </Button>
            </PopoverTrigger>
            <PopoverContent class="w-64 p-0" align="start">
              <Command>
                <CommandInput :placeholder="$t('flows.debug.search_nodes')" />
                <CommandList>
                  <CommandEmpty>{{ $t("flows.debug.no_matches") }}</CommandEmpty>
                  <CommandGroup>
                    <CommandItem
                      v-for="option in startNodeOptions"
                      :key="option.id"
                      :value="option.searchText"
                      :class="option.id === state.start_node_id ? 'font-semibold' : ''"
                      @select="changeStartNode(option.id)"
                    >
                      {{ option.label }}
                    </CommandItem>
                  </CommandGroup>
                </CommandList>
              </Command>
            </PopoverContent>
          </Popover>
        </div>
      </div>

      <!-- Speed slider -->
      <div class="flex items-center gap-1.5 ml-auto">
        <Gauge class="size-3 text-muted-foreground/60" />
        <Slider
          :model-value="[controls.speed]"
          :min="200"
          :max="3000"
          :step="100"
          class="w-24"
          :title="$t('flows.debug.speed_per_step', { ms: controls.speed })"
          @update:model-value="setSpeed"
        />
        <span class="text-xs text-muted-foreground tabular-nums w-10">
          {{ formatSpeed(controls.speed) }}
        </span>
      </div>

      <!-- Flow name -->
      <span class="text-xs text-muted-foreground truncate max-w-40">
        {{ controls.flowName }}
      </span>
    </div>

    <!-- Step limit warning -->
    <div
      v-if="controls.stepLimitReached"
      class="flex items-center gap-3 px-3 py-2 bg-amber-500/10 border-b border-amber-500/20 text-xs shrink-0"
    >
      <TriangleAlert class="size-4 text-amber-600 shrink-0" />
      <span class="text-amber-700">
        {{ $t("flows.debug.step_limit", { count: state.max_steps }) }}
      </span>
      <Button size="sm" variant="outline" class="h-6 ml-auto" @click="continuePastLimit">
        {{ $t("flows.debug.step_limit_continue") }}
      </Button>
    </div>

    <!-- Tab content -->
    <Tabs
      :model-value="controls.activeTab"
      class="flex-1 min-h-0 flex flex-col"
      @update:model-value="switchTab"
    >
      <TabsList class="px-3 pt-1 self-start">
        <TabsTrigger value="console" class="text-xs">
          {{ $t("flows.debug.tab_console") }}
        </TabsTrigger>
        <TabsTrigger value="variables" class="text-xs">
          {{ $t("flows.debug.tab_variables") }}
        </TabsTrigger>
        <TabsTrigger value="history" class="text-xs">
          {{ $t("flows.debug.tab_history") }}
        </TabsTrigger>
        <TabsTrigger value="path" class="text-xs">
          {{ $t("flows.debug.tab_path") }}
        </TabsTrigger>
      </TabsList>

      <!-- Console -->
      <TabsContent value="console" class="flex-1 min-h-0 overflow-y-auto">
        <div class="font-mono text-xs">
          <div
            v-for="(entry, i) in consoleEntries"
            :key="i"
            class="flex items-start gap-2 px-3 py-0.5 hover:bg-muted/60"
            :class="levelBg(entry.level)"
          >
            <span
              class="text-muted-foreground/50 shrink-0 w-14 text-right tabular-nums select-none"
            >
              {{ formatDebugTs(entry.ts) }}
            </span>
            <span class="shrink-0 mt-0.5" :class="levelColor(entry.level)">
              <component :is="levelIcon(entry.level)" class="size-3" />
            </span>
            <span
              v-if="entry.node_label"
              class="shrink-0 max-w-28 truncate text-primary/70"
              :title="entry.node_label"
            >
              {{ entry.node_label }}
            </span>
            <span class="flex-1 break-all">
              {{ entry.message }}
              <div v-if="entry.rule_details && entry.rule_details.length > 0" class="mt-0.5">
                <div
                  v-for="(rule, ri) in entry.rule_details"
                  :key="ri"
                  class="text-[10px] text-muted-foreground/60"
                >
                  {{ rule.variable_ref }} {{ rule.operator }}
                  {{ formatDebugValue(rule.expected_value) }}
                  → {{ rule.passed ? "pass" : "fail" }} (actual:
                  {{ formatDebugValue(rule.actual_value) }})
                </div>
              </div>
            </span>
          </div>

          <!-- Response choices (dialogue) -->
          <div
            v-if="pendingChoices.length > 0"
            class="px-3 py-2 border-t border-border bg-muted/30"
          >
            <p class="text-xs text-muted-foreground mb-1.5">
              {{ $t("flows.debug.choose_response") }}
            </p>
            <div class="flex flex-wrap gap-1.5">
              <button
                v-for="choice in pendingChoices"
                :key="choice.id"
                type="button"
                class="text-xs px-2 py-1 rounded border transition-colors"
                :class="
                  choice.valid
                    ? 'border-primary text-primary hover:bg-primary/10'
                    : 'border-border text-muted-foreground opacity-40 line-through cursor-not-allowed'
                "
                :disabled="!choice.valid"
                :title="!choice.valid ? $t('flows.debug.condition_not_met') : undefined"
                @click="selectChoice(choice.id)"
              >
                {{ cleanResponseText(choice.text) ?? $t("flows.debug.empty_response") }}
              </button>
            </div>
          </div>

          <!-- Empty state -->
          <div
            v-if="consoleEntries.length === 0 && pendingChoices.length === 0"
            class="text-xs text-muted-foreground py-4 text-center"
          >
            {{ $t("flows.debug.waiting") }}
          </div>
        </div>
      </TabsContent>

      <!-- Variables -->
      <TabsContent value="variables" class="flex-1 min-h-0 overflow-y-auto text-xs">
        <!-- Filter bar -->
        <div
          class="flex items-center gap-2 px-3 py-1.5 border-b border-border bg-background shrink-0 sticky top-0 z-10"
        >
          <div class="relative flex-1 max-w-48">
            <Search
              class="size-3 absolute left-2 top-1/2 -translate-y-1/2 text-muted-foreground/50 pointer-events-none"
            />
            <input
              :value="varFilter"
              type="text"
              :placeholder="$t('flows.debug.filter_variables')"
              class="w-full h-7 pl-7 pr-2 text-xs rounded border border-border bg-background focus:outline-none focus:ring-1 focus:ring-primary"
              @input="onVarFilterInput"
            />
          </div>
          <Button
            size="sm"
            :variant="controls.varChangedOnly ? 'default' : 'ghost'"
            class="h-7 gap-1"
            :title="$t('flows.debug.var_changed_hint')"
            @click="toggleChangedOnly"
          >
            <Diff class="size-3" />
            {{ $t("flows.debug.var_changed_toggle") }}
          </Button>
          <span class="text-xs text-muted-foreground tabular-nums ml-auto">
            {{
              $t("flows.debug.var_count", {
                shown: filteredVariables.length,
                total: totalVariables,
              })
            }}
          </span>
        </div>

        <!-- Variables table -->
        <table v-if="filteredVariables.length > 0" class="w-full table-fixed border-collapse">
          <colgroup>
            <col :style="{ width: `${colWidths.variable}px` }" />
            <col :style="{ width: `${colWidths.type}px` }" />
            <col :style="{ width: `${colWidths.initial}px` }" />
            <col :style="{ width: `${colWidths.previous}px` }" />
            <col :style="{ width: `${colWidths.current}px` }" />
          </colgroup>
          <thead class="sticky top-[34px] bg-background z-10 text-muted-foreground/70">
            <tr class="border-b border-border">
              <th
                v-for="col in ['variable', 'type', 'initial', 'previous', 'current']"
                :key="col"
                class="font-medium text-left relative pr-3 py-1 px-2 overflow-hidden"
                :class="col === 'variable' ? 'text-left' : ''"
              >
                {{ $t(`flows.debug.col_${col}`) }}
                <span
                  v-if="col !== 'current'"
                  class="absolute right-0 top-0 w-3 h-full cursor-col-resize group"
                  @pointerdown="startColResize(col, $event)"
                >
                  <span
                    class="absolute inset-y-0 right-0 w-px bg-border group-hover:w-[3px] group-hover:bg-primary/50 transition-all"
                  />
                </span>
              </th>
            </tr>
          </thead>
          <tbody class="font-mono">
            <tr
              v-for="[key, var_] in filteredVariables"
              :key="key"
              class="hover:bg-muted/40 border-b border-border/40"
            >
              <td class="truncate overflow-hidden py-1 px-2" :title="key">
                <span class="text-muted-foreground/60">{{ var_.sheet_shortcut }}.</span
                >{{ var_.variable_name }}
              </td>
              <td class="overflow-hidden py-1 px-2">
                <Badge variant="secondary" class="text-[10px] font-sans px-1.5 py-0">
                  {{ typeLabel(key, var_.block_type) }}
                </Badge>
              </td>
              <td
                class="text-left text-muted-foreground/70 tabular-nums truncate overflow-hidden py-1 px-2"
              >
                {{ formatDebugValue(var_.initial_value) }}
              </td>
              <td
                class="text-left text-muted-foreground/70 tabular-nums truncate overflow-hidden py-1 px-2"
              >
                {{ formatDebugValue(var_.previous_value) }}
              </td>
              <td
                class="text-left tabular-nums py-1 px-2 overflow-hidden"
                :class="var_.changed ? sourceColor(var_.source) : 'text-muted-foreground/70'"
              >
                <!-- Inline edit: boolean (shared BooleanToggle from components/) -->
                <BooleanToggle
                  v-if="var_.block_type === 'boolean'"
                  :value="var_.value as boolean | null"
                  :mode="isTriStateBoolean(var_) ? 'tri_state' : 'two_state'"
                  :true-label="$t('flows.debug.bool_true')"
                  :false-label="$t('flows.debug.bool_false')"
                  :neutral-label="$t('flows.debug.bool_nil')"
                  @update:value="(v) => onBooleanChange(key, v)"
                />
                <!-- Inline edit: number -->
                <input
                  v-else-if="editingVar === key && var_.block_type === 'number'"
                  type="number"
                  step="any"
                  :value="var_.value"
                  autofocus
                  class="w-full h-5 px-1 text-xs bg-background border border-primary rounded tabular-nums text-sky-500 focus:outline-none"
                  @blur="onEditBlur(key, $event)"
                  @keydown.enter="onEditEnter(key, $event)"
                  @keydown.escape="cancelEdit"
                />
                <!-- Inline edit: date -->
                <input
                  v-else-if="editingVar === key && var_.block_type === 'date'"
                  type="date"
                  :value="var_.value ?? ''"
                  autofocus
                  class="w-full h-5 px-1 text-xs bg-background border border-primary rounded text-sky-500 focus:outline-none"
                  @blur="onEditBlur(key, $event)"
                  @keydown.enter="onEditEnter(key, $event)"
                  @keydown.escape="cancelEdit"
                />
                <!-- Inline edit: select (Popover + Command) -->
                <Popover
                  v-else-if="editingVar === key && var_.block_type === 'select'"
                  :open="true"
                  @update:open="(open) => !open && cancelEdit()"
                >
                  <PopoverTrigger as-child>
                    <button
                      type="button"
                      class="w-full text-left text-xs px-1 min-h-5 border border-primary rounded bg-background"
                    >
                      {{ displayValue(var_) || $t("flows.debug.select_option") }}
                    </button>
                  </PopoverTrigger>
                  <PopoverContent class="w-56 p-0" align="start">
                    <Command>
                      <CommandInput :placeholder="$t('flows.debug.search_options')" />
                      <CommandList>
                        <CommandEmpty>{{ $t("flows.debug.no_options") }}</CommandEmpty>
                        <CommandGroup>
                          <CommandItem
                            v-for="opt in var_.options || []"
                            :key="opt.key"
                            :value="opt.value"
                            :class="opt.key === var_.value ? 'font-semibold' : ''"
                            @select="submitEdit(key, opt.key)"
                          >
                            {{ opt.value }}
                          </CommandItem>
                        </CommandGroup>
                      </CommandList>
                    </Command>
                  </PopoverContent>
                </Popover>
                <!-- Inline edit: multi_select (Popover + Command with checkboxes) -->
                <Popover
                  v-else-if="editingVar === key && var_.block_type === 'multi_select'"
                  :open="true"
                  @update:open="(open) => !open && cancelEdit()"
                >
                  <PopoverTrigger as-child>
                    <button
                      type="button"
                      class="w-full text-left text-xs px-1 min-h-5 border border-primary rounded bg-background truncate"
                    >
                      {{ displayValue(var_) || $t("flows.debug.select_options") }}
                    </button>
                  </PopoverTrigger>
                  <PopoverContent class="w-56 p-0" align="start">
                    <Command>
                      <CommandInput :placeholder="$t('flows.debug.search_options')" />
                      <CommandList>
                        <CommandEmpty>{{ $t("flows.debug.no_options") }}</CommandEmpty>
                        <CommandGroup>
                          <CommandItem
                            v-for="opt in var_.options || []"
                            :key="opt.key"
                            :value="opt.value"
                            @select="toggleMultiOption(var_, key, opt.key)"
                          >
                            <Checkbox
                              :model-value="selectedMultiKeys(var_).includes(opt.key)"
                              class="mr-2 pointer-events-none"
                            />
                            {{ opt.value }}
                          </CommandItem>
                        </CommandGroup>
                      </CommandList>
                    </Command>
                  </PopoverContent>
                </Popover>
                <!-- Inline edit: text (fallback) -->
                <input
                  v-else-if="editingVar === key"
                  type="text"
                  :value="var_.value"
                  autofocus
                  class="w-full h-5 px-1 text-xs bg-background border border-primary rounded text-sky-500 focus:outline-none"
                  @blur="onEditBlur(key, $event)"
                  @keydown.enter="onEditEnter(key, $event)"
                  @keydown.escape="cancelEdit"
                />
                <!-- Display -->
                <div
                  v-else
                  class="rounded px-1 -mx-1 truncate block w-full min-h-5"
                  :class="
                    isReadOnlyVariable(var_)
                      ? 'cursor-default text-muted-foreground/70'
                      : 'cursor-pointer hover:bg-muted'
                  "
                  :title="isReadOnlyVariable(var_) ? undefined : $t('flows.debug.click_to_edit')"
                  @click="startEdit(var_, key)"
                >
                  <span v-if="var_.changed" :class="sourceColor(var_.source)">◆ </span>
                  <span :class="var_.changed ? 'font-semibold' : ''">
                    {{ displayValue(var_) }}
                  </span>
                </div>
              </td>
            </tr>
          </tbody>
        </table>

        <!-- Empty states -->
        <div
          v-if="filteredVariables.length === 0 && totalVariables === 0"
          class="flex items-center justify-center h-24 text-muted-foreground/50"
        >
          {{ $t("flows.debug.no_variables") }}
        </div>
        <div
          v-else-if="filteredVariables.length === 0"
          class="flex items-center justify-center h-24 text-muted-foreground/50"
        >
          {{ $t("flows.debug.no_matching_vars") }}
        </div>
      </TabsContent>

      <!-- History -->
      <TabsContent value="history" class="flex-1 min-h-0 overflow-y-auto text-xs">
        <table v-if="historyEntries.length > 0" class="w-full border-collapse">
          <thead class="sticky top-0 bg-background text-muted-foreground/70 border-b border-border">
            <tr>
              <th class="font-medium text-left py-1 px-3 w-16">
                {{ $t("flows.debug.col_time") }}
              </th>
              <th class="font-medium text-left py-1 px-2">
                {{ $t("flows.debug.col_node") }}
              </th>
              <th class="font-medium text-left py-1 px-2">
                {{ $t("flows.debug.col_change") }}
              </th>
              <th class="font-medium text-left py-1 px-2 w-20">
                {{ $t("flows.debug.col_source") }}
              </th>
            </tr>
          </thead>
          <tbody class="font-mono">
            <tr
              v-for="(entry, i) in historyEntries"
              :key="i"
              class="hover:bg-muted/40 border-b border-border/40"
            >
              <td class="text-muted-foreground/60 tabular-nums py-1 px-3">
                {{ formatDebugTs(entry.ts) }}
              </td>
              <td class="truncate max-w-32 py-1 px-2" :title="entry.node_label">
                {{ entry.node_label || $t("flows.debug.user_override_label") }}
              </td>
              <td class="truncate max-w-64 py-1 px-2">
                <span class="text-muted-foreground/70">{{ entry.variable_ref }}:</span>
                <span class="ml-1">{{ formatDebugValue(entry.old_value) }}</span>
                <span class="mx-1 text-muted-foreground/50">→</span>
                <span class="font-semibold">{{ formatDebugValue(entry.new_value) }}</span>
              </td>
              <td class="py-1 px-2">
                <span
                  v-if="historySourceLabelKey(entry.source)"
                  class="inline-block text-[10px] px-1.5 py-0.5 rounded border font-sans"
                  :class="historySourceBadgeClass(entry.source)"
                >
                  {{ $t(historySourceLabelKey(entry.source)!) }}
                </span>
              </td>
            </tr>
          </tbody>
        </table>
        <div v-else class="flex items-center justify-center h-24 text-muted-foreground/50">
          {{ $t("flows.debug.no_history") }}
        </div>
      </TabsContent>

      <!-- Path -->
      <TabsContent value="path" class="flex-1 min-h-0 overflow-y-auto text-xs">
        <div
          v-if="pathEntries.length === 0"
          class="flex items-center justify-center h-24 text-muted-foreground/50"
        >
          {{ $t("flows.debug.no_path") }}
        </div>
        <template v-for="(entry, i) in pathEntries" :key="i">
          <!-- Sub-flow separator -->
          <div
            v-if="entry.separator"
            class="flex items-center gap-2 px-3 py-0.5 text-sky-500/60 select-none"
          >
            <div class="flex-1 border-t border-sky-500/20" />
            <component
              :is="entry.direction === 'enter' ? ArrowDownRight : ArrowUpLeft"
              class="size-3"
            />
            <span class="text-[10px]">
              {{
                entry.direction === "enter"
                  ? $t("flows.debug.entering_subflow")
                  : $t("flows.debug.returned_to_parent")
              }}
            </span>
            <div class="flex-1 border-t border-sky-500/20" />
          </div>

          <!-- Path entry -->
          <div
            v-else
            class="flex items-center gap-2 py-1 pr-3"
            :class="entry.is_current ? 'text-primary font-bold bg-primary/5' : 'hover:bg-muted/40'"
            :style="{ paddingLeft: `${12 + entry.depth * 16}px` }"
          >
            <button
              type="button"
              class="shrink-0 flex items-center justify-center w-3 h-3 group"
              :title="
                breakpointSet.has(entry.node_id)
                  ? $t('flows.debug.remove_breakpoint')
                  : $t('flows.debug.set_breakpoint')
              "
              @click="toggleBreakpoint(entry.node_id)"
            >
              <span
                class="block rounded-full"
                :class="
                  breakpointSet.has(entry.node_id)
                    ? 'w-2.5 h-2.5 bg-destructive'
                    : 'w-2 h-2 border border-border group-hover:border-destructive/50'
                "
              />
            </button>
            <span class="text-muted-foreground/50 w-5 text-right tabular-nums shrink-0 select-none">
              {{ entry.step }}
            </span>
            <component :is="pathIcon(entry.type)" class="size-3 shrink-0 opacity-60" />
            <span v-if="entry.label" class="truncate max-w-32">
              {{ entry.label }}
            </span>
            <span class="text-muted-foreground/50 shrink-0">→</span>
            <span class="truncate flex-1 text-muted-foreground/70 font-normal">
              {{ entry.outcome || "" }}
            </span>
          </div>
        </template>
      </TabsContent>
    </Tabs>
  </div>
</template>
