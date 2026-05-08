import { computed, onMounted, onUnmounted, ref, type Ref } from "vue";
import { useLive } from "../../../shared/composables/useLive";
import type { KonvaEventObject } from "konva/lib/Node";

const SELECTION_COLOR = "#6366f1";
const DELETE_KEYS = new Set(["Delete", "Backspace"]);

interface UseSelectionOpts {
  activeTool: Ref<string>;
  onCreationClick?: (e: KonvaEventObject<MouseEvent>) => boolean;
}

/**
 * Composable managing element selection state, click handlers, and server sync.
 * Selection is optimistic -- visual highlight appears immediately on click,
 * server confirms asynchronously.
 */
export function useSelection({ activeTool, onCreationClick }: UseSelectionOpts) {
  const live = useLive();
  const selectedType = ref<string | null>(null);
  const selectedId = ref<number | string | null>(null);

  const isSelectMode = computed(() => activeTool.value === "select");

  function handleElementClick(
    type: string,
    id: number | string,
    e?: KonvaEventObject<MouseEvent>,
  ): void {
    if (!isSelectMode.value) {
      return;
    }
    // Stop propagation so stage click doesn't deselect
    if (e) {
      e.cancelBubble = true;
    }

    // Optimistic: update local state immediately
    selectedType.value = type;
    selectedId.value = id;

    // Notify server
    live.pushEvent("select_element", { type, id: String(id) });
  }

  function handleStageClick(e: KonvaEventObject<MouseEvent>): void {
    // Creation tools get first priority (pin, annotation)
    if (onCreationClick?.(e)) {
      return;
    }

    // Select mode: deselect on empty canvas click
    if (!isSelectMode.value) {
      return;
    }
    const stage = e.target.getStage();
    if (e.target !== stage) {
      return;
    }

    if (selectedType.value !== null) {
      selectedType.value = null;
      selectedId.value = null;
      live.pushEvent("deselect", {});
    }
  }

  // Delete selected element on Delete/Backspace (skip if typing in an input)
  function onKeyDown(e: KeyboardEvent): void {
    if (!DELETE_KEYS.has(e.key)) {
      return;
    }
    if (!selectedType.value) {
      return;
    }
    const tag = (e.target as HTMLElement).tagName;
    if (tag === "INPUT" || tag === "TEXTAREA" || (e.target as HTMLElement).isContentEditable) {
      return;
    }
    e.preventDefault();
    live.pushEvent("delete_selected", {});
  }

  // Listen for server-driven selection (e.g., from SearchPanel focus)
  onMounted(() => {
    live.handleEvent("element_selected", (payload) => {
      const type = String(payload.type ?? "");
      const id = String(payload.id ?? "");
      selectedType.value = type;
      selectedId.value = Number(id);
    });

    live.handleEvent("element_deselected", () => {
      selectedType.value = null;
      selectedId.value = null;
    });

    window.addEventListener("keydown", onKeyDown);
  });

  onUnmounted(() => {
    window.removeEventListener("keydown", onKeyDown);
  });

  return {
    selectedType,
    selectedId,
    isSelectMode,
    handleElementClick,
    handleStageClick,
    SELECTION_COLOR,
  };
}
