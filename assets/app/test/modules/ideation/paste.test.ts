import { describe, expect, it } from "vitest";
import { pasteContent, sameBody } from "@modules/ideation/lib/paste";

describe("body comparison across server serialization", () => {
  it("treats the server echo of the same document as equal", () => {
    const typed = '<p>He said "hi"&nbsp;now<br>x &amp; y</p>';
    const stored = "<p>He said &quot;hi&quot;\u00A0now<br/>x &amp; y</p>";
    expect(typed).not.toBe(stored);
    expect(sameBody(typed, stored)).toBe(true);
    expect(
      sameBody(
        "<p><strong>bold</strong> <em>and</em></p>",
        "<p><strong>bold</strong> <em>and</em></p>",
      ),
    ).toBe(true);
  });
  it("still tells real edits apart", () => {
    expect(sameBody("<p>Start</p>", "<p>Start.</p>")).toBe(false);
    expect(
      sameBody(
        "<p><strong>bold</strong> <em>and</em></p>",
        "<p><strong>bold</strong><em>and</em></p>",
      ),
    ).toBe(false);
    expect(sameBody("<p>a</p>", "<p><em>a</em></p>")).toBe(false);
  });
  it("keeps pasteContent inert while comparing", () => {
    expect(pasteContent('<p style="color:red">x</p>')).toBe("<p>x</p>");
  });
});
