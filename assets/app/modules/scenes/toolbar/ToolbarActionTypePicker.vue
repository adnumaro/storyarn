<script setup lang="ts">
import { BarChart3, Compass, Footprints, PackageOpen, Zap } from "lucide-vue-next";
import type { Component } from "vue";
import { ref } from "vue";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";

interface ActionTypeOption {
  value: string;
  label: string;
  icon: Component;
  desc: string;
}

const ACTION_TYPES: ActionTypeOption[] = [
  {
    value: "none",
    label: "Navigation",
    icon: Compass,
    desc: "Clicking navigates or opens a link",
  },
  {
    value: "walkable",
    label: "Walkable Area",
    icon: Footprints,
    desc: "Defines traversable ground",
  },
  {
    value: "instruction",
    label: "Action",
    icon: Zap,
    desc: "Sets variables when triggered",
  },
  {
    value: "display",
    label: "Display",
    icon: BarChart3,
    desc: "Shows a variable value on the map",
  },
  {
    value: "collection",
    label: "Collection",
    icon: PackageOpen,
    desc: "Opens a collection modal with items",
  },
];

const { actionType = "none", disabled = false } = defineProps<{
  actionType?: string;
  disabled?: boolean;
}>();

const emit = defineEmits<{
  "update:actionType": [value: string];
}>();
const open = ref(false);

function select(value: string) {
  emit("update:actionType", value);
  open.value = false;
}

const current = (): ActionTypeOption =>
  ACTION_TYPES.find((t) => t.value === actionType) || ACTION_TYPES[0];
</script>

<template>
  <Popover v-model:open="open">
    <PopoverTrigger as-child>
      <button type="button" class="toolbar-btn gap-1" :disabled="disabled" title="Action type">
        <component :is="current().icon" class="size-3.5" />
      </button>
    </PopoverTrigger>
    <PopoverContent class="w-56 p-1" :side-offset="8" side="top">
      <button
        v-for="opt in ACTION_TYPES"
        :key="opt.value"
        type="button"
        class="flex items-start gap-2 w-full px-2 py-1.5 rounded text-left cursor-pointer transition-colors"
        :class="opt.value === actionType ? 'bg-accent' : 'hover:bg-accent/50'"
        @click="select(opt.value)"
      >
        <component :is="opt.icon" class="size-3.5 mt-0.5 shrink-0" />
        <div>
          <div class="text-xs font-medium">{{ opt.label }}</div>
          <div class="text-[10px] text-muted-foreground">{{ opt.desc }}</div>
        </div>
      </button>
    </PopoverContent>
  </Popover>
</template>
