import { computed, onMounted, onUnmounted, reactive, ref, type Ref } from "vue";
export interface Point {
  x: number;
  y: number;
}
export interface NoteBounds extends Point {
  width: number;
  height: number;
}
export function useCanvasViewport(container: Ref<HTMLElement | null>) {
  const view = reactive({ x: 100, y: 100, zoom: 1, width: 800, height: 600 });
  const space = ref(false);
  const transform = computed(() => `translate(${view.x}px, ${view.y}px) scale(${view.zoom})`);
  let observer: ResizeObserver | undefined;
  function world(clientX: number, clientY: number): Point {
    const rect = container.value?.getBoundingClientRect();
    return {
      x: (clientX - (rect?.left ?? 0) - view.x) / view.zoom,
      y: (clientY - (rect?.top ?? 0) - view.y) / view.zoom,
    };
  }
  function zoomTo(value: number, at = { x: view.width / 2, y: view.height / 2 }) {
    const next = Math.max(0.15, Math.min(3, value));
    view.x = at.x - ((at.x - view.x) / view.zoom) * next;
    view.y = at.y - ((at.y - view.y) / view.zoom) * next;
    view.zoom = next;
  }
  function wheel(event: WheelEvent) {
    event.preventDefault();
    const rect = container.value?.getBoundingClientRect();
    if (event.ctrlKey || event.metaKey)
      zoomTo(view.zoom * Math.exp(-event.deltaY * 0.01), {
        x: event.clientX - (rect?.left ?? 0),
        y: event.clientY - (rect?.top ?? 0),
      });
    else {
      view.x -= event.deltaX;
      view.y -= event.deltaY;
    }
  }
  function fit(notes: NoteBounds[]) {
    if (!notes.length) {
      view.x = view.width / 2 - 140;
      view.y = view.height / 2 - 120;
      view.zoom = 1;
      return;
    }
    const left = Math.min(...notes.map((n) => n.x)),
      top = Math.min(...notes.map((n) => n.y));
    const width = Math.max(...notes.map((n) => n.x + n.width)) - left;
    const height = Math.max(...notes.map((n) => n.y + n.height)) - top;
    view.zoom = Math.max(
      0.15,
      Math.min(1, (view.width - 120) / width, (view.height - 160) / height),
    );
    view.x = (view.width - width * view.zoom) / 2 - left * view.zoom;
    view.y = (view.height - height * view.zoom) / 2 - top * view.zoom;
  }
  function canvasTarget(target: EventTarget | null): boolean {
    return (
      target instanceof Element &&
      Boolean(container.value?.contains(target)) &&
      !target.closest(
        'button, a, input, textarea, select, summary, [contenteditable]:not([contenteditable="false"]), [role="textbox"], [role="button"], [role="link"], [data-canvas-chrome]',
      )
    );
  }
  function key(event: KeyboardEvent) {
    if (event.code !== "Space") return;
    if (event.type === "keyup") {
      space.value = false;
      return;
    }
    if (
      event.defaultPrevented ||
      event.altKey ||
      event.ctrlKey ||
      event.metaKey ||
      event.isComposing ||
      !canvasTarget(event.target)
    )
      return;
    event.preventDefault();
    space.value = true;
  }
  function blur() {
    space.value = false;
  }
  onMounted(() => {
    if (container.value) {
      view.width = container.value.clientWidth;
      view.height = container.value.clientHeight;
    }
    observer = new ResizeObserver(([entry]) => {
      view.width = entry!.contentRect.width;
      view.height = entry!.contentRect.height;
    });
    if (container.value) observer.observe(container.value);
    window.addEventListener("keydown", key);
    window.addEventListener("keyup", key);
    window.addEventListener("blur", blur);
  });
  onUnmounted(() => {
    observer?.disconnect();
    window.removeEventListener("keydown", key);
    window.removeEventListener("keyup", key);
    window.removeEventListener("blur", blur);
  });
  return { view, space, transform, world, zoomTo, wheel, fit };
}
