<script setup lang="ts">
import { ChevronDown, ChevronUp, Eye, EyeOff, GitBranch, X } from "lucide-vue-next";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@components/ui/select";
import { useLive } from "@composables/useLive";

interface AmbientFlow {
  id: number | string;
  flowName: string;
  enabled: boolean;
  triggerType: string;
  triggerConfig?: { interval_ms?: number; variable_ref?: string };
  priority: number;
}

const { flow, canEdit = false } = defineProps<{
  flow: AmbientFlow;
  canEdit?: boolean;
}>();

const live = useLive();

const triggerTypes = [
  { value: "on_enter", label: "On Enter" },
  { value: "timed", label: "Timed" },
  { value: "on_event", label: "On Event" },
  { value: "one_shot", label: "One Shot" },
];

function reorder(direction: string) {
  live.pushEvent("reorder_ambient_flow", {
    id: flow.id,
    direction,
  });
}

function toggle() {
  live.pushEvent("toggle_ambient_flow", { id: flow.id });
}

function remove() {
  live.pushEvent("remove_ambient_flow", { id: flow.id });
}

function onTriggerTypeChange(value: string) {
  live.pushEvent(`select_ambient_trigger_type:${flow.id}`, {
    selected: value,
  });
}

function onVariableRefBlur(e: FocusEvent) {
  live.pushEvent(`select_ambient_variable_ref:${flow.id}`, {
    selected: (e.target as HTMLInputElement).value,
  });
}

function onIntervalBlur(e: FocusEvent) {
  live.pushEvent("update_ambient_flow_trigger", {
    id: flow.id,
    trigger_type: flow.triggerType,
    interval_ms: (e.target as HTMLInputElement).value,
  });
}

function onPriorityBlur(e: FocusEvent) {
  live.pushEvent("update_ambient_flow_priority", {
    id: flow.id,
    priority: (e.target as HTMLInputElement).value,
  });
}

function triggerLabel(type: string): string {
  const found = triggerTypes.find((t) => t.value === type);
  return found ? found.label : type;
}
</script>

<template>
  <div class="space-y-1">
    <!-- Main row: name + actions -->
    <div class="flex items-center gap-1.5 group">
      <span class="text-xs truncate flex-1" :title="flow.flowName">
        <GitBranch class="size-3 inline-block mr-0.5 opacity-50" />
        {{ flow.flowName }}
      </span>
      <div v-if="canEdit" class="flex items-center gap-0.5 shrink-0">
        <button
          type="button"
          class="size-6 inline-flex items-center justify-center rounded hover:bg-accent text-muted-foreground opacity-0 group-hover:opacity-100 transition-opacity"
          title="Move up"
          @click="reorder('up')"
        >
          <ChevronUp class="size-3" />
        </button>
        <button
          type="button"
          class="size-6 inline-flex items-center justify-center rounded hover:bg-accent text-muted-foreground opacity-0 group-hover:opacity-100 transition-opacity"
          title="Move down"
          @click="reorder('down')"
        >
          <ChevronDown class="size-3" />
        </button>
        <button
          type="button"
          class="size-6 inline-flex items-center justify-center rounded transition-colors"
          :title="flow.enabled ? 'Disable' : 'Enable'"
          @click="toggle"
        >
          <Eye v-if="flow.enabled" class="size-3.5 text-green-500" />
          <EyeOff v-else class="size-3.5 text-muted-foreground/30" />
        </button>
        <button
          type="button"
          class="size-6 inline-flex items-center justify-center rounded text-destructive hover:bg-destructive/10 opacity-0 group-hover:opacity-100 transition-opacity"
          @click="remove"
        >
          <X class="size-3" />
        </button>
      </div>
    </div>

    <!-- Trigger config row (editable) -->
    <div v-if="canEdit" class="flex items-center gap-1 pl-4">
      <div class="flex-1 min-w-0">
        <Select :model-value="flow.triggerType" @update:model-value="onTriggerTypeChange">
          <SelectTrigger class="h-7 text-xs">
            <SelectValue placeholder="Trigger..." />
          </SelectTrigger>
          <SelectContent>
            <SelectItem v-for="t in triggerTypes" :key="t.value" :value="t.value" class="text-xs">
              {{ t.label }}
            </SelectItem>
          </SelectContent>
        </Select>
      </div>
      <input
        v-if="flow.triggerType === 'timed'"
        type="number"
        :value="flow.triggerConfig?.interval_ms ?? 30000"
        min="1000"
        step="1000"
        title="Interval (ms)"
        class="w-16 h-7 px-1.5 text-xs rounded-md border border-input bg-background"
        @blur="onIntervalBlur"
      />
      <div v-if="flow.triggerType === 'on_event'" class="flex-1 min-w-0">
        <input
          type="text"
          :value="flow.triggerConfig?.variable_ref ?? ''"
          placeholder="Select variable..."
          title="Variable reference"
          class="w-full h-7 px-2 text-xs rounded-md border border-input bg-background"
          @blur="onVariableRefBlur"
        />
      </div>
      <input
        type="number"
        :value="flow.priority"
        min="0"
        title="Priority (higher = first)"
        placeholder="0"
        class="w-12 h-7 px-1.5 text-xs rounded-md border border-input bg-background"
        @blur="onPriorityBlur"
      />
    </div>

    <!-- Read-only trigger info -->
    <div v-if="!canEdit" class="pl-4">
      <span
        class="inline-flex items-center h-5 px-1.5 text-[10px] rounded bg-muted text-muted-foreground"
      >
        {{ triggerLabel(flow.triggerType) }}
      </span>
      <span v-if="flow.priority > 0" class="text-[10px] text-muted-foreground/60 ml-1">
        P{{ flow.priority }}
      </span>
    </div>
  </div>
</template>
