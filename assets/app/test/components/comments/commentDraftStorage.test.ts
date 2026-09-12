import { beforeEach, describe, expect, it } from "vitest";
import { readCommentDraft, updateCommentDraft } from "@components/comments/commentDraftStorage";

const key = "storyarn:sheet-comment-draft:4:7";

beforeEach(() => window.sessionStorage.clear());

describe("contextual comment draft recovery", () => {
  it("keeps signed canvas coordinates and context when the composer writes text", () => {
    const flowKey = "storyarn:flow-comment-draft:4:flow-canvas-7";
    const context = { type: "flow_node", id: "42", offset: { x: 10, y: -20 } };
    updateCommentDraft(flowKey, {
      coordinateSpace: "canvas",
      position: { x: -1200, y: 840 },
      context,
    });
    updateCommentDraft(flowKey, { body: "Review this intervention" });
    expect(readCommentDraft(flowKey)).toEqual({
      coordinateSpace: "canvas",
      position: { x: -1200, y: 840 },
      context,
      body: "Review this intervention",
    });
    expect(readCommentDraft(key)).toBeNull();
  });

  it("rejects out-of-range canvas positions while keeping text and existing Sheet bounds", () => {
    updateCommentDraft(key, {
      coordinateSpace: "canvas",
      position: { x: 10_000_001, y: 0 },
      body: "Keep",
    });
    expect(readCommentDraft(key)).toEqual({ coordinateSpace: "canvas", body: "Keep" });
    window.sessionStorage.setItem(
      key,
      JSON.stringify({ position: { x: -5, y: 2 }, body: "Sheet" }),
    );
    expect(readCommentDraft(key)).toEqual({ body: "Sheet" });
  });

  it("preserves context while the composer updates text, and records explicit free placement", () => {
    const context = { type: "sheet_title", id: "7", offset: { x: -2, y: 18 } };
    updateCommentDraft(key, { position: { x: 40, y: 320 }, context });
    updateCommentDraft(key, { body: "Review this name", mentionIds: [4] });
    expect(readCommentDraft(key)).toEqual({
      position: { x: 40, y: 320 },
      context,
      body: "Review this name",
      mentionIds: [4],
    });
    updateCommentDraft(key, { position: { x: 15, y: 720 }, context: null });
    expect(readCommentDraft(key)).toMatchObject({ context: null, body: "Review this name" });
    expect(readCommentDraft("storyarn:sheet-comment-draft:4:8")).toBeNull();
  });

  it("recovers old drafts without context", () => {
    window.sessionStorage.setItem(
      key,
      JSON.stringify({ position: { x: 20, y: 90 }, body: "Saved before magnetism" }),
    );
    expect(readCommentDraft(key)).toEqual({
      position: { x: 20, y: 90 },
      body: "Saved before magnetism",
    });
  });

  it.each([
    { type: "sheet_block", id: "9", offset: { x: "bad", y: 1 } },
    { type: "sheet_column_group", id: "9", offset: { x: 1, y: 10_000_001 } },
    { type: "sheet_title", id: 7 },
  ])("discards invalid context without discarding the draft text", (context) => {
    window.sessionStorage.setItem(key, JSON.stringify({ context, body: "Keep my feedback" }));
    expect(readCommentDraft(key)).toEqual({ body: "Keep my feedback" });
  });
});
