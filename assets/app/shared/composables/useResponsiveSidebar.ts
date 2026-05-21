import { computed, ref, watch, type ComputedRef, type Ref } from "vue";
import { useMediaQuery } from "./useMediaQuery";

interface ResponsiveSidebar {
  desktopSidebarOpen: Readonly<Ref<boolean>>;
  mobileSidebarOpen: Ref<boolean>;
  sidebarOpen: ComputedRef<boolean>;
  closeSidebar: () => void;
  openSidebar: () => void;
  toggleSidebar: () => void;
}

export function useResponsiveSidebar(query = "(min-width: 1024px)"): ResponsiveSidebar {
  const desktopSidebarOpen = useMediaQuery(query);
  const mobileSidebarOpen = ref(false);
  const sidebarOpen = computed(() => desktopSidebarOpen.value || mobileSidebarOpen.value);

  function closeSidebar(): void {
    mobileSidebarOpen.value = false;
  }

  function openSidebar(): void {
    if (!desktopSidebarOpen.value) mobileSidebarOpen.value = true;
  }

  function toggleSidebar(): void {
    if (!desktopSidebarOpen.value) mobileSidebarOpen.value = !mobileSidebarOpen.value;
  }

  watch(desktopSidebarOpen, (open) => {
    if (open) closeSidebar();
  });

  return {
    desktopSidebarOpen,
    mobileSidebarOpen,
    sidebarOpen,
    closeSidebar,
    openSidebar,
    toggleSidebar,
  };
}
