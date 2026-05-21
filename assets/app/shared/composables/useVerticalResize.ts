import { ref } from "vue";

interface UseVerticalResizeOptions {
  initial: number;
  min: number;
  max: number;
  /**
   * `up` (default): dragging the handle upwards grows the panel (for
   * bottom-docked panels). `down`: dragging down grows it (for top-docked).
   */
  direction?: "up" | "down";
}

export function useVerticalResize({
  initial,
  min,
  max,
  direction = "up",
}: UseVerticalResizeOptions) {
  const height = ref(initial);

  function onPointerDown(event: PointerEvent) {
    event.preventDefault();
    const startY = event.clientY;
    const startHeight = height.value;

    function onMove(ev: PointerEvent) {
      const dy = direction === "up" ? startY - ev.clientY : ev.clientY - startY;
      height.value = Math.max(min, Math.min(max, startHeight + dy));
    }

    function onUp() {
      window.removeEventListener("pointermove", onMove);
      window.removeEventListener("pointerup", onUp);
      window.removeEventListener("pointercancel", onUp);
      document.body.style.userSelect = "";
      document.body.style.cursor = "";
    }

    document.body.style.userSelect = "none";
    document.body.style.cursor = "row-resize";
    window.addEventListener("pointermove", onMove);
    window.addEventListener("pointerup", onUp);
    window.addEventListener("pointercancel", onUp);
  }

  return { height, onPointerDown };
}
