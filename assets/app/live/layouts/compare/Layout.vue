<script setup lang="ts">
import { computed, useSlots } from "vue";
import { PanelLeft, PanelLeftClose } from "lucide-vue-next";
import { useLive } from "@shared/composables/useLive";

const {
  panelTitle = null,
  panelOpen = true,
  contentClass = "h-full overflow-hidden",
} = defineProps<{
  panelTitle?: string | null;
  panelOpen?: boolean;
  contentClass?: string;
}>();

const live = useLive();
const slots = useSlots();
const hasPanel = computed(() => Boolean(slots.panel));

function togglePanel() {
  live.pushEvent("main_sidebar_toggle", {});
}
</script>

<template>
  <div class="h-screen w-screen overflow-hidden relative bg-background">
    <button
      v-if="hasPanel && !panelOpen"
      type="button"
      class="fixed top-3 left-3 z-[1020] surface-panel p-1"
      :title="$t('layout.main_sidebar.show_panel')"
      @click="togglePanel"
    >
      <span
        class="inline-flex items-center justify-center size-8 rounded-md hover:bg-accent transition-colors"
      >
        <PanelLeft class="size-4" />
      </span>
    </button>

    <aside
      v-if="hasPanel"
      id="compare-panel"
      :class="[
        'fixed left-3 top-3 bottom-3 z-[1010] w-52 flex flex-col surface-panel overflow-hidden',
        'transition-all duration-200',
        panelOpen
          ? 'translate-x-0 opacity-100'
          : '-translate-x-[calc(100%+0.75rem)] opacity-0 pointer-events-none',
      ]"
    >
      <div class="flex items-center justify-between px-2.5 py-2 border-b border-border">
        <span
          v-if="panelTitle"
          class="text-xs font-medium text-muted-foreground flex items-center gap-1.5"
        >
          {{ panelTitle }}
        </span>
        <button
          type="button"
          class="inline-flex items-center justify-center size-7 rounded-md hover:bg-accent text-muted-foreground hover:text-foreground transition-colors"
          :title="$t('layout.main_sidebar.close')"
          @click="togglePanel"
        >
          <PanelLeftClose class="size-3.5" />
        </button>
      </div>

      <div class="flex-1 overflow-y-auto p-2">
        <slot name="panel" />
      </div>
    </aside>

    <main id="main-content" :class="contentClass">
      <slot />
    </main>
  </div>
</template>
