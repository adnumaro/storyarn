import type { CanvasPlacement, IdeaGroup } from "../types";

export interface GroupBounds {
  x: number;
  y: number;
  width: number;
  height: number;
  notesWidth: number;
  synthesisX: number;
  synthesisY: number;
}
export interface MemberGeometry {
  id: number;
  canvas?: CanvasPlacement;
  height?: number;
}
export const GROUP_PADDING = 28;
export const GROUP_HEADER = 64;
export const SYNTHESIS_WIDTH = 304;

function memberBounds(member: IdeaGroup["members"][number], overrides: MemberGeometry[]) {
  const local = overrides.find((note) => note.id === member.idea_id);
  const canvas = { ...member.canvas, ...local?.canvas };
  return {
    x: canvas.x ?? 0,
    y: canvas.y ?? 0,
    width: canvas.width ?? 280,
    height: local?.height ?? 260,
  };
}

/** All membership positions contribute, including notes hidden by the current filter. */
export function groupBounds(
  group: IdeaGroup,
  overrides: MemberGeometry[] = [],
  synthesisHeight = 180,
): GroupBounds {
  const members = group.members.map((member) => memberBounds(member, overrides));
  if (!members.length) {
    return {
      x: group.canvas.x,
      y: group.canvas.y,
      width: SYNTHESIS_WIDTH + GROUP_PADDING * 2,
      height: Math.max(284, synthesisHeight + 92),
      notesWidth: 0,
      synthesisX: GROUP_PADDING,
      synthesisY: GROUP_HEADER,
    };
  }
  const x = Math.min(...members.map((member) => member.x)) - GROUP_PADDING;
  const y = Math.min(...members.map((member) => member.y)) - GROUP_HEADER;
  const notesWidth =
    Math.max(...members.map((member) => member.x + member.width)) - x + GROUP_PADDING;
  const notesHeight = Math.max(
    284,
    Math.max(...members.map((member) => member.y + member.height)) - y + GROUP_PADDING,
  );
  let synthesisX = notesWidth;
  let synthesisY = GROUP_HEADER;
  const obstacles = overrides
    .filter((note) => !group.idea_ids.includes(note.id))
    .map((note) => ({
      x: note.canvas?.x ?? 0,
      y: note.canvas?.y ?? 0,
      width: note.canvas?.width ?? 280,
      height: note.height ?? 260,
    }));
  function collisions(left: number, top: number) {
    return obstacles.filter(
      (note) =>
        left < note.x + note.width + 12 &&
        left + SYNTHESIS_WIDTH + 12 > note.x &&
        top < note.y + note.height + 12 &&
        top + synthesisHeight + 12 > note.y,
    );
  }
  // Prefer the free right edge. A neighboring column leaves the synthesis
  // below its own sources, never on top of somebody else's note.
  if (collisions(x + synthesisX, y + synthesisY).length) {
    synthesisX = GROUP_PADDING;
    synthesisY = notesHeight;
    let blocked = collisions(x + synthesisX, y + synthesisY);
    while (blocked.length) {
      synthesisY = Math.max(...blocked.map((note) => note.y + note.height)) - y + GROUP_PADDING;
      blocked = collisions(x + synthesisX, y + synthesisY);
    }
  }
  return {
    x,
    y,
    notesWidth,
    width: group.synthesis
      ? Math.max(notesWidth, synthesisX + SYNTHESIS_WIDTH + GROUP_PADDING)
      : notesWidth,
    height: group.synthesis
      ? Math.max(notesHeight, synthesisY + synthesisHeight + GROUP_PADDING)
      : notesHeight,
    synthesisX,
    synthesisY,
  };
}
export function groupVisibility(group: IdeaGroup, visibleIds: number[]) {
  const visible = group.idea_ids.filter((id) => visibleIds.includes(id)).length;
  return { visible, total: group.idea_ids.length, partial: visible !== group.idea_ids.length };
}
