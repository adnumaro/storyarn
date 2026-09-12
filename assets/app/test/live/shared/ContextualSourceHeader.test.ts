import { describe, expect, it, vi } from "vitest";
import { mount } from "@vue/test-utils";
import Header from "@app/live/shared/ContextualSourceHeader.vue";
import type { ExplorationLauncherState } from "@app/live/ideation/explorationTypes";

const health = { errorItems: [], warningItems: [], infoItems: [] };
const comments = { count: 2, open: false, canComment: true };
const explorations: ExplorationLauncherState = {
  open: false,
  context: "source-preview",
  target: null,
  linked: [],
  available: [],
  linkedNext: null,
  availableNext: null,
  linkedPrevious: false,
  availablePrevious: false,
  linkedCursor: null,
  availableCursor: null,
  canEdit: true,
  error: null,
};
const cases = [
  { sourceType: "sheet" as const, header: { health, comments } },
  {
    sourceType: "flow" as const,
    header: {
      flowName: "A long opening flow title",
      flowShortcut: "opening",
      isMain: true,
      canEdit: true,
      saveStatus: "idle",
      navHistory: { back: null, forward: null },
      flowHealth: { wordCount: 330, health },
      sceneSelected: { name: null, inherited: false },
      projectScenes: [],
      comments,
    },
  },
  {
    sourceType: "scene" as const,
    header: {
      header: {
        toolbar: { canEdit: true, sceneName: "A long forest scene title", sceneShortcut: "forest" },
        search: { searchQuery: "", searchFilter: "all", searchResults: [] },
        health,
        comments,
      },
    },
  },
];

describe("Contextual source header composition", () => {
  it.each(cases)(
    "retains $sourceType controls alongside the compact exploration action",
    async ({ sourceType, header }) => {
      const pushEvent = vi.fn();
      const wrapper = mount(Header, {
        attrs: { ...header, "data-header-probe": sourceType },
        props: {
          sourceType,
          explorationState: explorations,
          explorationSourceKey: `${sourceType}:8`,
        },
        global: {
          provide: {
            _live_vue: {
              pushEvent,
              handleEvent: vi.fn(),
              removeHandleEvent: vi.fn(),
              upload: vi.fn(),
            },
          },
        },
      });
      expect(wrapper.attributes("data-header-probe")).toBeUndefined();
      expect(wrapper.find(`[data-header-probe="${sourceType}"]`).exists()).toBe(true);
      const toggle = wrapper.get(`#${sourceType}-comments-toggle`);
      expect(wrapper.find(`#${sourceType}-comments-create-mode`).exists()).toBe(true);
      if (sourceType === "flow") expect(wrapper.text()).toContain("A long opening flow title");
      if (sourceType === "scene") expect(wrapper.text()).toContain("A long forest scene title");
      const launcher = wrapper.get("#explore-changes");
      expect(launcher.attributes("aria-label")).toBe("Explore changes");
      expect(launcher.attributes("title")).toBe("Explore changes");
      expect(launcher.attributes("data-size")).toBe("icon-sm");
      await toggle.trigger("click");
      expect(pushEvent.mock.calls[0][0]).toBe("comments_open");
      await launcher.trigger("click");
      expect(pushEvent.mock.calls[1][0]).toBe("exploration_open");
      expect(pushEvent.mock.calls[1][1]).toMatchObject({
        source_key: `${sourceType}:8`,
        exploration_context: "source-preview",
      });
      expect(wrapper.find(`#${sourceType}-comments-toggle`).exists()).toBe(true);
      wrapper.unmount();
    },
  );
});
