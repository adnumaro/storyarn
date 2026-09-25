import { describe, expect, it } from "vitest";
import {
  taskBasis,
  taskHost,
  taskParts,
  taskSummary,
  validTaskUrl,
} from "@app/live/ideation/decisionTask";
import addresses from "../../../../../test/fixtures/decision_task_urls.json";
import { accepted, decision, revision, source, target } from "./decisionFixtures";

const t = (key: string, values?: Record<string, unknown>) =>
  values ? `${key} ${JSON.stringify(values)}` : key;
const context = {
  t,
  origin: "https://storyarn.test",
  decisionUrl: "https://storyarn.test/brainstorming/3?decision=4",
};

describe("task addresses", () => {
  it("follows the address table shared with the server", () => {
    for (const url of addresses.valid) expect(validTaskUrl(url), url).toBe(true);
    for (const url of addresses.invalid) expect(validTaskUrl(url), url).toBe(false);
  });

  it("accepts web addresses and rejects other schemes, credentials and spaces", () => {
    expect(validTaskUrl("https://tracker.example.com/browse/ENG-1")).toBe(true);
    expect(validTaskUrl("  http://trello.com/c/abc  ")).toBe(true);
    for (const url of [
      "",
      "javascript:alert(1)",
      "ftp://files.example.com",
      "https://user:secret@tracker.example.com",
      "https://tracker example.com",
      "tracker.example.com/1",
      `https://example.com/${"a".repeat(2048)}`,
    ])
      expect(validTaskUrl(url), url).toBe(false);
  });

  it("names a task by its host when it has no title", () => {
    expect(taskHost("https://tracker.example.com/browse/ENG-1")).toBe("tracker.example.com");
  });
});

describe("preparing a task", () => {
  it("starts from the agreement in force and offers only the parts it has", () => {
    const pending = accepted({
      status: "proposed",
      proposal: revision({ revision: 3, title: "A newer proposal" }),
    });
    expect(taskBasis(pending).title).toBe("Take the forest path");
    expect(taskParts(revision({ reason: null, targets: [], sources: [] }))).toEqual(["conclusion"]);
  });

  it("copies only the chosen parts with links back to Storyarn and the affected content", () => {
    const record = accepted({
      accepted: revision({
        revision: 2,
        operation: "accept",
        nextAction: { text: "Write the forest scene", ownerId: 2, ownerName: "Noor" },
        targets: [
          target({ href: "/workspaces/w/projects/p/sheets/7" }),
          target({ key: "new", id: null, name: "Harbor", type: "scene", isNew: true }),
        ],
        sources: [
          source({ title: "Guarded road" }),
          source({ id: 11, title: "Hidden draft", available: false }),
        ],
      }),
    });
    const text = taskSummary(record, ["conclusion", "targets", "nextAction", "sources"], context);

    expect(text).toContain("Take the forest path");
    expect(text).toContain("brainstormingDecisions.tasks.summary.status.accepted");
    expect(text).toContain("The party avoids the road.");
    expect(text).not.toContain("It creates a difficult choice.");
    expect(text).toContain(
      "- Mara (brainstormingDecisions.targetTypes.sheet): https://storyarn.test/workspaces/w/projects/p/sheets/7",
    );
    expect(text).toContain(
      "- Harbor (brainstormingDecisions.targetTypes.scene, brainstormingDecisions.targetNew)",
    );
    expect(text).toContain("Write the forest scene (Noor)");
    expect(text).toContain("- Guarded road");
    expect(text).not.toContain("Hidden draft");
    expect(
      text.endsWith(
        "brainstormingDecisions.tasks.summary.link: https://storyarn.test/brainstorming/3?decision=4",
      ),
    ).toBe(true);
  });

  it("names the real state of the decision it copies", () => {
    const state = (record: Parameters<typeof taskSummary>[0]) =>
      taskSummary(record, ["conclusion"], context).split("\n")[1];

    expect(state(decision())).toContain("summary.status.proposed");
    expect(state(accepted())).toContain("summary.status.accepted");
    expect(state(accepted({ status: "proposed" }))).toContain("summary.status.revisionPending");
    expect(state(decision({ status: "withdrawn" }))).toContain("summary.status.withdrawn");
    expect(state(accepted({ status: "withdrawn" }))).toContain("summary.status.withdrawn");
    expect(
      state(accepted({ status: "superseded", supersededBy: { id: 9, title: "Mara leaves" } })),
    ).toBe(
      'brainstormingDecisions.verbs.change · brainstormingDecisions.tasks.summary.status.superseded {"title":"Mara leaves"}',
    );
  });
});
