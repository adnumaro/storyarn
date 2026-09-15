import { describe, expect, it } from "vitest";
import {
  NOTE_COLOR_IDS,
  noteColor,
  noteFill,
  noteInk,
  noteSwatch,
} from "@modules/ideation/lib/noteColors";

describe("note colours", () => {
  it("offers no colour first and treats anything unknown as no colour", () => {
    expect(NOTE_COLOR_IDS[0]).toBe("none");
    expect(noteColor(undefined)).toBe("none");
    expect(noteColor("chartreuse")).toBe("none");
    expect(noteColor("coral")).toBe("coral");
  });

  it("puts the colour on a card's surface and on a text-only note's words", () => {
    expect(noteFill("coral")).toBe("#f8cbbd");
    expect(noteInk("coral")).toBe("#c2410c");
    expect(noteSwatch("coral", "rectangle")).toBe("#f8cbbd");
    expect(noteSwatch("coral", "plain")).toBe("#c2410c");
  });

  it("keeps the default look with no colour: the yellow card, the theme's ink", () => {
    expect(noteFill("none")).toBe(noteFill("yellow"));
    expect(noteInk("none")).toBeNull();
    expect(noteSwatch("none", "plain")).toBeUndefined();
  });
});
