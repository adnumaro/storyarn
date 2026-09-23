import { describe, expect, it } from "vitest";
import {
  deriveTitle,
  excerpt,
  orderTargets,
  primaryStatus,
  replaceable,
  roundTag,
  splitTargets,
} from "@app/live/ideation/decisionStatus";
import { accepted, decision, target } from "./decisionFixtures";

describe("decision status", () => {
  it("shows exactly one primary status, with to-apply standing for an accepted decision", () => {
    expect(primaryStatus(accepted())).toEqual({ kind: "toApply", pending: 1, total: 1 });
    expect(
      primaryStatus(
        accepted({ application: { targets: [], decision: null, pending: 0, total: 0 } }),
      ),
    ).toEqual({ kind: "accepted" });
    expect(primaryStatus(decision())).toEqual({ kind: "waitingForYou" });
    expect(primaryStatus(decision({ canAccept: false }))).toEqual({
      kind: "proposal",
      waitingFor: "Alex",
    });
    expect(primaryStatus(decision({ status: "withdrawn", withdrawnByName: "Noor" }))).toEqual({
      kind: "withdrawn",
      by: "Noor",
    });
    // A revision waiting over an agreement keeps the agreement's status.
    expect(primaryStatus(accepted({ status: "proposed", canAccept: true })).kind).toBe("toApply");
  });

  it("offers only decisions with an agreement in force as replacements, never the one being revised", () => {
    const items = [
      accepted({ id: 1 }),
      decision({ id: 2 }),
      accepted({ id: 3, status: "superseded" }),
      accepted({ id: 4, status: "proposed" }),
    ];
    expect(replaceable(items, 4).map((item) => item.id)).toEqual([1]);
  });

  it("puts what is still to apply first and folds more than three targets", () => {
    const applied = target({
      key: "a",
      application: { state: "applied", note: null, actorName: null, at: "" },
    });
    const pending = target({ key: "b" });
    const partial = target({
      key: "c",
      application: { state: "partially_applied", note: null, actorName: null, at: "" },
    });
    expect(orderTargets([applied, partial, pending], true).map((item) => item.key)).toEqual([
      "b",
      "c",
      "a",
    ]);
    expect(orderTargets([applied, pending], false).map((item) => item.key)).toEqual(["a", "b"]);
    const four = [pending, partial, applied, target({ key: "d" })];
    expect(splitTargets(four).visible).toHaveLength(2);
    expect(splitTargets(four).hidden).toHaveLength(2);
    expect(splitTargets(four.slice(0, 3)).hidden).toHaveLength(0);
  });

  it("derives a title from the first sentence and tags rounds only when there are several", () => {
    expect(deriveTitle("We ship the ending where Mara stays. The keeper leaves.")).toBe(
      "We ship the ending where Mara stays",
    );
    expect(deriveTitle("a".repeat(80))).toBe(`${"a".repeat(60)}…`);
    expect(excerpt("  The   keeper  ")).toBe("The keeper");
    expect(roundTag({ number: 2, prompt: null }, 2)).toBe("R2");
    expect(roundTag({ number: 1, prompt: null }, 1)).toBeNull();
  });
});
