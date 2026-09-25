import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { defineComponent, h, nextTick, reactive, ref } from "vue";
import { mount, type VueWrapper } from "@vue/test-utils";
import BrainstormingCanvas from "@modules/ideation/components/BrainstormingCanvas.vue";
import type { Point } from "@modules/ideation/composables/useCanvasViewport";
import { decision } from "../../live/ideation/decisionFixtures";
import { idea, round } from "./fixtures";

vi.mock("@modules/ideation/composables/useCanvasViewport", () => ({
  useCanvasViewport: () => ({
    view: reactive({ x: 0, y: 0, zoom: 1, width: 800, height: 600 }),
    space: ref(false),
    transform: ref(""),
    world: (x: number, y: number) => ({ x, y }),
    zoomTo: vi.fn(),
    wheel: vi.fn(),
    fit: vi.fn(),
  }),
}));
const NoteStub = defineComponent({
  props: ["note"],
  setup: (props) => () => h("article", { "data-test-note": props.note.id }, "Text"),
});

beforeAll(() => {
  Object.assign(HTMLElement.prototype, {
    setPointerCapture: () => undefined,
    hasPointerCapture: () => false,
    releasePointerCapture: () => undefined,
  });
});
const mounted: VueWrapper[] = [];
afterEach(() => mounted.splice(0).forEach((wrapper) => wrapper.unmount()));

function canvas(places = new Map<number, Point>(), edit = true) {
  const move = vi.fn(async () => undefined);
  const wrapper = mount(BrainstormingCanvas, {
    attachTo: document.body,
    props: {
      notes: [idea({ id: 10, round_id: 20, canvas: { x: 0, y: 600 } })],
      selectedIds: [],
      editingId: null,
      permissions: { edit, create: true },
      historyState: { canUndo: false, canRedo: false, busy: false },
      members: [],
      statuses: {},
      collaboration: { context: { epoch: "a", session_id: 1 }, cursors: true },
      bands: {
        rounds: [round({ id: 20, number: 1 }), round({ id: 21, number: 2, status: "closed" })],
        offsets: new Map([
          [20, 0],
          [21, 0],
        ]),
        canManage: false,
        pending: false,
        lanes: { decisions: [decision({ id: 1 })], focusId: null, places, move },
      },
    },
    global: { stubs: { CanvasNote: NoteStub, CanvasCursors: true } },
  });
  mounted.push(wrapper);
  return { wrapper, move };
}
async function pointer(target: Element, type: string, x: number, y: number) {
  target.dispatchEvent(
    new PointerEvent(type, {
      bubbles: true,
      cancelable: true,
      pointerId: 1,
      clientX: x,
      clientY: y,
    }),
  );
  await nextTick();
}

describe("dragging a decision lane on the board", () => {
  it("moves the whole lane from one of its cards and hands the drop to the session", async () => {
    const { wrapper, move } = canvas();
    const card = wrapper.get("#decision-lane-card-1").element;
    const frame = wrapper.get("[data-decision-lane]");
    const before = frame.attributes("style");
    await pointer(card, "pointerdown", 100, 100);
    await pointer(card, "pointermove", 160, 180);
    expect(frame.attributes("style")).not.toBe(before);
    await pointer(card, "pointerup", 160, 180);
    await nextTick();
    expect(move).toHaveBeenCalledOnce();
    const [roundId, point, from] = move.mock.calls[0] as unknown as [number, Point, Point];
    expect(roundId).toBe(20);
    expect([point.x - from.x, point.y - from.y]).toEqual([60, 80]);
  });

  it("leaves the lane where it is for a reader who cannot edit", async () => {
    const { wrapper, move } = canvas(new Map(), false);
    const card = wrapper.get("#decision-lane-card-1").element;
    await pointer(card, "pointerdown", 100, 100);
    await pointer(card, "pointermove", 160, 180);
    await pointer(card, "pointerup", 160, 180);
    expect(move).not.toHaveBeenCalled();
  });

  it("keeps the band tall enough for notes below a lane that was moved up", async () => {
    const { wrapper } = canvas(new Map([[20, { x: 0, y: 40 }]]));
    await nextTick();
    const offsets = wrapper.emitted("bands")?.at(-1)?.[0] as Map<number, number>;
    // The note ends at 600 + 96; the next band starts below it, not below the lane.
    expect(offsets.get(21)).toBeGreaterThanOrEqual(696);
  });
});
