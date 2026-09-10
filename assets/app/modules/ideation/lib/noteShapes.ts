import type { NoteShape } from "../types";

export function validNoteShape(value: unknown): value is NoteShape {
  return value === "rectangle" || value === "ellipse" || value === "diamond";
}

const contentWidthRatio = { rectangle: 1, ellipse: Math.SQRT1_2, diamond: 0.5 };
const contentPadding = { rectangle: 40, ellipse: 24, diamond: 24 };

/** Keep the writing area readable when a shape has a narrower inscribed region. */
export function reshapedWidth(width: number, before: NoteShape, after: NoteShape): number {
  const content = width * contentWidthRatio[before] - contentPadding[before];
  return Math.min(
    800,
    Math.max(180, Math.round((content + contentPadding[after]) / contentWidthRatio[after])),
  );
}
