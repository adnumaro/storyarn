import type { Idea } from "../types";
export function notePosition(note: Idea) {
  return {
    x: note.canvas?.x ?? (note.id % 5) * 330,
    y: note.canvas?.y ?? (Math.floor(note.id / 5) % 5) * 290,
  };
}
