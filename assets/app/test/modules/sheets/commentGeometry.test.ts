import { afterEach, describe, expect, it, vi } from "vitest";
import {
  clampSheetCommentPosition,
  sheetCommentPointFromClient,
  sheetCommentPositionForBlock,
  sheetCommentScreenPoint,
} from "@modules/sheets/lib/comment-geometry";
import type { SheetCommentThread } from "@modules/sheets/types/comments";

function rect(left: number, top: number, width: number, height: number): DOMRect {
  return {
    left,
    top,
    width,
    height,
    right: left + width,
    bottom: top + height,
    x: left,
    y: top,
    toJSON: () => ({}),
  } as DOMRect;
}

const author = { id: 4, display_name: "Ada", avatar_url: null };
const thread: SheetCommentThread = {
  id: 12,
  status: "open",
  revision: 3,
  message_count: 1,
  created_at: "2026-09-05T09:00:00Z",
  last_activity_at: "2026-09-05T09:00:00Z",
  resolved_at: null,
  resolved_by: null,
  source: {
    type: "sheet_block",
    id: 42,
    sheet_id: 7,
    label: "Health",
    status: "available",
  },
  author,
  position: { x: 25, y: 50 },
};

afterEach(() => {
  document.body.innerHTML = "";
  vi.restoreAllMocks();
});

describe("sheet comment geometry", () => {
  it("normalizes client coordinates inside a block and clamps them at its edges", () => {
    const block = rect(100, 200, 400, 160);

    expect(sheetCommentPointFromClient({ x: 300, y: 240 }, block)).toEqual({ x: 50, y: 25 });
    expect(sheetCommentPointFromClient({ x: 20, y: 500 }, block)).toEqual({ x: 0, y: 100 });
    expect(clampSheetCommentPosition({ x: 120, y: -5 })).toEqual({ x: 100, y: 0 });
  });

  it("projects a pin relative to its own block after document reflow", () => {
    const container = document.createElement("div");
    const block = document.createElement("div");
    block.dataset.sheetBlockId = "42";
    block.id = "sheet-block-42";
    container.append(block);
    document.body.append(container);

    vi.spyOn(container, "getBoundingClientRect").mockReturnValue(rect(10, 20, 800, 1_000));
    const blockRect = vi
      .spyOn(block, "getBoundingClientRect")
      .mockReturnValue(rect(110, 220, 400, 160));

    expect(sheetCommentScreenPoint(thread, container)).toEqual({ x: 200, y: 280 });

    blockRect.mockReturnValue(rect(210, 420, 200, 320));
    expect(sheetCommentPositionForBlock(42, { x: 25, y: 50 }, container)).toEqual({
      x: 250,
      y: 560,
    });
  });

  it("does not render unavailable, missing, or invalid anchors", () => {
    const container = document.createElement("div");
    document.body.append(container);

    expect(sheetCommentScreenPoint(thread, container)).toBeNull();
    expect(
      sheetCommentScreenPoint(
        { ...thread, source: { ...thread.source, status: "unavailable" } },
        container,
      ),
    ).toBeNull();
    expect(
      sheetCommentScreenPoint({ ...thread, position: { x: Number.NaN, y: 20 } }, container),
    ).toBeNull();
  });
});
