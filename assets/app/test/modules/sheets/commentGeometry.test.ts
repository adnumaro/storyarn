import { afterEach, describe, expect, it, vi } from "vitest";
import {
  clampSheetCommentPosition,
  constrainSheetCommentPositionToSurface,
  sheetCommentCanvasPoint,
  sheetCommentPointFromClient,
  sheetCommentPositionForSurface,
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
    type: "sheet_canvas",
    id: 7,
    sheet_id: 7,
    label: "Hero",
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
  it("normalizes horizontal coordinates, keeps vertical pixels, and insets pins at the edges", () => {
    const surface = rect(100, 200, 400, 160);

    expect(sheetCommentPointFromClient({ x: 300, y: 240 }, surface)).toEqual({ x: 50, y: 40 });
    expect(sheetCommentPointFromClient({ x: 20, y: 500 }, surface)).toEqual({ x: 4, y: 144 });
    expect(clampSheetCommentPosition({ x: 120, y: -5 })).toEqual({ x: 100, y: 0 });
  });

  it("projects every pin against the sheet and preserves vertical placement as it grows", () => {
    const container = document.createElement("div");
    document.body.append(container);
    const surfaceRect = vi
      .spyOn(container, "getBoundingClientRect")
      .mockReturnValue(rect(10, 20, 800, 1_000));

    expect(sheetCommentScreenPoint(thread, container)).toEqual({ x: 200, y: 50 });

    surfaceRect.mockReturnValue(rect(10, 20, 400, 2_000));
    expect(sheetCommentPositionForSurface({ x: 25, y: 50 }, container)).toEqual({ x: 100, y: 50 });
  });

  it("keeps pins inside the gray surface without rewriting an old offscreen position", () => {
    const container = document.createElement("div");
    document.body.append(container);
    vi.spyOn(container, "getBoundingClientRect").mockReturnValue(rect(10, 20, 800, 300));

    const oldPosition = { x: 100, y: 900 };
    expect(sheetCommentPositionForSurface(oldPosition, container)).toEqual({ x: 784, y: 284 });
    expect(oldPosition).toEqual({ x: 100, y: 900 });
    expect(
      constrainSheetCommentPositionToSurface(oldPosition, { width: 800, height: 300 }),
    ).toEqual({ x: 98, y: 284 });
  });

  it("does not render unavailable, non-canvas, missing, or invalid anchors", () => {
    const container = document.createElement("div");
    document.body.append(container);
    vi.spyOn(container, "getBoundingClientRect").mockReturnValue(rect(10, 20, 800, 1_000));

    expect(
      sheetCommentScreenPoint(
        { ...thread, source: { ...thread.source, status: "unavailable" } },
        container,
      ),
    ).toBeNull();
    expect(
      sheetCommentScreenPoint({ ...thread, position: { x: Number.NaN, y: 20 } }, container),
    ).toBeNull();
    expect(sheetCommentScreenPoint({ ...thread, position: null }, container)).toBeNull();
    expect(
      sheetCommentCanvasPoint({
        ...thread,
        source: { ...thread.source, type: "sheet_block" as "sheet_canvas" },
      }),
    ).toBeNull();
  });
});
