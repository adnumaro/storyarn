<script setup>
import { ArrowRight, ArrowRightToLine, ChevronDown, Undo2 } from "lucide-vue-next";
import { computed, ref } from "vue";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover/index.ts";

const EXIT_MODES = [
  {
    value: "terminal",
    icon: ArrowRightToLine,
    label: "Terminal",
    description: "End of flow — no continuation",
  },
  {
    value: "flow_reference",
    icon: ArrowRight,
    label: "Flow Reference",
    description: "Continue to another flow",
  },
  {
    value: "caller_return",
    icon: Undo2,
    label: "Caller Return",
    description: "Return to the calling flow",
  },
];

const { mode, disabled } = defineProps({
  mode: { type: String, default: "terminal" },
  disabled: { type: Boolean, default: false },
});

const emit = defineEmits(["update:mode"]);
const open = ref(false);

const current = computed(() => EXIT_MODES.find((m) => m.value === mode) || EXIT_MODES[0]);

function selectMode(value) {
  emit("update:mode", value);
  open.value = false;
}
</script>

<template>
  <Popover v-model:open="open">
    <PopoverTrigger as-child>
      <button type="button" class="v2-toolbar-btn gap-1 px-1.5" :disabled="disabled">
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
