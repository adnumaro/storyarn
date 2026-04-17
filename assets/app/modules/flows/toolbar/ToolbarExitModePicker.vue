<script setup lang="ts">
import { ArrowRight, ArrowRightToLine, ChevronDown, Undo2 } from "lucide-vue-next";
import type { Component } from "vue";
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover/index.ts";

interface ExitMode {
  value: string;
  icon: Component;
  label: string;
  description: string;
}

const { t } = useI18n();

const EXIT_MODES = computed<ExitMode[]>(() => [
  {
    value: "terminal",
    icon: ArrowRightToLine,
    label: t("flows.exit_modes.terminal"),
    description: t("flows.exit_modes.terminal_desc"),
  },
  {
    value: "flow_reference",
    icon: ArrowRight,
    label: t("flows.exit_modes.flow_reference"),
    description: t("flows.exit_modes.flow_reference_desc"),
  },
  {
    value: "caller_return",
    icon: Undo2,
    label: t("flows.exit_modes.caller_return"),
    description: t("flows.exit_modes.caller_return_desc"),
  },
]);

const { mode = "terminal", disabled = false } = defineProps<{
  mode?: string;
  disabled?: boolean;
}>();

const emit = defineEmits<{
  "update:mode": [value: string];
}>();
const open = ref(false);

const current = computed(
  () => EXIT_MODES.value.find((m) => m.value === mode) || EXIT_MODES.value[0],
);

function selectMode(value: string) {
  emit("update:mode", value);
  open.value = false;
}
</script>

<template>
  <Popover v-model:open="open">
    <PopoverTrigger as-child>
      <button type="button" class="toolbar-btn gap-1 px-1.5" :disabled="disabled">
        <component :is="current.icon" class="size-3.5" />
        <span class="text-xs">{{ current.label }}</span>
        <ChevronDown class="size-3 opacity-50" />
      </button>
    </PopoverTrigger>
    <PopoverContent class="w-56 p-1" :side-offset="8" side="top">
      <button
        v-for="m in EXIT_MODES"
        :key="m.value"
        type="button"
        class="flex items-center gap-2.5 w-full px-2.5 py-2 rounded-md text-left hover:bg-accent transition-colors"
        :class="{ 'bg-accent font-medium': mode === m.value }"
        @click="selectMode(m.value)"
      >
        <component :is="m.icon" class="size-5 shrink-0" />
        <div>
          <div class="text-sm leading-tight">{{ m.label }}</div>
          <div class="text-xs text-muted-foreground leading-tight">{{ m.description }}</div>
        </div>
      </button>
    </PopoverContent>
  </Popover>
</template>
