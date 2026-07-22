import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import SceneDashboard from "../../../../live/scene/dashboard/SceneDashboard.vue";
import { createMockLive } from "../../../setup";

function mountDashboard() {
  const live = createMockLive();

  return mount(SceneDashboard, {
    props: {
      stats: {
        scene_count: 1,
        zone_count: 0,
        pin_count: 0,
        background_count: 0,
      },
      tableData: [],
      pagination: {
        sortBy: "name",
        sortDir: "asc",
        page: 1,
        totalPages: 1,
        total: 1,
      },
      issues: [
        {
          severity: "error",
          code: "invalid_connection_endpoint",
          label: "World · Road",
          href: "/workspaces/ws/projects/story/scenes/1?highlight=connection:4",
        },
        {
          severity: "warning",
          code: "missing_background",
          label: "World",
          href: "/workspaces/ws/projects/story/scenes/1",
        },
        {
          severity: "info",
          code: "empty_scene",
          label: "Empty World",
          href: "/workspaces/ws/projects/story/scenes/2",
        },
      ],
      canEdit: false,
      workspaceSlug: "ws",
      projectSlug: "story",
    },
    global: {
      provide: { _live_vue: live },
    },
  });
}

describe("SceneDashboard health", () => {
  it("renders canonical severities, translations, and deep links", () => {
    const wrapper = mountDashboard();
    const error = wrapper.get('a[data-severity="error"]');
    const warning = wrapper.get('a[data-severity="warning"]');
    const info = wrapper.get('a[data-severity="info"]');

    expect(error.get('[data-testid="scene-issue-error-icon"]').classes()).toContain("text-red-500");
    expect(warning.get('[data-testid="scene-issue-warning-icon"]').classes()).toContain(
      "text-yellow-500",
    );
    expect(info.get('[data-testid="scene-issue-info-icon"]').classes()).toContain("text-blue-400");

    expect(error.text()).toContain("World · Road · The connection has an invalid endpoint");
    expect(warning.text()).toContain("World · The scene has no background image");
    expect(info.text()).toContain("Empty World · The scene has no zones or pins");
    expect(error.attributes("href")).toContain("highlight=connection:4");
  });
});
