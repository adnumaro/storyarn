<script setup lang="ts">
import { Layers, MessageSquare } from "lucide-vue-next";
import type { Component } from "vue";
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";

interface DockNodeEntry {
  type: string;
  icon: Component;
  title: string;
  description: string;
}

const emit = defineEmits<{
  "add-node": [type: string];
}>();

const { t } = useI18n();
const open = ref(false);

const narrativeNodes = computed<DockNodeEntry[]>(() => [
  {
    type: "dialogue",
    icon: MessageSquare,
    title: t("flows.node_types.dialogue"),
    description: t("flows.dock.dialogue_desc"),
  },
  {
    type: "sequence",
    icon: Layers,
    title: t("flows.node_types.sequence"),
    description: t("flows.dock.sequence_desc"),
  },
]);

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
  <div class="dock-item group relative">
    <Popover v-model:open="open">
      <PopoverTrigger as-child>
        <button type="button" class="dock-btn">
          <MessageSquare class="size-5" />
        </button>
      </PopoverTrigger>
      <PopoverContent side="top" :side-offset="12" class="w-56 p-3">
        <div class="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-2 px-1">
          {{ $t("flows.dock.narrative") }}
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
    <div v-if="!open" class="dock-tooltip">
      <div class="text-sm font-semibold mb-0.5">{{ $t("flows.dock.narrative") }}</div>
      <div class="text-xs text-muted-foreground leading-relaxed">
        {{ $t("flows.dock.dialogue_desc") }}
      </div>
    </div>
  </div>
</template>
