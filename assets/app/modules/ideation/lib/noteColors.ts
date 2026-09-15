/**
 * A note has one colour; its shape decides where the colour goes. A card takes
 * it on its surface, a text-only note takes it on its words, and "none" keeps
 * the default look of either.
 */
export const NOTE_COLOR_IDS = [
  "none",
  "yellow",
  "coral",
  "mint",
  "blue",
  "violet",
  "paper",
] as const;
export type NoteColor = (typeof NOTE_COLOR_IDS)[number];

const TONES: Record<Exclude<NoteColor, "none">, { fill: string; ink: string }> = {
  yellow: { fill: "#f5e6a8", ink: "#a16207" },
  coral: { fill: "#f8cbbd", ink: "#c2410c" },
  mint: { fill: "#cbe8d5", ink: "#15803d" },
  blue: { fill: "#c9e2f5", ink: "#1d4ed8" },
  violet: { fill: "#e2d5f4", ink: "#7e22ce" },
  paper: { fill: "#f4f1e9", ink: "#78716c" },
};

export function noteColor(id: string | undefined): NoteColor {
  return (NOTE_COLOR_IDS as readonly string[]).includes(id ?? "") ? (id as NoteColor) : "none";
}

/** The surface tone of a card; the default card is the yellow one. */
export function noteFill(id: string | undefined): string {
  const color = noteColor(id);
  return TONES[color === "none" ? "yellow" : color].fill;
}

/** The ink of a text-only note, or null to keep the default text colour. */
export function noteInk(id: string | undefined): string | null {
  const color = noteColor(id);
  return color === "none" ? null : TONES[color].ink;
}

/** What a swatch previews: the ink for a text-only note, the surface otherwise. */
export function noteSwatch(id: string | undefined, shape: string | undefined): string | undefined {
  return shape === "plain" ? (noteInk(id) ?? undefined) : noteFill(id);
}
