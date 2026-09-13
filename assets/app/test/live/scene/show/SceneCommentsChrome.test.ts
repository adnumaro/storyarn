import { mount } from "@vue/test-utils";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { createMockLive } from "@app/test/setup";
import type { SceneCommentsPanelState } from "@modules/scenes/types/comments";

const live = createMockLive();
vi.mock("@shared/composables/useLive", () => ({ useLive: () => live }));
const { default: SceneHeader } = await import("@app/live/scene/show/SceneHeader.vue");
const { default: ScenePanels } = await import("@app/live/scene/show/ScenePanels.vue");
const { default: SceneCommentPopover } =
  await import("@modules/scenes/editor/components/panels/SceneCommentPopover.vue");

const comments: SceneCommentsPanelState = {
  open: true,
  presentation: "canvas",
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
  it("keeps the Scene header free of comment controls", () => {
    const wrapper = mount(SceneHeader, {
      props: {
        header: {
          toolbar: { canEdit: true, sceneName: "Courtyard", sceneShortcut: "C" },
          search: { searchQuery: "", searchFilter: "all", searchResults: [] },
          health: { errorItems: [], warningItems: [], infoItems: [] },
        },
      },
      global: { stubs: { SceneToolbar: true, SearchPanel: true, SceneHealthStatus: true } },
    });
    expect(wrapper.find("#scene-comments-toggle").exists()).toBe(false);
    expect(wrapper.find("#scene-comments-create-mode").exists()).toBe(false);
  });

  it("keeps editor panels available without a comments sidebar", async () => {
    const wrapper = mount(ScenePanels, {
      props: {
        panels: {
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
          SceneCommentPopover: {
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

    expect(wrapper.find('[data-testid="comments-panel"]').exists()).toBe(false);
    expect(wrapper.get('[data-testid="versions-panel"]').attributes("data-open")).toBe("true");
    expect(wrapper.get('[data-testid="element-panel"]').attributes("data-open")).toBe("true");
    expect(wrapper.get('[data-testid="settings-panel"]').attributes("data-open")).toBe("true");
  });

  it("creates a scene-canvas thread with percentage coordinates and no entity anchor", async () => {
    const position = { x: 20, y: 30 };
    const wrapper = mount(SceneCommentPopover, {
      props: {
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
    const wrapper = mount(SceneCommentPopover, {
      props: { state: comments },
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
