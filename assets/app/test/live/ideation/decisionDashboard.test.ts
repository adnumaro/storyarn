import { describe, expect, it } from "vitest";
import {
  dashboardDecisions,
  groupByTarget,
  sessionSummary,
  type DecisionSessionGroup,
} from "@app/live/ideation/decisionDashboard";
import { accepted, decision, revision, target } from "./decisionFixtures";

const applied = accepted({
  id: 1,
  application: {
    targets: [
      { ...target(), application: { state: "applied", note: null, actorName: null, at: "" } },
    ],
    decision: null,
    pending: 0,
    total: 1,
  },
});
const pending = accepted({ id: 2 });
const waiting = decision({ id: 3 });
const withdrawn = decision({ id: 4, status: "withdrawn", canAccept: false });
const other = accepted({
  id: 5,
  proposal: revision({ targets: [target({ key: "flow", type: "flow", id: 9, name: "Act 3" })] }),
});
other.accepted = other.proposal;
other.application = { targets: other.proposal.targets, decision: null, pending: 1, total: 1 };

// A revision waits while the agreement in force still has something to apply.
const revising = accepted({
  id: 6,
  status: "proposed",
  proposal: revision({
    revision: 3,
    operation: "revise",
    targets: [target({ key: "keeper", id: 8, name: "The keeper" })],
  }),
});
revising.accepted = revision({
  revision: 2,
  operation: "accept",
  targets: [target({ key: "keeper", id: 8, name: "The keeper" })],
});
revising.application = { targets: revising.accepted.targets, decision: null, pending: 1, total: 1 };

const groups: DecisionSessionGroup[] = [
  {
    id: 10,
    title: "Endings",
    status: "open",
    roundCount: 2,
    decisions: [applied, pending, waiting, withdrawn, revising],
  },
  { id: 11, title: "Act 3", status: "open", roundCount: 1, decisions: [other] },
];

describe("the decisions dashboard", () => {
  it("summarizes a session", () => {
    expect(sessionSummary(groups[0].decisions)).toEqual({ total: 5, waiting: 1, toApply: 2 });
  });

  it("orders by what to do first and keeps retired apart, with their session", () => {
    const { live, retired } = dashboardDecisions(groups, "all", "all");
    expect(live.map((item) => item.decision.id)).toEqual([3, 2, 6, 5, 1]);
    expect(live[0].sessionTitle).toBe("Endings");
    expect(retired.map((item) => item.decision.id)).toEqual([4]);
  });

  it("filters by status and application", () => {
    // A pending revision is a proposal too, even with an agreement in force.
    expect(dashboardDecisions(groups, "proposed", "all").live.map((i) => i.decision.id)).toEqual([
      3, 6,
    ]);
    expect(dashboardDecisions(groups, "all", "toApply").live.map((i) => i.decision.id)).toEqual([
      2, 6, 5,
    ]);
    expect(dashboardDecisions(groups, "all", "applied").live.map((i) => i.decision.id)).toEqual([
      1,
    ]);
    expect(dashboardDecisions(groups, "retired", "all").retired.map((i) => i.decision.id)).toEqual([
      4,
    ]);
  });

  it("groups by affected content, counting what is still to apply there", () => {
    const { live } = dashboardDecisions(groups, "all", "all");
    const grouped = groupByTarget(live);
    expect(grouped.map((group) => [group.name, group.items.length, group.toApply])).toEqual([
      ["Act 3", 1, 1],
      ["Mara", 3, 1],
      ["The keeper", 1, 1],
    ]);
  });
});
