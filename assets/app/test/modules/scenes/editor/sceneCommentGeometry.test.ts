import { describe, expect, it } from "vitest";
import {
  clampSceneCommentPosition,
  sceneCommentCanvasPoint,
  sceneCommentDragPosition,
  sceneCommentPointFromClient,
  sceneCommentScreenPoint,
} from "@modules/scenes/editor/lib/comment-geometry";
import type { SceneCommentThread } from "@modules/scenes/types/comments";

const projection = {
  percentToPixel: (x: number, y: number) => ({ x: 50 + x * 8, y: 25 + y * 4 }),
  pixelToPercent: (x: number, y: number) => ({ x: (x - 50) / 8, y: (y - 25) / 4 }),
};

const thread: SceneCommentThread = {
  id: 12,
  status: "open",
  revision: 3,
  message_count: 1,
  created_at: "2026-09-04T09:00:00Z",
  last_activity_at: "2026-09-04T09:00:00Z",
  resolved_at: null,
  resolved_by: null,
  source: {
    type: "scene_canvas",
    id: 7,
    scene_id: 7,
    label: "Scene canvas",
    status: "available",
  },
  author: { id: 4, display_name: "Ada", avatar_url: null },
  preview: "Move the encounter here.",
  position: { x: 25, y: 75 },
};

describe("Scene comment geometry", () => {
  it("projects logical percentages through canvas bounds and the current pan and zoom", () => {
    expect(
      sceneCommentScreenPoint(
        { x: 25, y: 75 },
        { x: 100, y: -20, scaleX: 2, scaleY: 2 },
        projection,
      ),
    ).toEqual({ x: 600, y: 630 });

    const resizedProjection = {
      percentToPixel: (x: number, y: number) => ({ x: 20 + x * 12, y: 40 + y * 6 }),
    };
    expect(
      sceneCommentScreenPoint(
        { x: 25, y: 75 },
        { x: -50, y: 30, scaleX: 0.5, scaleY: 0.5 },
        resizedProjection,
      ),
    ).toEqual({ x: 110, y: 275 });
  });

  it("inverts client coordinates through the stage transform and clamps outside clicks", () => {
    expect(
      sceneCommentPointFromClient(
        { x: 610, y: 650 },
        { left: 10, top: 20 },
        { x: 100, y: -20, scaleX: 2, scaleY: 2 },
        projection,
      ),
    ).toEqual({ x: 25, y: 75 });

    expect(
      sceneCommentPointFromClient(
        { x: -500, y: 2_000 },
        { left: 10, top: 20 },
        { x: 0, y: 0, scaleX: 1, scaleY: 1 },
        projection,
      ),
    ).toEqual({ x: 0, y: 100 });
  });

  it("converts screen drag deltas back to percentages at any zoom and clamps every edge", () => {
    expect(
      sceneCommentDragPosition(
        { x: 25, y: 75 },
        { x: 160, y: -80 },
        { x: 500, y: 300, scaleX: 2, scaleY: 2 },
        projection,
      ),
    ).toEqual({ x: 35, y: 65 });
    expect(
      sceneCommentDragPosition(
        { x: 99, y: 1 },
        { x: 1_000, y: -1_000 },
        { x: 0, y: 0, scaleX: 0.5, scaleY: 0.5 },
        projection,
      ),
    ).toEqual({ x: 100, y: 0 });
    expect(clampSceneCommentPosition({ x: -0.1, y: 100.1 })).toEqual({ x: 0, y: 100 });
  });

  it("renders only available scene-canvas sources with finite positions", () => {
    expect(sceneCommentCanvasPoint(thread)).toEqual({ x: 25, y: 75 });
    expect(
      sceneCommentCanvasPoint({
        ...thread,
        source: { ...thread.source, status: "unavailable" },
      }),
    ).toBeNull();
    expect(sceneCommentCanvasPoint({ ...thread, position: { x: Number.NaN, y: 25 } })).toBeNull();
  });
});
