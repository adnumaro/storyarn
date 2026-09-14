import { afterEach, describe, expect, it, vi } from "vitest";
import { nextTick } from "vue";
import { mount, type VueWrapper } from "@vue/test-utils";
import BrainstormingSidebar from "@modules/ideation/BrainstormingSidebar.vue";
import { board, round } from "./fixtures";

const mounted: VueWrapper[] = [];
async function sidebar(
  sessions: ReturnType<typeof board>["sessions"],
  path = "/p/brainstorming/1",
) {
  window.history.replaceState({}, "", path);
  const wrapper = mount(BrainstormingSidebar, {
    attachTo: document.body,
    props: { board: board({ session: null, sessions }), baseUrl: "/p/brainstorming" },
    global: {
      provide: {
        _live_vue: {
          pushEvent: vi.fn(),
          handleEvent: vi.fn(),
          removeHandleEvent: vi.fn(),
          upload: vi.fn(),
        },
      },
      stubs: { SidebarFrame: { template: "<div><slot /></div>" } },
    },
  });
  mounted.push(wrapper);
  // The current route is read on mount and rendered on the next tick.
  await nextTick();
  return wrapper;
}
function session(overrides: Partial<ReturnType<typeof board>["sessions"][number]> = {}) {
  return { ...board().session!, ...overrides };
}
afterEach(() => {
  for (const wrapper of mounted.splice(0)) wrapper.unmount();
});

describe("brainstorming session tree", () => {
  it("lists a single-round session as a leaf and expands the current session into its rounds", async () => {
    const wrapper = await sidebar([
      session({
        id: 1,
        title: "Endings we could ship",
        rounds: [
          round({ id: 20, number: 1, status: "closed" }),
          round({ id: 21, number: 2, status: "active" }),
        ],
        parked_count: 1,
      }),
      session({ id: 2, title: "Untitled session", rounds: [round({ id: 30 })], parked_count: 0 }),
    ]);
    const rows = wrapper.findAll("#brainstorming-tree-rounds-1 a");
    expect(rows.map((row) => row.attributes("href"))).toEqual([
      "/p/brainstorming/1?round=20",
      "/p/brainstorming/1?round=21",
      "/p/brainstorming/1?view=later",
    ]);
    expect(wrapper.get("#brainstorming-tree-round-21").text()).toContain("Round 2");
    expect(wrapper.get("#brainstorming-tree-later-1").text()).toContain("For later");
    expect(wrapper.get("#brainstorming-tree-later-1").text()).toContain("1");
    expect(wrapper.find("#brainstorming-tree-rounds-2").exists()).toBe(false);
    expect(wrapper.find("#brainstorming-tree-session-2 button").exists()).toBe(false);
  });

  it("collapses on demand and marks the linked round or list as current", async () => {
    const wrapper = await sidebar(
      [
        session({
          id: 1,
          rounds: [round({ id: 20, number: 1 }), round({ id: 21, number: 2 })],
          parked_count: 2,
        }),
      ],
      "/p/brainstorming/1?round=21",
    );
    expect(wrapper.get("#brainstorming-tree-round-21").classes()).toContain("bg-accent");
    expect(wrapper.get("#brainstorming-tree-round-20").classes()).not.toContain("bg-accent");
    expect(wrapper.get("#brainstorming-tree-session-1").classes()).not.toContain("bg-accent");
    await wrapper.get("#brainstorming-tree-session-1 button").trigger("click");
    expect(wrapper.find("#brainstorming-tree-rounds-1").exists()).toBe(false);
    await wrapper.get("#brainstorming-tree-session-1 button").trigger("click");
    expect(wrapper.find("#brainstorming-tree-rounds-1").exists()).toBe(true);
  });

  it("keeps other sessions collapsed until opened", async () => {
    const wrapper = await sidebar(
      [
        session({ id: 1, rounds: [round({ id: 20 })], parked_count: 0 }),
        session({
          id: 2,
          title: "Later",
          rounds: [round({ id: 30, number: 1 }), round({ id: 31, number: 2 })],
          parked_count: 0,
        }),
      ],
      "/p/brainstorming/1",
    );
    expect(wrapper.find("#brainstorming-tree-rounds-2").exists()).toBe(false);
    await wrapper.get("#brainstorming-tree-session-2 button").trigger("click");
    expect(wrapper.findAll("#brainstorming-tree-rounds-2 a")).toHaveLength(2);
  });
});
