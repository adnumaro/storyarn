import type { NoteShape } from "../types";

export function validNoteShape(value: unknown): value is NoteShape {
  return value === "plain" || value === "rectangle" || value === "ellipse" || value === "diamond";
}
