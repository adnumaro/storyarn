import { mount } from "@vue/test-utils";
import { afterEach, describe, expect, it } from "vitest";
import { isAIPaletteCommand } from "@shared/command-palette/aiCommands";
import { paletteGroups } from "@shared/command-palette/registry";
import FlowAnalysisPanel from "@modules/flows/editor/components/panels/FlowAnalysisPanel.vue";
import type { AnalysisFinding } from "@modules/flows/editor/components/panels/flowAnalysisTypes.ts";
import { createMockLive } from "@app/test/setup.ts";

const REASON_CODES = [
  "intentional_design",
  "rule_not_applicable",
  "missing_context",
  "incorrect_detection",
  "duplicate_finding",
  "other",
];

function finding(overrides: Partial<AnalysisFinding> = {}): AnalysisFinding {
  return {
    findingId: "sf1_abc",
    findingKey: "no_outgoing_connection:1:node:42",
    ruleId: "no_outgoing_connection",
    ruleVersion: 1,
    category: "structure",
    severity: "warning",
    targetType: "node",
    targetId: 42,
    nodeType: "dialogue",
    pins: [],
    count: null,
    hubId: null,
    evidence: [{ type: "flow_node", id: 42 }],
    ...overrides,
  };
}

function mountPanel(props: Record<string, unknown> = {}) {
  const live = createMockLive();
  const wrapper = mount(FlowAnalysisPanel, {
    props: {
      open: true,
      canEdit: true,
      stale: false,
      computedAt: "2026-07-24T12:00:00Z",
      reasonCodes: REASON_CODES,
      maxNoteLength: 2000,
      active: [finding()],
      dismissed: [],
      ...props,
    },
    global: {
      provide: { _live_vue: live },
      stubs: {
        Sidebar: { template: "<div><slot name='header' /><slot /></div>" },
        teleport: true,
      },
    },
  });
  return { live, wrapper };
}

