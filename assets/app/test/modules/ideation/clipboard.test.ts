import { describe, expect, it } from "vitest";
import { readNotes, writeNotes } from "@modules/ideation/lib/clipboard";
import { idea } from "./fixtures";

const mime = "application/x-storyarn-brainstorming+json";
function clipboard(contents: { [format: string]: string } = {}) {
  const data = new Map(Object.entries(contents));
  const event = new Event("copy", { cancelable: true }) as ClipboardEvent;
  Object.defineProperty(event, "clipboardData", {
    value: {
      getData: (format: string) => data.get(format) ?? "",
      setData: (format: string, value: string) => data.set(format, value),
    },
  });
  return { event, data };
}
describe("canvas clipboard", () => {
  it("remaps connection styles only within the copied selection", () => {
    const { event, data } = clipboard();
    writeNotes(event, [
      idea({
        id: 813,
        canvas: { links: [814, 999], link_directions: { 814: "both", 999: "backward" } },
      }),
      idea({ id: 814 }),
    ]);
    expect(readNotes(event)?.[0].directions).toEqual({ 1: "both" });
    expect(data.get(mime)).not.toContain("999");
    expect(data.get(mime)).not.toContain("814");
  });

  it.each(["plain", "rectangle", "ellipse", "diamond"] as const)(
    "preserves %s through native copy and paste",
    (shape) => {
      const { event } = clipboard();
      expect(writeNotes(event, [idea({ canvas: { shape, x: 20, y: 30 } })])).toBe(true);
      expect(readNotes(event)?.[0].canvas).toEqual({ shape, x: 20, y: 30 });
    },
  );
  it("round-trips content and internal connections without identity or unrelated references", () => {
    const { event, data } = clipboard();
    const notes = [
      idea({
        id: 813,
        canvas: { x: 12, y: 34, width: 350, color: "mint", links: [814, 999], version: 20 },
      }),
      idea({ id: 814, title: null, body: "<p>Alternative</p>", canvas: { x: 430, y: 54 } }),
    ];
    expect(writeNotes(event, notes)).toBe(true);
    expect(event.defaultPrevented).toBe(true);
    expect(readNotes(event)).toEqual([
      {
        title: "A motive",
        body: "<p>Original text</p>",
        canvas: { x: 12, y: 34, width: 350, color: "mint", shape: "rectangle" },
        connections: [1],
        directions: { 1: "forward" },
      },
      {
        title: null,
        body: "<p>Alternative</p>",
        canvas: { x: 430, y: 54, shape: "rectangle" },
        connections: [],
        directions: {},
      },
    ]);
    const payload = data.get(mime)!;
    for (const field of [
      "813",
      "814",
      "999",
      "author_id",
      "session_id",
      "publication",
      "revision",
      "links",
    ])
      expect(payload).not.toContain(field);
    expect(data.get("text/plain")).toContain("A motive\nOriginal text");
    expect(data.get("text/html")).toContain("<strong>A motive</strong>");
  });
  it("round-trips valid Unicode titles using the domain grapheme limit", () => {
    for (const title of [
      "\u{1F331}".repeat(100),
      "e\u0301".repeat(160),
      "\u{1F468}\u200d\u{1F469}\u200d\u{1F467}".repeat(160),
    ]) {
      const { event } = clipboard();
      expect(writeNotes(event, [idea({ title })])).toBe(true);
      expect(readNotes(event)?.[0].title).toBe(title);
    }
    const { event } = clipboard({
      [mime]: JSON.stringify({
        version: 1,
        notes: [{ title: "e\u0301".repeat(161), body: "<p>Valid body</p>" }],
      }),
    });
    expect(readNotes(event)).toBeNull();
  });
  it("escapes titles and plain text, and strips attributes and executable markup from HTML", () => {
    const title = clipboard();
    writeNotes(title.event, [idea({ title: '<img src=x onerror="bad()">' })]);
    expect(title.data.get("text/html")).toContain("&lt;img");
    const plain = clipboard({ "text/plain": "<img src=x onerror=bad()>\nSecond line" });
    expect(readNotes(plain.event)?.[0].body).toBe(
      "<p>&lt;img src=x onerror=bad()&gt;</p><p>Second line</p>",
    );
    const rich = clipboard({
      "text/html": '<p onclick="bad()"><strong>Formatted</strong><img src=x onerror=bad()></p>',
    });
    expect(readNotes(rich.event)?.[0].body).toBe("<p><strong>Formatted</strong></p>");
  });
  it("rejects malformed, unsupported, oversized and empty payloads instead of creating broken notes", () => {
    for (const payload of [
      "{",
      JSON.stringify({ version: 2, notes: [] }),
      JSON.stringify({ version: 1, notes: [{ title: null, body: 42 }] }),
      JSON.stringify({ version: 1, notes: [{ title: null, body: "<p></p>" }] }),
      JSON.stringify({
        version: 1,
        notes: Array.from({ length: 101 }, () => ({ title: null, body: "<p>a</p>" })),
      }),
      "x".repeat(1_000_001),
    ]) {
      expect(readNotes(clipboard({ [mime]: payload, "text/plain": "fallback" }).event)).toBeNull();
    }
    expect(readNotes(clipboard({ "text/plain": "é".repeat(32_001) }).event)).toBeNull();
    expect(readNotes(clipboard().event)).toBeNull();
    const destination = clipboard();
    expect(writeNotes(destination.event, [idea({ body: "x".repeat(64_001) })])).toBe(false);
    expect(destination.event.defaultPrevented).toBe(false);
    expect(destination.data.size).toBe(0);
  });
  it("accepts only bounded placement and selection-local connection indices", () => {
    const { event } = clipboard({
      [mime]: JSON.stringify({
        version: 1,
        notes: [
          {
            title: null,
            body: "<p>Valid</p>",
            canvas: {
              x: 1e20,
              y: 4,
              width: 30,
              color: "red;bad",
              shape: "polygon(0 0)",
              links: [77],
              version: 89,
            },
            connections: [-1, 0, 1, 1, 2, 3.1, "1"],
          },
          { title: null, body: "<p>Other</p>", canvas: {} },
        ],
      }),
    });
    expect(readNotes(event)?.[0]).toEqual({
      title: null,
      body: "<p>Valid</p>",
      canvas: { y: 4, shape: "rectangle" },
      connections: [1],
      directions: {},
    });
  });
  it("keeps portable content if the browser rejects custom MIME data", () => {
    const { event, data } = clipboard();
    event.clipboardData!.setData = (format, value) => {
      if (format === mime) throw new DOMException("Unsupported format");
      data.set(format, value);
    };
    expect(writeNotes(event, [idea()])).toBe(true);
    expect(readNotes(event)?.[0].body).toContain("Original text");
  });
});
