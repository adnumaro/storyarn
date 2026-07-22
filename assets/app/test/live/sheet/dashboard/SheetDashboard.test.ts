import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import SheetDashboard from "../../../../live/sheet/dashboard/SheetDashboard.vue";
import { createMockLive } from "../../../setup";

function mountDashboard() {
  const live = createMockLive();

  return mount(SheetDashboard, {
    props: {
      stats: {
        sheet_count: 1,
        block_count: 0,
        variable_count: 0,
        variables_in_use: 0,
        word_count: 0,
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
          code: "missing_sheet_shortcut",
          label: "Hero",
          href: "/workspaces/ws/projects/story/sheets/1",
        },
        {
          severity: "warning",
          code: "required_block_empty",
          label: "Hero · Biography",
          href: "/workspaces/ws/projects/story/sheets/1",
        },
        {
          severity: "info",
          code: "empty_leaf_sheet",
          label: "Empty Sheet",
          href: "/workspaces/ws/projects/story/sheets/2",
        },
      ],
      canEdit: false,
      workspaceSlug: "ws",
      projectSlug: "story",
    },
    global: {
      provide: {
        _live_vue: live,
      },
    },
  });
}

describe("SheetDashboard health", () => {
  it("renders canonical severities and the shared health translations", () => {
    const wrapper = mountDashboard();
    const error = wrapper.get('a[data-severity="error"]');
    const warning = wrapper.get('a[data-severity="warning"]');
    const info = wrapper.get('a[data-severity="info"]');

    expect(error.get('[data-testid="sheet-issue-error-icon"]').classes()).toContain("text-red-500");
    expect(warning.get('[data-testid="sheet-issue-warning-icon"]').classes()).toContain(
      "text-yellow-500",
    );
    expect(info.get('[data-testid="sheet-issue-info-icon"]').classes()).toContain("text-blue-400");

    expect(error.text()).toContain("Hero · The sheet has no shortcut");
    expect(warning.text()).toContain("Hero · Biography · This required block is empty");
    expect(info.text()).toContain("Empty Sheet · The sheet has no blocks or child sheets");
  });
});