describe("FlowAnalysisPanel", () => {
  it("lists active findings with rule label and target", () => {
    const { wrapper } = mountPanel();

    const row = wrapper.get('[data-testid="analysis-finding"]');
    expect(row.text()).toContain("Node has no outgoing connection");
    expect(row.text()).toContain("#42");
  });

  it("shows the stale banner and reruns from it", async () => {
    const { live, wrapper } = mountPanel({ stale: true });

    const banner = wrapper.get('[data-testid="analysis-stale-banner"]');
    await banner.get("button").trigger("click");

    expect(live.pushEvent).toHaveBeenCalledWith("rerun_analysis", {}, undefined);
  });

  it("filters by category", async () => {
    const { wrapper } = mountPanel({
      active: [
        finding(),
        finding({
          findingId: "sf1_ref",
          ruleId: "stale_jump_target",
          category: "reference_integrity",
          severity: "error",
          nodeType: "jump",
          targetId: 7,
        }),
      ],
    });

    expect(wrapper.findAll('[data-testid="analysis-finding"]')).toHaveLength(2);

    const referencesFilter = wrapper.findAll("button").find((b) => b.text() === "References");
    await referencesFilter!.trigger("click");

    const rows = wrapper.findAll('[data-testid="analysis-finding"]');
    expect(rows).toHaveLength(1);
    expect(rows[0].text()).toContain("Jump targets a missing hub");
  });

  it("dismiss flow requires a reason and sends the disposition", async () => {
    const { live, wrapper } = mountPanel();

    await wrapper.get('[data-testid="analysis-finding"]').trigger("click");
    await wrapper.get('[data-testid="analysis-dismiss"]').trigger("click");

    const confirm = wrapper.get('[data-testid="analysis-dismiss-confirm"]');
    expect(confirm.attributes("disabled")).toBeDefined();

    const reasonLabel = wrapper
      .findAll("label")
      .find((l) => l.text().includes("Intentional design"));
    await reasonLabel!.get("button, [role=radio]").trigger("click");
    await confirm.trigger("click");

    expect(live.pushEvent).toHaveBeenCalledWith(
      "dismiss_finding",
      { finding_id: "sf1_abc", reason_code: "intentional_design", note: "" },
      undefined,
    );
  });

  it("viewer sees findings without disposition actions", async () => {
    const { wrapper } = mountPanel({ canEdit: false });

    await wrapper.get('[data-testid="analysis-finding"]').trigger("click");

    expect(wrapper.find('[data-testid="analysis-dismiss"]').exists()).toBe(false);
  });

  it("dismissed tab shows dismissal metadata and restore", async () => {
    const { live, wrapper } = mountPanel({
      active: [],
      dismissed: [
        finding({
          dismissalId: 9,
          reasonCode: "intentional_design",
          note: "kept on purpose",
          dismissedBy: "owner@example.com",
          dismissedAt: "2026-07-24T11:00:00Z",
        }),
      ],
    });

    await wrapper.get('[data-testid="analysis-tab-dismissed"]').trigger("click");
    const row = wrapper.get('[data-testid="analysis-dismissed-finding"]');
    await row.trigger("click");

    expect(wrapper.text()).toContain("owner@example.com");
    expect(wrapper.text()).toContain("kept on purpose");

    await wrapper.get('[data-testid="analysis-restore"]').trigger("click");
    expect(live.pushEvent).toHaveBeenCalledWith(
      "restore_finding_dismissal",
      { dismissal_id: 9 },
      undefined,
    );
  });

  it("navigates evidence through the server event", async () => {
    const { live, wrapper } = mountPanel();

    await wrapper.get('[data-testid="analysis-finding"]').trigger("click");
    await wrapper.get('[data-testid="analysis-evidence-navigate"]').trigger("click");

    expect(live.pushEvent).toHaveBeenCalledWith(
      "analysis_navigate_evidence",
      { type: "flow_node", id: 42 },
      undefined,
    );
  });

  it("shows the empty state when there are no findings", () => {
    const { wrapper } = mountPanel({ active: [] });

    expect(wrapper.get('[data-testid="analysis-empty"]').text()).toContain("No active findings");
  });

  describe("AI palette command", () => {
    const explanationState = {
      available: true,
      findingId: null,
      findingKey: null,
      status: "idle" as const,
      error: null,
      stale: false,
      routes: [],
      blockedLanes: [],
      disclosure: null,
      result: null,
    };

    function explainCommands() {
      return paletteGroups.value
        .flatMap((group) => group.commands)
        .filter((command) => command.id === "flows.explain_finding");
    }

    afterEach(() => {
      wrappers.forEach((wrapper) => wrapper.unmount());
      wrappers.length = 0;
    });

    const wrappers: ReturnType<typeof mountPanel>["wrapper"][] = [];

    it("is hidden while no finding is selected", () => {
      const { wrapper } = mountPanel({ explanation: explanationState });
      wrappers.push(wrapper);

      expect(explainCommands()).toHaveLength(0);
    });

    it("appears for the expanded finding and disappears when it collapses", async () => {
      const { wrapper } = mountPanel({ explanation: explanationState });
      wrappers.push(wrapper);

      await wrapper.find("[data-testid='analysis-finding']").trigger("click");
      expect(explainCommands()).toHaveLength(1);

      await wrapper.find("[data-testid='analysis-finding']").trigger("click");
      expect(explainCommands()).toHaveLength(0);
    });

    it("stays hidden while the snapshot is stale", async () => {
      // Every occurrence id is provisional until the analysis is recomputed, so
      // the command would launch straight into a refusal.
      const { wrapper } = mountPanel({ stale: true, explanation: explanationState });
      wrappers.push(wrapper);

      const card = wrapper.find("[data-testid='analysis-finding']");
      expect(card.exists()).toBe(true);
      await card.trigger("click");

      expect(explainCommands()).toHaveLength(0);
    });

    it("stays hidden for a dismissed finding", async () => {
      // Expanding a card in the dismissed tab also sets the selection, but a
      // dismissed occurrence is not in the active set the server resolves against.
      const { wrapper } = mountPanel({
        active: [],
        dismissed: [finding({ dismissalId: 7, reasonCode: "other" })],
        explanation: explanationState,
      });
      wrappers.push(wrapper);

      await wrapper.find("[data-testid='analysis-tab-dismissed']").trigger("click");
      const card = wrapper.find("[data-testid='analysis-dismissed-finding']");
      expect(card.exists()).toBe(true);
      await card.trigger("click");

      expect(explainCommands()).toHaveLength(0);
    });

    it("stays hidden when the actor cannot use AI", async () => {
      const { wrapper } = mountPanel({
        explanation: { ...explanationState, available: false },
      });
      wrappers.push(wrapper);

      await wrapper.find("[data-testid='analysis-finding']").trigger("click");

      expect(explainCommands()).toHaveLength(0);
    });

    it("launches the panel preflight for the selected finding", async () => {
      const { live, wrapper } = mountPanel({ explanation: explanationState });
      wrappers.push(wrapper);

      await wrapper.find("[data-testid='analysis-finding']").trigger("click");
      const [command] = explainCommands();

      // Narrowing through the exported guard is also the assertion that the
      // command registers as an AI command and not as an ordinary one.
      expect(isAIPaletteCommand(command)).toBe(true);
      if (!isAIPaletteCommand(command) || command.mode !== "launch") {
        throw new Error("expected an AI launch command");
      }

      // Cost is disclosed by the panel, never by the palette.
      expect(command.cost).toEqual({ kind: "deferred_to_preflight" });

      await command.launch();

      // The useLive wrapper consumes the onError callback, so the raw mock
      // sees three arguments.
      expect(live.pushEvent).toHaveBeenCalledWith(
        "open_explanation",
        { finding_id: "sf1_abc" },
        undefined,
      );
    });
  });
});
