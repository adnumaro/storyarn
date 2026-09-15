import { afterEach, describe, expect, it, vi } from "vitest";
import { defineComponent, h, nextTick, reactive, ref } from "vue";
import { flushPromises, mount, type VueWrapper } from "@vue/test-utils";
import BrainstormingCanvas from "@modules/ideation/components/BrainstormingCanvas.vue";
import { bandAt, bandOffsets } from "@modules/ideation/lib/bands";
import { board, idea, round, timer } from "./fixtures";
import type { SessionTimer } from "@modules/ideation/types";

const view = reactive({ x: 0, y: 0, zoom: 1, width: 800, height: 600 });
vi.mock("@modules/ideation/composables/useCanvasViewport", () => ({
  useCanvasViewport: () => ({
    view,
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
// reka's menu needs pointer geometry jsdom lacks; the settings are plain buttons here.
const Passthrough = defineComponent({
  name: "Passthrough",
  setup:
    (_props, { slots }) =>
    () =>
      h("div", slots.default?.()),
});
const CheckboxStub = defineComponent({
  name: "DropdownMenuCheckboxItem",
  props: {
    modelValue: { type: Boolean, default: false },
    disabled: { type: Boolean, default: false },
  },
  emits: ["update:modelValue"],
  setup:
    (props, { emit, slots }) =>
    () =>
      h(
        "button",
        {
          type: "button",
          disabled: props.disabled,
          onClick: () => emit("update:modelValue", !props.modelValue),
        },
        slots.default?.(),
      ),
});
const mounted: VueWrapper[] = [];
async function pointer(target: Element, type: string, options: PointerEventInit = {}) {
  target.dispatchEvent(new PointerEvent(type, { bubbles: true, cancelable: true, ...options }));
  await nextTick();
}
const capturing = () => ({
  setPointerCapture: vi.fn(),
  hasPointerCapture: () => false,
  releasePointerCapture: vi.fn(),
});
const twoRounds = () => [
  round({ id: 20, number: 1, status: "closed", prompt: "First?" }),
  round({ id: 21, number: 2, status: "active", prompt: null }),
];
const measured = () =>
  new Map([
    [20, 0],
    [21, 320],
  ]);
function canvas(props = {}) {
  const wrapper = mount(BrainstormingCanvas, {
    attachTo: document.body,
    props: {
      notes: [
        idea({ id: 10, round_id: 20, canvas: { x: 10, y: 60 } }),
        idea({ id: 11, round_id: 21, canvas: { x: 40, y: 560 } }),
      ],
      selectedIds: [],
      editingId: null,
      permissions: { edit: true, create: true },
      historyState: { canUndo: false, canRedo: false, busy: false },
      members: [],
      statuses: {},
      collaboration: { context: { epoch: "a", session_id: 1 }, cursors: false },
      bands: {
        rounds: twoRounds(),
        offsets: new Map([
          [20, 0],
          [21, 500],
        ]),
        canManage: true,
        pending: false,
      },
      ...props,
    },
    global: {
      stubs: {
        CanvasNote: NoteStub,
        CanvasCursors: true,
        DropdownMenu: Passthrough,
        DropdownMenuTrigger: Passthrough,
        DropdownMenuContent: Passthrough,
        DropdownMenuCheckboxItem: CheckboxStub,
      },
    },
  });
  Object.assign(wrapper.element, capturing());
  mounted.push(wrapper);
  return wrapper;
}
function grab(wrapper: VueWrapper, id: number) {
  const note = wrapper.get(`[data-note-id="${id}"]`);
  Object.assign(note.element, capturing());
  return note.element;
}
afterEach(() => {
  for (const wrapper of mounted.splice(0)) wrapper.unmount();
  Object.assign(view, { x: 0, y: 0, zoom: 1 });
});

describe("band layout", () => {
  it("stacks bands as tall as their content, with a floor for empty ones", () => {
    const rounds = [
      round({ id: 3, number: 3 }),
      round({ id: 1, number: 1 }),
      round({ id: 2, number: 2 }),
    ];
    const content = new Map([
      [1, 156],
      [2, null],
      [3, 900],
    ]);
    const offsets = bandOffsets(rounds, (id) => content.get(id) ?? null);
    // 156 + 160 is under the 320 floor; an empty band is 320 tall.
    expect([...offsets]).toEqual([
      [1, 0],
      [2, 320],
      [3, 640],
    ]);
    expect(bandAt(rounds, offsets, -50)).toBe(1);
    expect(bandAt(rounds, offsets, 319)).toBe(1);
    expect(bandAt(rounds, offsets, 320)).toBe(2);
    expect(bandAt(rounds, offsets, 5000)).toBe(3);
    expect(bandAt([], offsets, 10)).toBeNull();
  });
});

describe("round bands on the canvas", () => {
  it("draws one header per round at its offset in screen space and reports the layout it measures", async () => {
    const wrapper = canvas();
    const first = wrapper.get("#brainstorming-band-20");
    // At the top of the canvas the first header already rests at its pin line.
    expect(first.attributes("style")).toContain("top: 0px");
    expect(wrapper.get("#brainstorming-band-21").attributes("style")).toContain("top: 500px");
    expect(first.text()).toContain("Round 1");
    expect(first.text()).toContain("First?");
    expect(first.text()).toContain("Closed");
    expect(wrapper.get("#brainstorming-band-21").text()).toContain("In progress");
    // Note 10 ends at 60 + 96, so band 1 is 320 tall: the given 500 is corrected.
    expect(wrapper.emitted("bands")).toEqual([[measured()]]);
    await wrapper.setProps({
      bands: { rounds: twoRounds(), offsets: measured(), canManage: true, pending: false },
    });
    expect(wrapper.emitted("bands")).toHaveLength(1);
    view.y = -100;
    view.zoom = 0.5;
    await nextTick();
    // Band 2's header sits at its own place, 60px, above the rest line: not pinned.
    expect(wrapper.get("#brainstorming-band-21").attributes("style")).toContain("top: 60px");
  });

  it("grows a band while a note is dragged past its bottom and shrinks it back", async () => {
    const wrapper = canvas({
      bands: { rounds: twoRounds(), offsets: measured(), canManage: true, pending: false },
    });
    const note = grab(wrapper, 10);
    await pointer(note, "pointerdown", { button: 0, pointerId: 1, clientX: 20, clientY: 70 });
    await pointer(wrapper.element, "pointermove", { pointerId: 1, clientX: 20, clientY: 470 });
    // The note now ends at 460 + 96; the next header follows 160 below.
    expect(wrapper.emitted("bands")?.at(-1)).toEqual([
      new Map([
        [20, 0],
        [21, 716],
      ]),
    ]);
    await pointer(wrapper.element, "pointermove", { pointerId: 1, clientX: 20, clientY: 90 });
    // Back near the top: 80 + 96 + 160.
    expect(wrapper.emitted("bands")?.at(-1)).toEqual([
      new Map([
        [20, 0],
        [21, 336],
      ]),
    ]);
    await pointer(wrapper.element, "pointerup", { pointerId: 1 });
    expect(wrapper.emitted("move")).toEqual([[[{ id: 10, point: { x: 10, y: 80 } }]]]);
  });

  it("stops a drag at the round's own header, lights it, and stops a selection as a whole", async () => {
    const wrapper = canvas({
      selectedIds: [10, 11],
      bands: { rounds: twoRounds(), offsets: measured(), canManage: true, pending: false },
    });
    const note = grab(wrapper, 10);
    await pointer(note, "pointerdown", { button: 0, pointerId: 1, clientX: 20, clientY: 70 });
    await pointer(wrapper.element, "pointermove", { pointerId: 1, clientX: 20, clientY: -500 });
    expect(wrapper.get("#brainstorming-round-20").classes()).toContain("bg-primary/5");
    expect(wrapper.get("#brainstorming-round-21").classes()).not.toContain("bg-primary/5");
    await pointer(wrapper.element, "pointerup", { pointerId: 1 });
    // Note 10 stops under the 44 px header row; note 11 moves the same 16 px.
    expect(wrapper.emitted("move")).toEqual([
      [
        [
          { id: 10, point: { x: 10, y: 44 } },
          { id: 11, point: { x: 40, y: 544 } },
        ],
      ],
    ]);
    expect(wrapper.get("#brainstorming-round-20").classes()).not.toContain("bg-primary/5");
  });

  it("keeps keyboard nudges under the header", async () => {
    const wrapper = canvas({
      notes: [idea({ id: 10, round_id: 20, canvas: { x: 10, y: 46 } })],
      selectedIds: [10],
      bands: { rounds: twoRounds(), offsets: measured(), canManage: true, pending: false },
    });
    const arrow = (key: string) =>
      wrapper.element.dispatchEvent(
        new KeyboardEvent("keydown", { key, bubbles: true, cancelable: true }),
      );
    arrow("ArrowUp");
    expect(wrapper.emitted("move")).toEqual([[[{ id: 10, point: { x: 10, y: 44 } }]]]);
    await wrapper.setProps({
      notes: [idea({ id: 10, round_id: 20, canvas: { x: 10, y: 44 } })],
    });
    arrow("ArrowUp");
    expect(wrapper.emitted("move")).toHaveLength(1);
    arrow("ArrowDown");
    expect(wrapper.emitted("move")?.[1]).toEqual([[{ id: 10, point: { x: 10, y: 46 } }]]);
  });

  it("creates notes under the header of the band they land in, never above it", async () => {
    const wrapper = canvas({
      bands: { rounds: twoRounds(), offsets: measured(), canManage: true, pending: false },
    });
    await wrapper.trigger("dblclick", { clientX: 300, clientY: 10 });
    await wrapper.trigger("dblclick", { clientX: 300, clientY: 330 });
    await wrapper.trigger("dblclick", { clientX: 300, clientY: 500 });
    expect(wrapper.emitted("add")).toEqual([
      [{ x: 300, y: 44 }],
      [{ x: 300, y: 364 }],
      [{ x: 300, y: 500 }],
    ]);
    // The keyboard shortcut aims at the viewport centre, 100 px up: clamped the same way.
    view.y = 240;
    wrapper.element.dispatchEvent(
      new KeyboardEvent("keydown", { key: "n", bubbles: true, cancelable: true }),
    );
    expect(wrapper.emitted("add")?.[3]).toEqual([{ x: 260, y: 44 }]);
  });

  it("offers the facilitator round actions on the right rounds only", async () => {
    const wrapper = canvas();
    expect(wrapper.find("#brainstorming-round-close-20").exists()).toBe(false);
    expect(wrapper.find("#brainstorming-round-new-20").exists()).toBe(false);
    expect(wrapper.find("#brainstorming-round-close-21").exists()).toBe(true);
    await wrapper.get("#brainstorming-round-close-21").trigger("click");
    expect(wrapper.emitted("closeRound")).toEqual([[21]]);
    await wrapper.get("#brainstorming-round-new-21").trigger("click");
    expect(wrapper.emitted("newRound")).toEqual([[]]);
  });

  it("lets the facilitator edit the question of the round in progress in place", async () => {
    const wrapper = canvas();
    expect(wrapper.find("#brainstorming-round-prompt-20").exists()).toBe(false);
    await wrapper.get("#brainstorming-round-prompt-21").trigger("dblclick");
    const input = wrapper.get("#brainstorming-band-21 input");
    await input.setValue("Which ending lets the player choose?");
    await input.trigger("blur");
    expect(wrapper.emitted("updatePrompt")).toEqual([[21, "Which ending lets the player choose?"]]);
    expect(wrapper.emitted("add")).toBeUndefined();
  });

  it("marks a private round with a lock, counts its notes, draws other people's notes as placeholders and lets the facilitator reveal it", async () => {
    const wrapper = canvas({
      bands: {
        rounds: [
          round({ id: 20, number: 1, status: "closed" }),
          round({ id: 21, number: 2, status: "active", private: true }),
        ],
        offsets: measured(),
        counts: new Map([
          [20, 1],
          [21, 2],
        ]),
        masked: [{ id: 99, round_id: 21, canvas: { x: 30, y: 40, width: 200 } }],
        canManage: true,
        pending: false,
      },
    });
    expect(wrapper.find("#brainstorming-round-private-20").exists()).toBe(false);
    expect(wrapper.find("#brainstorming-round-private-21").exists()).toBe(true);
    expect(wrapper.get("#brainstorming-round-count-20").text()).toBe("1 note");
    expect(wrapper.get("#brainstorming-round-count-21").text()).toBe("2 notes");
    const placeholder = wrapper.get("#canvas-masked-99");
    expect(placeholder.attributes("style")).toContain("width: 200px");
    expect(placeholder.text()).toBe("");
    await wrapper.get("#brainstorming-round-reveal-21").trigger("click");
    expect(wrapper.emitted("reveal")).toEqual([[21]]);
    await wrapper.get("#brainstorming-round-reveal-on-expiry-21").trigger("click");
    expect(wrapper.emitted("updatePrivacy")).toEqual([
      [21, { private: true, reveal_on_expiry: true }],
    ]);
    await wrapper.get("#brainstorming-round-private-toggle-21").trigger("click");
    expect(wrapper.emitted("updatePrivacy")?.[1]).toEqual([
      21,
      { private: false, reveal_on_expiry: false },
    ]);
  });

  it("keeps privacy controls from members, and settings from closed rounds", () => {
    const member = canvas({
      bands: {
        rounds: [
          round({ id: 20, number: 1, status: "closed", private: true }),
          round({ id: 21, number: 2, status: "active", private: true }),
        ],
        offsets: measured(),
        canManage: false,
        pending: false,
      },
    });
    expect(member.find("#brainstorming-round-private-21").exists()).toBe(true);
    expect(member.find("#brainstorming-round-reveal-21").exists()).toBe(false);
    expect(member.find("#brainstorming-round-settings-21").exists()).toBe(false);

    const facilitator = canvas({
      bands: {
        rounds: [
          round({ id: 20, number: 1, status: "closed", private: true }),
          round({ id: 21, number: 2, status: "active" }),
        ],
        offsets: measured(),
        canManage: true,
        pending: false,
      },
    });
    // A closed round can still be revealed, but nothing else about it changes.
    expect(facilitator.find("#brainstorming-round-reveal-20").exists()).toBe(true);
    expect(facilitator.find("#brainstorming-round-settings-20").exists()).toBe(false);
    expect(facilitator.find("#brainstorming-round-settings-21").exists()).toBe(true);
    expect(facilitator.find("#brainstorming-round-reveal-21").exists()).toBe(false);
  });

  it("keeps the last closed band able to start the next round and hides actions from members", () => {
    const closed = canvas({
      bands: {
        rounds: [
          round({ id: 20, number: 1, status: "closed" }),
          round({ id: 21, number: 2, status: "closed" }),
        ],
        offsets: measured(),
        canManage: true,
        pending: false,
      },
    });
    expect(closed.find("#brainstorming-round-new-20").exists()).toBe(false);
    expect(closed.find("#brainstorming-round-new-21").exists()).toBe(true);
    expect(closed.find("#brainstorming-round-close-21").exists()).toBe(false);
    closed.unmount();
    mounted.splice(mounted.indexOf(closed), 1);

    const member = canvas({
      bands: {
        rounds: [round({ id: 20, number: 1 }), round({ id: 21, number: 2 })],
        offsets: measured(),
        canManage: false,
        pending: false,
      },
    });
    expect(member.find("#brainstorming-round-new-21").exists()).toBe(false);
    expect(member.find("#brainstorming-band-21").exists()).toBe(true);
  });

  it("offers to bring a note of an earlier round into the one in progress, under its content", async () => {
    const bring = async (wrapper: VueWrapper, id: number) => {
      await wrapper.get(`[data-note-id="${id}"]`).trigger("contextmenu", { button: 2 });
      await flushPromises();
      return document.querySelector<HTMLElement>("#brainstorming-note-context-bring");
    };
    const wrapper = canvas();
    const item = await bring(wrapper, 10);
    expect(item?.textContent).toContain("Bring to the active round");
    item!.click();
    await flushPromises();
    // Note 11 ends at 560 + 96 in round 2, whose header sits at 500: the copy goes under it.
    expect(wrapper.emitted("bringForward")).toEqual([[10, { x: 10, y: 680 }]]);
    wrapper.unmount();
    mounted.splice(mounted.indexOf(wrapper), 1);

    expect(await bring(canvas(), 11)).toBeNull();
    expect(await bring(canvas({ permissions: { edit: true, create: false } }), 10)).toBeNull();
  });

  it("stays quiet with a single round and only shows its question, or the facilitator's placeholder", () => {
    const single = (prompt: string | null, canManage: boolean, clock: SessionTimer | null = null) =>
      canvas({
        notes: [idea({ id: 10, round_id: 20, canvas: { x: 10, y: 60 } })],
        bands: {
          rounds: [round({ id: 20, number: 1, prompt })],
          offsets: new Map([[20, 0]]),
          canManage,
          pending: false,
          timer: clock && {
            session: board().session!,
            epoch: "a",
            timer: clock,
            canEdit: canManage,
          },
        },
      });
    const quiet = single(null, false);
    expect(quiet.find("#brainstorming-band-20").exists()).toBe(false);
    expect(quiet.find("#brainstorming-round-next").exists()).toBe(false);

    const facilitator = single(null, true);
    const placeholder = facilitator.get("#brainstorming-band-20");
    expect(placeholder.text()).not.toContain("Round 1");
    expect(placeholder.find("#brainstorming-round-prompt-20").exists()).toBe(true);
    expect(facilitator.find("#brainstorming-round-new-20").exists()).toBe(false);

    const asked = single("Where does Mara go?", false);
    const header = asked.get("#brainstorming-band-20");
    expect(header.text()).toContain("Where does Mara go?");
    expect(header.text()).not.toContain("Round 1");
    // Nothing to operate: no controls row, so a narrow screen keeps one line.
    expect(asked.find("#brainstorming-round-controls-20").exists()).toBe(false);

    // A participant consults the clock in the same header once it runs.
    const clocked = single(null, false, timer({ status: "paused" }));
    expect(clocked.get("#brainstorming-band-20 #brainstorming-round-timer").text()).toBe("05:00");
    expect(clocked.find("#brainstorming-round-controls-20").exists()).toBe(true);
    expect(clocked.get("#brainstorming-band-20").text()).not.toContain("Round 1");
    const stopped = single(null, false, timer({ status: "cancelled" }));
    expect(stopped.find("#brainstorming-band-20").exists()).toBe(false);
  });

  it("keeps the clock on the last band once no round is in progress", () => {
    const wrapper = canvas({
      notes: [idea({ id: 10, round_id: 20, canvas: { x: 10, y: 60 } })],
      bands: {
        rounds: [
          round({ id: 20, number: 1, status: "closed" }),
          round({ id: 21, number: 2, status: "closed" }),
        ],
        offsets: new Map([
          [20, 0],
          [21, 500],
        ]),
        canManage: false,
        pending: false,
        timer: {
          session: board().session!,
          epoch: "a",
          timer: timer({ status: "paused" }),
          canEdit: false,
        },
      },
    });
    expect(wrapper.get("#brainstorming-band-21 #brainstorming-round-timer").text()).toBe("05:00");
    expect(wrapper.find("#brainstorming-band-20 #brainstorming-round-timer").exists()).toBe(false);
  });

  it("opens on the round in progress and fits everything when there is one round", async () => {
    const wrapper = canvas();
    await nextTick();
    // The measured layout puts Round 2 at 320, whatever the props said.
    expect(view.y).toBe(0 - 320);
    wrapper.unmount();
    mounted.splice(mounted.indexOf(wrapper), 1);
    Object.assign(view, { x: 0, y: 0, zoom: 1 });
    const single = canvas({
      notes: [idea({ id: 10, round_id: 20, canvas: { x: 10, y: 60 } })],
      bands: {
        rounds: [round({ id: 20, number: 1, prompt: null })],
        offsets: new Map([[20, 0]]),
        canManage: false,
        pending: false,
      },
    });
    await nextTick();
    expect(view.y).toBe(0);
    // The single band already sits at 0: nothing to report, everything fitted.
    expect(single.emitted("bands")).toBeUndefined();
  });

  it("pins a band's header under the chrome while the viewport is inside it, until the next header pushes it out", async () => {
    const wrapper = canvas();
    const style = (id: number) => wrapper.get(`#brainstorming-band-${id}`).attributes("style");
    const pinned = (id: number) =>
      wrapper.get(`#brainstorming-band-${id}`).attributes("data-pinned");
    // The rest line is the top edge, where a jump to a round also leaves its header.
    view.y = -100;
    await nextTick();
    expect(style(20)).toContain("top: 0px");
    expect(pinned(20)).toBe("true");
    expect(style(21)).toContain("top: 400px");
    expect(pinned(21)).toBeUndefined();
    view.y = -480;
    await nextTick();
    expect(style(20)).toContain("top: -22px");
    view.y = -600;
    await nextTick();
    expect(style(21)).toContain("top: 0px");
    expect(pinned(21)).toBe("true");
    view.zoom = 0.5;
    view.y = -100;
    await nextTick();
    expect(style(20)).toContain("top: 0px");
    expect(style(21)).toContain("top: 150px");
  });

  it("lands a jump again two frames later, once the notes have been measured", async () => {
    const wrapper = canvas();
    const scroll = (wrapper.vm as unknown as { scrollToRound: (round: { id: number }) => void })
      .scrollToRound;
    scroll(round({ id: 21 }));
    expect(view.y).toBe(0 - 320);
    // Band 1's content measures lower right after the jump: the header follows.
    await wrapper.setProps({
      notes: [
        idea({ id: 10, round_id: 20, canvas: { x: 10, y: 300 } }),
        idea({ id: 11, round_id: 21, canvas: { x: 40, y: 560 } }),
      ],
    });
    await new Promise<void>((resolve) => {
      requestAnimationFrame(() => requestAnimationFrame(() => resolve()));
    });
    expect(view.y).toBe(0 - (300 + 96 + 160));
  });

  it("scrolls a band's header to the top at any zoom", () => {
    const wrapper = canvas();
    const scroll = (wrapper.vm as unknown as { scrollToRound: (round: { id: number }) => void })
      .scrollToRound;
    scroll(round({ id: 21 }));
    expect(view.y).toBe(0 - 320);
    view.zoom = 0.5;
    scroll(round({ id: 21 }));
    expect(view.y).toBe(0 - 160);
  });
});
