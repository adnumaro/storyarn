<script setup>
import { GitBranch, Zap } from "lucide-vue-next";
import { ref } from "vue";
import {
	Popover,
	PopoverContent,
	PopoverTrigger,
} from "@/vue/components/ui/popover/index.js";

const emit = defineEmits(["add-node"]);

const open = ref(false);

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

function addNode(type) {
	emit("add-node", type);
	open.value = false;
}

defineExpose({ close: () => { open.value = false; } });
</script>

<template>
  <div class="v2-dock-item group relative">
    <Popover v-model:open="open">
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
    <div v-if="!open" class="v2-dock-tooltip">
      <div class="text-sm font-semibold mb-0.5">Logic</div>
      <div class="text-xs text-muted-foreground leading-relaxed">
        Conditions and instructions
      </div>
    </div>
  </div>
</template>
