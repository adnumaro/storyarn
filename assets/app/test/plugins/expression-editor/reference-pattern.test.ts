import { describe, expect, it } from "vitest";
import {
  classifyReferencePattern,
  type ReferencePatternKind,
} from "@plugins/expression-editor/reference-pattern";

function expectReady(input: string, kind: ReferencePatternKind): void {
  expect(classifyReferencePattern(input)).toMatchObject({
    state: "ready",
    pattern: { raw: input, kind },
  });
}

describe("classifyReferencePattern", () => {
  it.each([
    ["mc.health", "exact"],
    ["mc.jaime.health", "exact"],
    ["2b.health", "exact"],
    ["23410.health", "exact"],
    ["story.character.stats.health", "exact"],
    ["sheets.**.health", "deep_wildcard"],
    ["sheets.**.?heal", "deep_wildcard_partial"],
    ["mc.?", "partial"],
    ["mc.jaime.?", "partial"],
    ["?heal", "partial"],
  ] as const)("accepts %s as a %s pattern", (input, kind) => {
    expectReady(input, kind);
  });

  it("returns typed segments without guessing the sheet/variable boundary", () => {
    expect(classifyReferencePattern("sheets.**.?heal")).toEqual({
      state: "ready",
      pattern: {
        raw: "sheets.**.?heal",
        kind: "deep_wildcard_partial",
        segments: [
          { kind: "identifier", value: "sheets" },
          { kind: "deep_wildcard" },
          { kind: "partial", value: "heal" },
        ],
      },
    });
  });

  it.each(["", "help", "go to", "mc", "health", "foo@bar.com"])(
    "keeps ordinary input %j in the guided door",
    (input) => {
      expect(classifyReferencePattern(input)).toEqual({ state: "normal" });
    },
  );

  it.each(["?", "mc.", "mc.jaime.", "sheets.**", "sheets.**.", "sheets.**.?"])(
    "keeps the pattern door active while %s is incomplete",
    (input) => {
      expect(classifyReferencePattern(input)).toEqual({ state: "incomplete", raw: input });
    },
  );

  it.each([
    "mc..health",
    "mc.*.health",
    "mc.***.health",
    "mc.**",
    "mc.**.health",
    "mc.**.**.health",
    "mc.?heal.more",
    "mc.jaime.?heal",
    "mc.health?",
    "mc.??heal",
    "mc.?he*",
    "mc . health",
    " mc.health",
    "mc.health ",
    "mc.health//comment",
    "mc.health/*comment*/",
    '"mc.health"',
    "'mc.health'",
    "`mc.health`",
    '"dialogue content"',
    "//mc.health",
    "/*mc.health*/",
    "? heal",
    "?heal.more",
    "sheets.characters.**.stats.health",
    "sheets.**.stats.health",
    "sheets.**.stats.?heal",
  ])("rejects malformed or reserved pattern input %j", (input) => {
    expect(classifyReferencePattern(input)).toEqual({ state: "invalid", raw: input });
  });

  it("does not accept a complete expression as a reference pattern", () => {
    expect(classifyReferencePattern("mc.health > 10")).toEqual({
      state: "invalid",
      raw: "mc.health > 10",
    });
  });
});
