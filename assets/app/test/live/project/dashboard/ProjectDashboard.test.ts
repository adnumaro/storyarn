import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import ProjectDashboard from "../../../../live/project/dashboard/ProjectDashboard.vue";
import { createMockLive } from "../../../setup";

const stats = {
  sheet_count: 4,
  variable_count: 12,
  flow_count: 3,
  dialogue_count: 40,
  scene_count: 2,
  total_word_count: 900,
};

type Counts = { error: number; warning: number; info: number; actionable: number };

function counts(error: number, warning: number, info: number): Counts {
  return { error, warning, info, actionable: error + warning };
}

function mountDashboard(overrides: Record<string, unknown> = {}) {
  const live = createMockLive();

  const wrapper = mount(ProjectDashboard, {
    props: {
      stats,
      activity: [],
      toolHealth: {
        flows: counts(2, 3, 7),
        sheets: counts(0, 0, 5),
        scenes: counts(0, 1, 0),
      },
      overviewStatus: "ready",
      issuesStatus: "ready",
      workspaceSlug: "ws",
      projectSlug: "story",
      ...overrides,
    },
    global: { provide: { _live_vue: live } },
  });

  return { wrapper, live };
}

describe("ProjectDashboard", () => {
  it("renders one health card per tool, linking to that tool's dashboard", () => {
    const { wrapper } = mountDashboard();

    for (const tool of ["flows", "sheets", "scenes"]) {
      const card = wrapper.find(`[data-testid="project-health-${tool}"]`);
      expect(card.exists()).toBe(true);
      expect(card.attributes("href")).toBe(`/workspaces/ws/projects/story/${tool}`);
    }
  });

  // The product rule: only errors and warnings are reported. `info` describes
  // valid content, so a tool carrying nothing else reads as up to date.
  it("reads as up to date when a tool has only info findings", () => {
    const { wrapper } = mountDashboard();

    const sheets = wrapper.find('[data-testid="project-health-sheets"]');
    expect(sheets.attributes("data-state")).toBe("clean");
    expect(sheets.text()).toContain("Up to date");
    // The 5 info findings must not be advertised as problems.
    expect(sheets.text()).not.toContain("5");
  });

  it("reports the actionable count and its error/warning breakdown", () => {
    const { wrapper } = mountDashboard();

    const flows = wrapper.find('[data-testid="project-health-flows"]');
    expect(flows.attributes("data-state")).toBe("error");
    // 2 errors + 3 warnings = 5 actionable; the 7 info findings are excluded.
    expect(flows.text()).toContain("5 issues to review");
    expect(flows.text()).toContain("2 errors");
    expect(flows.text()).toContain("3 warnings");
  });

  it("marks a warning-only tool as warning, not as an error", () => {
    const { wrapper } = mountDashboard();

    const scenes = wrapper.find('[data-testid="project-health-scenes"]');
    expect(scenes.attributes("data-state")).toBe("warning");
    expect(scenes.text()).toContain("1 issue to review");
    expect(scenes.text()).toContain("1 warning");
    expect(scenes.text()).not.toContain("error");
  });

  it("shows a spinner instead of empty cards while health is loading", () => {
    const { wrapper } = mountDashboard({ issuesStatus: "loading", toolHealth: null });

    expect(wrapper.find('[data-testid="project-health-loading"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="project-health-flows"]').exists()).toBe(false);
  });

  // A failed load used to present as a dashboard that never finishes loading.
  it("offers a retry when health fails, and pushes the retry event", async () => {
    const { wrapper, live } = mountDashboard({ issuesStatus: "error", toolHealth: null });

    const retry = wrapper.find('[data-testid="project-health-retry"]');
    expect(retry.exists()).toBe(true);

    await retry.trigger("click");
    expect(live.pushEvent).toHaveBeenCalledWith("retry_dashboard_issues", {}, undefined);
  });

  it("keeps the last counts visible when a refresh fails", () => {
    const { wrapper } = mountDashboard({ issuesStatus: "stale" });

    expect(wrapper.find('[data-testid="project-health-stale"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="project-health-flows"]').exists()).toBe(true);
  });

  it("renders the project totals", () => {
    const { wrapper } = mountDashboard();

    expect(wrapper.find('[data-testid="project-stat-sheets"]').text()).toContain("4");
    expect(wrapper.find('[data-testid="project-stat-words"]').text()).toContain("900");
  });

  // Recent activity is loaded by the OVERVIEW. Rendering its "no activity yet"
  // empty state next to an overview error told the reader the project had no
  // activity, when the truth was that nothing loaded.
  it("hides recent activity when the overview failed, instead of claiming there is none", () => {
    const { wrapper } = mountDashboard({
      overviewStatus: "error",
      stats: null,
      activity: [],
    });

    expect(wrapper.find('[data-testid="project-recent-activity"]').exists()).toBe(false);
    expect(wrapper.text()).not.toContain("No activity yet");
    // Health is a separate load, so it survives an overview failure.
    expect(wrapper.find('[data-testid="project-health-flows"]').exists()).toBe(true);
  });

  // Health is the actionable summary: it belongs directly under the totals, not
  // stranded below a ten-row activity list.
  it("orders the page totals -> health -> activity", () => {
    const { wrapper } = mountDashboard({
      activity: [{ type: "flow", name: "Opening", updated_at: "2026-07-26T12:00:00Z" }],
    });

    const html = wrapper.html();
    const totals = html.indexOf('data-testid="project-stat-sheets"');
    const health = html.indexOf('data-testid="project-tool-health"');
    const recent = html.indexOf('data-testid="project-recent-activity"');

    expect(totals).toBeGreaterThan(-1);
    expect(health).toBeGreaterThan(totals);
    expect(recent).toBeGreaterThan(health);
  });

  it("shows recent activity once the overview is ready", () => {
    const { wrapper } = mountDashboard({
      activity: [{ type: "flow", name: "Opening", updated_at: "2026-07-26T12:00:00Z" }],
    });

    const panel = wrapper.find('[data-testid="project-recent-activity"]');
    expect(panel.exists()).toBe(true);
    expect(panel.text()).toContain("Opening");
  });

  // An unmapped type must degrade to the raw string, not crash or render a stray
  // key. `screenplay` is the concrete case: the tool was removed in #59.
  it("degrades gracefully on an unknown activity type", () => {
    const { wrapper } = mountDashboard({
      activity: [{ type: "screenplay", name: "Ghost", updated_at: "2026-07-26T12:00:00Z" }],
    });

    const panel = wrapper.find('[data-testid="project-recent-activity"]');
    expect(panel.text()).toContain("Ghost");
    expect(panel.text()).not.toContain("Screenplay");
    expect(panel.text()).not.toContain("activity_types");
  });

  // Moved to the flows dashboard; the overview is a global context surface now.
  it("no longer renders flow-specific panels", () => {
    const { wrapper } = mountDashboard();
    const text = wrapper.text();

    expect(text).not.toContain("Node Distribution");
    expect(text).not.toContain("Top Speakers");
    expect(text).not.toContain("Localization Progress");
  });
});
