<script setup lang="ts">
import { ref, watch } from "vue";
import { Cable, Unplug, ArrowUp, ArrowRight, ArrowDown, ArrowLeft } from "@lucide/vue";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";
import ToolbarTooltip from "@components/toolbar/ToolbarTooltip.vue";
import { useBoardText } from "../composables/useBoardText";
import type { ConnectionDirection } from "../lib/connectionGeometry";

const { selection, hasConnections, canCreate, busy } = defineProps<{
  selection: Array<{ id: number; label: string }>;
  hasConnections: boolean;
  canCreate: boolean;
  busy: boolean;
}>();
const emit = defineEmits<{
  connect: [];
  disconnect: [];
  create: [direction: ConnectionDirection];
}>();
const { t } = useBoardText();
const open = ref(false);
const trigger = ref<HTMLButtonElement>();
const restoreFocus = ref(true);
watch(open, (value) => {
  if (value) restoreFocus.value = true;
});
watch(
  () => busy,
  (value) => {
    if (value) open.value = false;
  },
);
const directions = [
  { id: "up", icon: ArrowUp, key: "↑" },
  { id: "right", icon: ArrowRight, key: "→" },
  { id: "down", icon: ArrowDown, key: "↓" },
  { id: "left", icon: ArrowLeft, key: "←" },
] as const;
function create(direction: ConnectionDirection) {
  restoreFocus.value = false;
  open.value = false;
  emit("create", direction);
}
function connect(connected: boolean) {
  restoreFocus.value = false;
  open.value = false;
  if (connected) emit("connect");
  else emit("disconnect");
}
</script>

<template>
  <Popover v-if="selection.length >= 2 || (selection.length && canCreate)" v-model:open="open">
    <ToolbarTooltip :label="t('ideation.canvas.connectionHelp')">
      <PopoverTrigger as-child>
        <button
          id="brainstorming-connection-tools"
          ref="trigger"
          type="button"
          class="toolbar-btn gap-1.5 disabled:opacity-45"
          :aria-label="t('ideation.canvas.connections')"
          :disabled="busy"
        >
          <Cable class="size-4" />
        </button>
      </PopoverTrigger>
    </ToolbarTooltip>
    <PopoverContent
      :reference="trigger"
      :aria-label="t('ideation.canvas.connections')"
      class="w-72 p-2"
      @close-auto-focus="!restoreFocus && $event.preventDefault()"
    >
      <template v-if="selection.length >= 2">
        <button
          id="connect-selected-ideas"
          type="button"
          class="mt-1 flex w-full items-center gap-2 rounded-md px-2 py-2 text-left text-sm hover:bg-accent"
          @click="connect(true)"
        >
          <Cable class="size-4 shrink-0" /><span class="flex-1">{{
            t("ideation.canvas.connectSelected")
          }}</span
          ><kbd class="text-xs text-muted-foreground">L</kbd>
        </button>
        <button
          id="disconnect-selected-ideas"
          type="button"
          class="flex w-full items-center gap-2 rounded-md px-2 py-2 text-left text-sm hover:bg-accent disabled:opacity-45"
          :disabled="!hasConnections"
          @click="connect(false)"
        >
          <Unplug class="size-4 shrink-0" /><span class="flex-1">{{
            t("ideation.canvas.disconnectSelected")
          }}</span
          ><kbd class="text-xs text-muted-foreground">Shift L</kbd>
        </button>
      </template>
      <template v-if="canCreate">
        <div v-if="selection.length >= 2" class="my-2 border-t border-border" />
        <p class="px-2 py-1 text-xs text-muted-foreground">
          {{ t("ideation.canvas.addConnectedHelp", { count: selection.length }) }}
        </p>
        <button
          v-for="direction in directions"
          :id="`add-connected-idea-${direction.id}`"
          :key="direction.id"
          type="button"
          class="flex w-full items-center gap-2 rounded-md px-2 py-2 text-left text-sm hover:bg-accent"
          @click="create(direction.id)"
        >
          <component :is="direction.icon" class="size-4 shrink-0" /><span class="flex-1">{{
            t(`ideation.canvas.addConnected.${direction.id}`)
          }}</span
          ><kbd class="text-xs text-muted-foreground">Alt Shift {{ direction.key }}</kbd>
        </button>
      </template>
    </PopoverContent>
  </Popover>
</template>
