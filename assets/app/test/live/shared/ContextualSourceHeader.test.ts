import { describe, expect, it, vi } from "vitest";
import { mount } from "@vue/test-utils";
import Header from "@app/live/shared/ContextualSourceHeader.vue";
import type { ExplorationLauncherState } from "@app/live/ideation/explorationTypes";

type HeaderProps = InstanceType<typeof Header>["$props"]["header"];
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
  canEdit: true,
  error: null,
};
const cases: Array<{
  sourceType: "sheet" | "flow" | "scene";
  header: HeaderProps;
}> = [
  { sourceType: "sheet", header: { health, comments } },
  {
    sourceType: "flow",
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
    sourceType: "scene",
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
        props: {
          sourceType,
          header,
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
