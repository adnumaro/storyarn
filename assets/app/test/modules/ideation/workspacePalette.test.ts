import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { flushPromises, shallowMount, type VueWrapper } from "@vue/test-utils";
import { defineComponent, h } from "vue";
import BrainstormingWorkspace from "@modules/ideation/BrainstormingWorkspace.vue";
import type { Board } from "@modules/ideation/types";
import {
  paletteGroups,
  primarySurface,
  resetPaletteRegistry,
} from "@shared/command-palette/registry";
import { createMockLive } from "../../setup";
import { board } from "./fixtures";

const fitAll = vi.fn();
const Canvas = defineComponent({
  name: "BrainstormingCanvas",
  setup(_props, { expose }) {
    expose({ fitAll, focus: vi.fn() });
    return () => h("div");
  },
});

let mounted: VueWrapper | undefined;

function workspace(overrides: Partial<Board> = {}) {
  const live = createMockLive();
  const current = board(overrides);
  const wrapper = shallowMount(BrainstormingWorkspace, {
    props: { board: current, baseUrl: "/brainstorming" },
    global: { provide: { _live_vue: live }, stubs: { BrainstormingCanvas: Canvas } },
  });
  mounted = wrapper;
  return { live, current, wrapper };
}

function commands() {
  return paletteGroups.value.flatMap((group) => group.commands);
}

function command(id: string) {
  const entry = commands().find((item) => item.id === id);
  if (!entry || !("run" in entry) || typeof entry.run !== "function") {
    throw new Error(`Missing local palette command: ${id}`);
  }
  return { ...entry, run: entry.run };
}

beforeEach(() => {
  resetPaletteRegistry();
  fitAll.mockClear();
});

afterEach(() => {
  mounted?.unmount();
  mounted = undefined;
  resetPaletteRegistry();
  vi.restoreAllMocks();
});

describe("brainstorming palette commands", () => {
  it("creates and opens a session through the existing action without duplicate pending requests", async () => {
    const { live } = workspace({ session: null });
    const create = command("brainstorming.new-session");

    expect(primarySurface.value).toBe("brainstorming");
    expect(create.labelKey).toBe("ideation.newSession");
    expect(create.enabled?.()).toBe(true);

    const pending = create.run();
    expect(create.enabled?.()).toBe(false);
    await create.run();
    expect(live.pushEvent).toHaveBeenCalledTimes(1);
    expect(vi.mocked(live.pushEvent).mock.calls[0].slice(0, 2)).toEqual([
      "create_session",
      {
        title: expect.any(String),
        preset: "openPreset",
        session_id: null,
        epoch: "epoch-one",
      },
    ]);

    vi.mocked(live.pushEvent).mock.calls[0][2]?.({ status: "ok", value: { id: 2 } });
    await flushPromises();
    expect(vi.mocked(live.pushEvent).mock.calls[1].slice(0, 2)).toEqual([
      "open_session",
      { id: 2, session_id: null, epoch: "epoch-one" },
    ]);
    expect(create.enabled?.()).toBe(false);
    vi.mocked(live.pushEvent).mock.calls[1][2]?.({ status: "ok" });
    await pending;
    expect(create.enabled?.()).toBe(true);
  });

  it("reacts to loading and edit permissions and guards a previously selected create action", async () => {
    const { live, current, wrapper } = workspace();
    const create = command("brainstorming.new-session");

    await wrapper.setProps({ board: { ...current, loading: true } });
    expect(create.enabled?.()).toBe(false);
    await create.run();
    expect(live.pushEvent).not.toHaveBeenCalled();

    await wrapper.setProps({ board: { ...current, can_edit: false } });
    expect(commands().map((item) => item.id)).not.toContain("brainstorming.new-session");
    expect(create.enabled?.()).toBe(false);
    await create.run();
    expect(live.pushEvent).not.toHaveBeenCalled();

    await wrapper.setProps({ board: current });
    expect(command("brainstorming.new-session").enabled?.()).toBe(true);
  });

  it("blocks creation while offline and restores availability when the board reconnects", async () => {
    const { live, current, wrapper } = workspace();
    const create = command("brainstorming.new-session");
    vi.spyOn(console, "warn").mockImplementation(() => {});
    vi.mocked(live.pushEvent).mockImplementationOnce(() => {
      throw new Error("offline");
    });

    window.dispatchEvent(new Event("online"));
    await flushPromises();
    expect(create.enabled?.()).toBe(false);
    await create.run();
    expect(live.pushEvent).toHaveBeenCalledTimes(1);

    command("brainstorming.fit-to-view").run();
    expect(fitAll).toHaveBeenCalledTimes(1);
    await wrapper.setProps({ board: { ...current, epoch: "epoch-two" } });
    expect(create.enabled?.()).toBe(true);
  });

  it("fits the canvas for readers and hides that action in the list and dashboard", async () => {
    const { current, wrapper } = workspace({ can_edit: false });
    const fit = command("brainstorming.fit-to-view");
    expect(fit.labelKey).toBe("ideation.canvas.fit");
    expect(fit.enabled?.()).toBe(true);
    fit.run();
    expect(fitAll).toHaveBeenCalledTimes(1);

    wrapper.getComponent(Canvas).vm.$emit("list");
    await flushPromises();
    expect(commands()).toEqual([]);
    await wrapper.setProps({ board: { ...current, session: null } });
    expect(commands()).toEqual([]);
    await wrapper.setProps({ board: current });
    command("brainstorming.fit-to-view").run();
    expect(fitAll).toHaveBeenCalledTimes(2);
  });

  it("unregisters the brainstorming surface and commands when the workspace unmounts", () => {
    const { wrapper } = workspace();
    expect(commands()).toHaveLength(2);
    wrapper.unmount();
    mounted = undefined;
    expect(commands()).toEqual([]);
    expect(primarySurface.value).toBe("global");
  });
});
