import { computed, onUnmounted, ref, watch, type Ref } from "vue";

type Panel = "library" | "inspector";
interface PanelWidths {
  library: number;
  inspector: number;
}
interface ResizeOptions {
  root: Ref<HTMLElement | null>;
  libraryOpen: () => boolean;
  inspectorOpen: () => boolean;
}
interface ResizeGesture {
  kind: "pointer" | "keyboard";
  panel: Panel;
  previous: PanelWidths;
  startWidth: number;
  clientX: number;
  pointerId?: number;
  bodyStyles: { property: string; value: string; priority: string }[];
}

const MIN_WIDTH: PanelWidths = { library: 180, inspector: 240 };
const MAX_WIDTH: PanelWidths = { library: 420, inspector: 480 };
const RESIZE_KEYS = new Set(["ArrowLeft", "ArrowRight", "Home", "End"]);
const SEPARATOR_WIDTH = 6;
const MIN_CANVAS_WIDTH = 320;

export function useSequenceWorkspaceResize(options: ResizeOptions) {
  const preferred = ref<PanelWidths>({ library: 240, inspector: 288 });
  const rootWidth = ref(0);
  const resizing = ref<Panel | null>(null);
  const compact = computed(() => rootWidth.value <= 780);
  let gesture: ResizeGesture | null = null;
  let observer: ResizeObserver | null = null;
  const open = (panel: Panel) =>
    panel === "library" ? options.libraryOpen() : options.inspectorOpen();
  const available = computed(
    () =>
      rootWidth.value -
      MIN_CANVAS_WIDTH -
      SEPARATOR_WIDTH * (Number(options.libraryOpen()) + Number(options.inspectorOpen())),
  );
  const widths = computed(() => fitWidths(preferred.value, open, available.value, compact.value));
  const libraryWidth = computed(() => widths.value.library);
  const inspectorWidth = computed(() => widths.value.inspector);
  function limits(panel: Panel) {
    const other = panel === "library" ? "inspector" : "library";
    const remaining = available.value - (open(other) ? widths.value[other] : 0);
    return {
      min: MIN_WIDTH[panel],
      max: Math.max(MIN_WIDTH[panel], Math.floor(Math.min(MAX_WIDTH[panel], remaining))),
    };
  }
  const libraryLimits = computed(() => limits("library"));
  const inspectorLimits = computed(() => limits("inspector"));

  function setWidth(panel: Panel, width: number) {
    const { min, max } = limits(panel);
    preferred.value = {
      ...preferred.value,
      [panel]: Math.round(Math.max(min, Math.min(max, width))),
    };
  }

  function begin(panel: Panel, kind: ResizeGesture["kind"]): ResizeGesture | null {
    if (compact.value || !open(panel) || !options.root.value) return null;
    cancelResize();
    const previous = { ...preferred.value };
    const fitted = widths.value;
    const startWidth = fitted[panel];
    // Freeze the other visible panel at its fitted width while dragging this separator.
    for (const name of ["library", "inspector"] as const) {
      if (open(name)) preferred.value[name] = fitted[name];
    }
    gesture = { kind, panel, previous, startWidth, clientX: 0, bodyStyles: [] };
    resizing.value = panel;
    window.addEventListener("keydown", escapeResize, true);
    window.addEventListener("blur", cancelResize);
    return gesture;
  }

  function startResize(event: PointerEvent, panel: Panel) {
    if (event.button !== 0 || event.isPrimary === false) return;
    const session = begin(panel, "pointer");
    if (!session) return;
    event.preventDefault();
    event.stopPropagation();
    (event.currentTarget as HTMLElement | null)?.focus();
    session.pointerId = event.pointerId;
    session.clientX = event.clientX;
    for (const [property, value] of [
      ["cursor", "col-resize"],
      ["user-select", "none"],
    ] as const) {
      session.bodyStyles.push({
        property,
        value: document.body.style.getPropertyValue(property),
        priority: document.body.style.getPropertyPriority(property),
      });
      document.body.style.setProperty(property, value);
    }
    window.addEventListener("pointermove", movePointer);
    window.addEventListener("pointerup", finishPointer);
    window.addEventListener("pointercancel", cancelPointer);
  }

  function matchingPointer(event: PointerEvent) {
    return gesture?.kind === "pointer" && gesture.pointerId === event.pointerId;
  }
  function movePointer(event: PointerEvent) {
    if (!gesture || !matchingPointer(event)) return;
    const direction = gesture.panel === "library" ? 1 : -1;
    setWidth(gesture.panel, gesture.startWidth + direction * (event.clientX - gesture.clientX));
  }
  function finishPointer(event: PointerEvent) {
    if (!matchingPointer(event)) return;
    movePointer(event);
    finishResize();
  }
  function cancelPointer(event: PointerEvent) {
    if (matchingPointer(event)) cancelResize();
  }

  function onResizeKeydown(event: KeyboardEvent, panel: Panel) {
    if (!RESIZE_KEYS.has(event.key) || event.ctrlKey || event.metaKey || event.altKey) return;
    if (compact.value || !open(panel)) return;
    event.preventDefault();
    event.stopPropagation();
    if (!beginKeyboard(panel)) return;
    setWidth(panel, keyboardWidth(event, panel, widths.value[panel], limits(panel)));
  }
  function beginKeyboard(panel: Panel): boolean {
    if (gesture?.kind === "keyboard" && gesture.panel === panel) return true;
    if (!begin(panel, "keyboard")) return false;
    window.addEventListener("keyup", finishKeyboard);
    return true;
  }
  function finishKeyboard(event: KeyboardEvent) {
    if (gesture?.kind === "keyboard" && RESIZE_KEYS.has(event.key)) finishResize();
  }
  function escapeResize(event: KeyboardEvent) {
    if (event.key !== "Escape") return;
    event.preventDefault();
    event.stopPropagation();
    cancelResize();
  }
  function finishResize() {
    window.removeEventListener("pointermove", movePointer);
    window.removeEventListener("pointerup", finishPointer);
    window.removeEventListener("pointercancel", cancelPointer);
    window.removeEventListener("keydown", escapeResize, true);
    window.removeEventListener("keyup", finishKeyboard);
    window.removeEventListener("blur", cancelResize);
    for (const { property, value, priority } of gesture?.bodyStyles ?? []) {
      document.body.style.setProperty(property, value, priority);
    }
    gesture = null;
    resizing.value = null;
  }
  function cancelResize() {
    const previous = gesture?.previous;
    finishResize();
    if (previous) preferred.value = previous;
  }
  function measure(width: number) {
    if (width === rootWidth.value) return;
    cancelResize();
    rootWidth.value = width;
  }
  function refresh() {
    measure(options.root.value?.getBoundingClientRect().width ?? 0);
  }
  watch(
    options.root,
    (element) => {
      cancelResize();
      observer?.disconnect();
      refresh();
      if (!element || typeof ResizeObserver === "undefined") return;
      observer = new ResizeObserver(([entry]) => {
        if (entry) measure(entry.contentRect.width);
      });
      observer.observe(element);
    },
    { immediate: true, flush: "post" },
  );
  watch([options.libraryOpen, options.inspectorOpen], cancelResize, { flush: "sync" });
  window.addEventListener("resize", refresh);
  onUnmounted(() => {
    cancelResize();
    observer?.disconnect();
    window.removeEventListener("resize", refresh);
  });

  return {
    libraryWidth,
    inspectorWidth,
    libraryLimits,
    inspectorLimits,
    compact,
    resizing,
    startResize,
    onResizeKeydown,
    cancelResize,
  };
}

