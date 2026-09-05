import type { SceneCommentPosition, SceneCommentThread } from "../../types/comments";

export interface SceneCommentStageTransform {
  x: number;
  y: number;
  scaleX: number;
  scaleY: number;
}

export interface SceneCommentProjection {
  percentToPixel(x: number, y: number): SceneCommentPosition;
  pixelToPercent(x: number, y: number): SceneCommentPosition;
}

export function clampSceneCommentPosition(position: SceneCommentPosition): SceneCommentPosition {
  return {
    x: Math.max(0, Math.min(100, position.x)),
    y: Math.max(0, Math.min(100, position.y)),
  };
}

export function sceneCommentCanvasPoint(
  thread: SceneCommentThread,
  position = thread.position,
): SceneCommentPosition | null {
  if (
    thread.source.type !== "scene_canvas" ||
    thread.source.status !== "available" ||
    !position ||
    !Number.isFinite(position.x) ||
    !Number.isFinite(position.y)
  )
    return null;

  return clampSceneCommentPosition(position);
}

export function sceneCommentScreenPoint(
  position: SceneCommentPosition,
  stage: SceneCommentStageTransform,
  projection: Pick<SceneCommentProjection, "percentToPixel">,
): SceneCommentPosition {
  const world = projection.percentToPixel(position.x, position.y);
  return {
    x: world.x * stage.scaleX + stage.x,
    y: world.y * stage.scaleY + stage.y,
  };
}

export function sceneCommentPointFromClient(
  point: SceneCommentPosition,
  rect: Pick<DOMRect, "left" | "top">,
  stage: SceneCommentStageTransform,
  projection: Pick<SceneCommentProjection, "pixelToPercent">,
): SceneCommentPosition {
  const scaleX = stage.scaleX || 1;
  const scaleY = stage.scaleY || 1;
  const world = {
    x: (point.x - rect.left - stage.x) / scaleX,
    y: (point.y - rect.top - stage.y) / scaleY,
  };

  return clampSceneCommentPosition(projection.pixelToPercent(world.x, world.y));
}

export function sceneCommentDragPosition(
  start: SceneCommentPosition,
  delta: SceneCommentPosition,
  stage: SceneCommentStageTransform,
  projection: SceneCommentProjection,
): SceneCommentPosition {
  const world = projection.percentToPixel(start.x, start.y);
  const nextWorld = {
    x: world.x + delta.x / (stage.scaleX || 1),
    y: world.y + delta.y / (stage.scaleY || 1),
  };

  return clampSceneCommentPosition(projection.pixelToPercent(nextWorld.x, nextWorld.y));
}
