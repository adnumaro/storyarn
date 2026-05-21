<script setup lang="ts">
import { LayoutDashboard } from "lucide-vue-next";
import { onMounted, onUnmounted, ref, watch } from "vue";
import { useMediaQuery } from "@shared/composables/useMediaQuery";

const {
  mainSidebarOpen = false,
  activeTool = "sheets",
  dashboardUrl = null,
  onDashboard = false,
} = defineProps<{
  mainSidebarOpen?: boolean;
  activeTool?: string;
  dashboardUrl?: string | null;
  onDashboard?: boolean;
}>();

const internalOpen = ref(false);
const desktopSidebar = useMediaQuery("(min-width: 1024px)");

function handleMainSidebarChange(event: Event) {
  const open = (event as CustomEvent<{ open?: boolean }>).detail?.open;
  if (typeof open === "boolean") internalOpen.value = open;
}

onMounted(() => {
  window.addEventListener("storyarn:main-sidebar-change", handleMainSidebarChange);
});

watch(
  desktopSidebar,
  (open) => {
    internalOpen.value = mainSidebarOpen || open;
  },
  { immediate: true },
);

watch(
  () => mainSidebarOpen,
  (open) => {
    if (open) internalOpen.value = true;
  },
);

// ProjectLayout reads `body[data-main-sidebar-open="1"]` to reveal the
// left sidebar and resize the main shell when the panel is open.
watch(
  internalOpen,
  (open) => {
    if (open) {
      document.body.dataset.mainSidebarOpen = "1";
    } else {
      delete document.body.dataset.mainSidebarOpen;
    }

    window.dispatchEvent(new CustomEvent("storyarn:main-sidebar-change", { detail: { open } }));
  },
  { immediate: true },
);

onUnmounted(() => {
  delete document.body.dataset.mainSidebarOpen;
  window.removeEventListener("storyarn:main-sidebar-change", handleMainSidebarChange);
});
</script>

<template>
  <div
    :inert="!internalOpen"
    :aria-hidden="!internalOpen"
    class="flex h-full flex-col overflow-hidden"
  >
    <div v-if="dashboardUrl" class="shrink-0 border-b border-border/10 px-2.5">
      <div class="pt-2 pb-2">
        <a
          :href="dashboardUrl"
          data-phx-link="redirect"
          data-phx-link-state="push"
          :class="[
            'flex items-center gap-2 px-2 py-1.5 rounded-md text-sm transition-colors',
            onDashboard
              ? 'bg-accent text-accent-foreground font-medium'
              : 'text-muted-foreground hover:text-foreground hover:bg-accent/50',
          ]"
        >
          <LayoutDashboard class="size-4" />
          {{
            $t("layout.main_sidebar.dashboard_label", { tool: $t(`layout.tools.${activeTool}`) })
          }}
        </a>
      </div>
    </div>

    <div class="flex-1 overflow-y-auto px-2.5 py-2">
      <slot />
    </div>
  </div>
</template>