function fitWidths(
  preferred: PanelWidths,
  open: (panel: Panel) => boolean,
  available: number,
  compact: boolean,
): PanelWidths {
  if (compact) return preferred;
  const library = open("library") ? preferred.library : 0;
  const inspector = open("inspector") ? preferred.inspector : 0;
  const libraryMin = open("library") ? MIN_WIDTH.library : 0;
  const inspectorMin = open("inspector") ? MIN_WIDTH.inspector : 0;
  const slack = library + inspector - libraryMin - inspectorMin;
  const excess = Math.max(0, library + inspector - available);
  const reduction = slack > 0 ? (excess * (library - libraryMin)) / slack : 0;
  const fittedLibrary = Math.max(libraryMin, Math.floor(library - reduction));
  return { library: fittedLibrary, inspector: Math.min(inspector, available - fittedLibrary) };
}

function keyboardWidth(
  event: KeyboardEvent,
  panel: Panel,
  current: number,
  limits: { min: number; max: number },
): number {
  if (event.key === "Home") return limits.min;
  if (event.key === "End") return limits.max;
  const direction = panel === "library" ? 1 : -1;
  const step = event.shiftKey ? 40 : 10;
  const delta = event.key === "ArrowRight" ? step : -step;
  return current + direction * delta;
}
