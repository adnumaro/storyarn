<script setup lang="ts">
import { ArrowRightToLine, Box, LogIn, LogOut } from "lucide-vue-next";
import type { Component } from "vue";
import { ref } from "vue";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover/index.ts";

interface DockNodeEntry {
  type: string;
  icon: Component;
  title: string;
  description: string;
}

const emit = defineEmits<{
  "add-node": [type: string];
}>();

const open = ref(false);

const navigationNodes: DockNodeEntry[] = [
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

function addNode(type: string): void {
  emit("add-node", type);
  open.value = false;
}

defineExpose({
  close: () => {
    open.value = false;
  },
});
</script>

<template>
  <div class="v2-dock-item group relative">
    <Popover v-model:open="open">
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
    <div v-if="!open" class="v2-dock-tooltip">
      <div class="text-sm font-semibold mb-0.5">Navigation</div>
      <div class="text-xs text-muted-foreground leading-relaxed">Flow control and routing</div>
    </div>
  </div>
</template>
