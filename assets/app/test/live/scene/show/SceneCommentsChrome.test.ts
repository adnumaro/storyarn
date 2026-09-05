import { mount } from "@vue/test-utils";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { createMockLive } from "@app/test/setup";
import type { SceneCommentsPanelState } from "@modules/scenes/types/comments";

const live = createMockLive();
vi.mock("@shared/composables/useLive", () => ({ useLive: () => live }));
const { default: SceneHeader } = await import("@app/live/scene/show/SceneHeader.vue");
const { default: ScenePanels } = await import("@app/live/scene/show/ScenePanels.vue");
const { default: SceneCommentsPanel } =
  await import("@modules/scenes/editor/components/panels/SceneCommentsPanel.vue");

const comments: SceneCommentsPanelState = {
  open: true,
  presentation: "panel",
  placing: false,
  draftPosition: null,
  draftId: null,
  threads: [],
  nextCursor: null,
  thread: null,
  messages: [],
  messageNextCursor: null,
  members: [],
  canComment: true,
  statusFilter: "open",
  error: null,
};
const passthrough = { template: "<div><slot /></div>" };

beforeEach(() => vi.mocked(live.pushEvent).mockClear());

describe("Scene comments chrome wiring", () => {
  it("exposes the scene header count, placement mode, and viewer-safe panel toggle", async () => {
    const wrapper = mount(SceneHeader, {
      props: {
        header: {
          toolbar: { canEdit: true, sceneName: "Courtyard", sceneShortcut: "C" },
          search: { searchQuery: "", searchFilter: "all", searchResults: [] },
          health: { errorItems: [], warningItems: [], infoItems: [] },
          comments: { count: 2, open: false, placing: false, canComment: true },
        },
      },
      global: {
        stubs: {
          SceneToolbar: true,
          SearchPanel: true,
          SceneHealthStatus: true,
          ToolbarTooltip: passthrough,
        },
      },
    });

    expect(wrapper.get("#scene-comments-toggle").text()).toContain("2");
    await wrapper.get("#scene-comments-create-mode").trigger("click");
    expect(live.pushEvent).toHaveBeenLastCalledWith("comments_mode", { active: true });
    await wrapper.get("#scene-comments-toggle").trigger("click");
    expect(live.pushEvent).toHaveBeenLastCalledWith("comments_open", {});

    await wrapper.setProps({
      header: {
        toolbar: { canEdit: false, sceneName: "Courtyard", sceneShortcut: "C" },
        search: { searchQuery: "", searchFilter: "all", searchResults: [] },
        health: { errorItems: [], warningItems: [], infoItems: [] },
        comments: { count: 2, open: true, placing: false, canComment: false },
      },
    });
    expect(wrapper.find("#scene-comments-create-mode").exists()).toBe(false);
    expect(wrapper.get("#scene-comments-toggle").attributes("aria-expanded")).toBe("true");
    await wrapper.get("#scene-comments-toggle").trigger("click");
    expect(live.pushEvent).toHaveBeenLastCalledWith("comments_close", {});
  });

  it("gives a docked comment panel priority without hiding canvas conversations", async () => {
    const wrapper = mount(ScenePanels, {
      props: {
        panels: {
          comments,
          versions: {
            open: true,
            versions: [],
            namedVersions: [],
            autoVersions: [],
            hasMore: false,
            canNameVersion: true,
            currentVersionId: null,
            canEdit: true,
            restoreEnabled: true,
            loading: false,
          },
          element: {
            selectedType: "pin",
            selectedElement: { id: 1 },
            canEdit: true,
            elementPanelOpen: true,
            projectSheets: [],
            projectFlows: [],
            projectScenes: [],
            projectVariables: [],
          },
          settings: {
            scene: { id: 7 },
            canEdit: true,
            ambientFlows: [],
            projectFlows: [],
            sceneSettingsOpen: true,
          },
        },
      },
      global: {
        stubs: {
          SceneCommentsPanel: {
            props: ["state"],
            template: '<section data-testid="comments-panel" />',
          },
          VersionHistoryPanel: {
            props: ["open"],
            template: '<section data-testid="versions-panel" :data-open="String(open)" />',
          },
          ElementPropertiesPanel: {
            props: ["elementPanelOpen"],
            template:
              '<section data-testid="element-panel" :data-open="String(elementPanelOpen)" />',
          },
          SettingsPanel: {
            props: ["sceneSettingsOpen"],
            template:
              '<section data-testid="settings-panel" :data-open="String(sceneSettingsOpen)" />',
          },
        },
      },
    });

    expect(wrapper.find('[data-testid="comments-panel"]').exists()).toBe(true);
    expect(wrapper.get('[data-testid="versions-panel"]').attributes("data-open")).toBe("false");
    expect(wrapper.get('[data-testid="element-panel"]').attributes("data-open")).toBe("false");
    expect(wrapper.get('[data-testid="settings-panel"]').attributes("data-open")).toBe("false");

    await wrapper.setProps({
      panels: {
        ...wrapper.props("panels"),
        comments: { ...comments, presentation: "canvas" },
      },
    });
    expect(wrapper.get('[data-testid="versions-panel"]').attributes("data-open")).toBe("true");
    expect(wrapper.get('[data-testid="element-panel"]').attributes("data-open")).toBe("true");
    expect(wrapper.get('[data-testid="settings-panel"]').attributes("data-open")).toBe("true");
  });

  it("creates a scene-canvas thread with percentage coordinates and no entity anchor", async () => {
    const position = { x: 20, y: 30 };
    const wrapper = mount(SceneCommentsPanel, {
      props: {
        embedded: true,
        state: {
          ...comments,
          presentation: "canvas",
          draftPosition: position,
          draftId: "scene-draft",
        },
      },
      global: {
        stubs: {
          Sidebar: {
            template: "<aside><slot name='header'/><slot/><slot name='footer'/></aside>",
          },
          Popover: passthrough,
          PopoverContent: passthrough,
          PopoverTrigger: passthrough,
        },
      },
    });

    await wrapper.get("#scene-comment-body").setValue("Check this encounter beat.");
    await wrapper.get("form").trigger("submit");
    const payload = vi.mocked(live.pushEvent).mock.calls.at(-1)?.[1];
    expect(live.pushEvent).toHaveBeenCalledWith(
      "comments_create",
      expect.objectContaining({ body: "Check this encounter beat.", position }),
      expect.any(Function),
      expect.any(Function),
    );
    expect(payload).not.toHaveProperty("node_id");
    expect(wrapper.find("#scene-comment-send").exists()).toBe(true);
  });

  it("renders a replacement comments state received after mount", async () => {
    const wrapper = mount(SceneCommentsPanel, {
      props: { embedded: true, state: comments },
      global: {
        stubs: {
          Sidebar: {
            template: "<aside><slot name='header'/><slot/><slot name='footer'/></aside>",
          },
          Popover: passthrough,
          PopoverContent: passthrough,
          PopoverTrigger: passthrough,
        },
      },
    });

    expect(wrapper.find('[role="alert"]').exists()).toBe(false);

    await wrapper.setProps({
      state: { ...comments, error: "Latest comments state" },
    });

    expect(wrapper.get('[role="alert"]').text()).toBe("Latest comments state");
  });
});
