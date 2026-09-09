import { onMounted, onUnmounted, ref, type Ref } from "vue";
import type { NoteBounds, Point } from "./useCanvasViewport";

interface Selection {
  ids: number[];
  groupId: number | null;
}
interface Gesture {
  pointer: number;
  start: Point;
  origin: Point;
  initial: Selection;
  additive: boolean;
  clickGroup: number | null;
  moved: boolean;
  capture: HTMLElement;
}
interface Options {
  root: Ref<HTMLElement | null>;
  world: (x: number, y: number) => Point;
  bounds: () => Array<NoteBounds & { id: number }>;
  selection: () => Selection;
  select: (selection: Selection) => void;
}

function rectangle(a: Point, b: Point): NoteBounds {
  return {
    x: Math.min(a.x, b.x),
    y: Math.min(a.y, b.y),
    width: Math.abs(b.x - a.x),
    height: Math.abs(b.y - a.y),
  };
}

export function useCanvasMarquee(options: Options) {
  const active = ref(false);
  const area = ref<NoteBounds | null>(null);
  let gesture: Gesture | null = null;

  function begin(event: PointerEvent, clickGroup: number | null = null) {
    const capture = options.root.value;
    if (!capture || gesture) return;
    event.preventDefault();
    const initial = options.selection();
    gesture = {
      pointer: event.pointerId,
      start: { x: event.clientX, y: event.clientY },
      origin: options.world(event.clientX, event.clientY),
      initial: { ids: [...initial.ids], groupId: initial.groupId },
      additive: event.shiftKey,
      clickGroup,
      moved: false,
      capture,
    };
    active.value = true;
    capture.setPointerCapture(event.pointerId);
    if (clickGroup === null)
      options.select({ ids: event.shiftKey ? initial.ids : [], groupId: null });
  }

  function move(event: PointerEvent) {
    if (!gesture || gesture.pointer !== event.pointerId) return;
    const { start, origin } = gesture;
    if (Math.hypot(event.clientX - start.x, event.clientY - start.y) > 3) gesture.moved = true;
    if (!gesture.moved) return;
    const rect = rectangle(origin, options.world(event.clientX, event.clientY));
    const bounds = options.bounds();
    const hits = bounds.filter(
      (note) =>
        note.x <= rect.x + rect.width &&
        note.x + note.width >= rect.x &&
        note.y <= rect.y + rect.height &&
        note.y + note.height >= rect.y,
    );
    // Always union with the selection at pointerdown, not the previous preview.
    const base = gesture.additive
      ? gesture.initial.ids.filter((id) => bounds.some((note) => note.id === id))
      : [];
    const ids = [...new Set([...base, ...hits.map((note) => note.id)])];
    const current = options.selection();
    if (current.groupId !== null || ids.join() !== current.ids.join())
      options.select({ ids, groupId: null });

    const screen = rectangle(start, { x: event.clientX, y: event.clientY });
    const container = gesture.capture.getBoundingClientRect();
    area.value = { ...screen, x: screen.x - container.left, y: screen.y - container.top };
  }

  function release() {
    const finished = gesture;
    // lostpointercapture can fire synchronously when capture is released.
    gesture = null;
    active.value = false;
    area.value = null;
    if (finished?.capture.hasPointerCapture(finished.pointer))
      finished.capture.releasePointerCapture(finished.pointer);
  }

  function finish(event: PointerEvent): boolean {
    if (!gesture || gesture.pointer !== event.pointerId) return false;
    move(event);
    const { moved, clickGroup } = gesture;
    release();
    if (!moved && clickGroup !== null) options.select({ ids: [], groupId: clickGroup });
    return true;
  }

  function cancel(event?: PointerEvent) {
    if (!gesture || (event && event.pointerId !== gesture.pointer)) return;
    const initial = gesture.initial;
    release();
    const available = options.bounds();
    options.select({
      ids: initial.ids.filter((id) => available.some((note) => note.id === id)),
      groupId: initial.groupId,
    });
  }
  const blur = () => cancel();
  onMounted(() => window.addEventListener("blur", blur));
  onUnmounted(() => {
    release();
    window.removeEventListener("blur", blur);
  });

  return { active, area, begin, move, finish, cancel };
}
