import type { CanvasPlacement, Idea } from "../types";
import { notePosition } from "./placement";
import { pasteContent } from "./paste";

const MIME = "application/x-storyarn-brainstorming+json";
const MAX_NOTES = 100;
const MAX_PAYLOAD_BYTES = 1_000_000;
const MAX_BODY_BYTES = 64_000;
const colors = new Set(["yellow", "coral", "mint", "blue", "violet", "paper"]);
const encoder = new TextEncoder();
const titleSegments = new Intl.Segmenter(undefined, { granularity: "grapheme" });

export interface NoteCopy {
  title: string | null;
  body: string;
  canvas: CanvasPlacement;
  /** Selection-local indices, never persisted idea IDs. */
  connections?: number[];
}

function sized(value: string, maximum: number): boolean {
  return value.length <= maximum && encoder.encode(value).length <= maximum;
}
function escaped(value: string): string {
  const element = document.createElement("div");
  element.textContent = value;
  return element.innerHTML;
}
function textOf(html: string): string {
  const element = document.createElement("template");
  element.innerHTML = html.replace(/<\/(p|li|blockquote)>/g, "\n").replace(/<br\s*\/?\s*>/g, "\n");
  return element.content.textContent?.trim() ?? "";
}
function coordinate(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value) && Math.abs(value) <= 1_000_000;
}
interface PlacementInput {
  x?: unknown;
  y?: unknown;
  width?: unknown;
  color?: unknown;
}
interface NoteInput {
  title?: unknown;
  body?: unknown;
  canvas?: unknown;
  connections?: unknown;
}
interface ClipboardInput {
  version?: unknown;
  notes?: unknown;
}
function object(value: unknown): value is object {
  return value !== null && typeof value === "object";
}
function validWidth(value: unknown): value is number {
  return typeof value === "number" && value >= 180 && value <= 800;
}
function validColor(value: unknown): value is string {
  return typeof value === "string" && colors.has(value);
}
function validTitle(value: unknown): value is string | null {
  if (value === null) return true;
  if (typeof value !== "string") return false;
  // Match the domain's grapheme limit, including composed accents and emoji.
  const segments = titleSegments.segment(value)[Symbol.iterator]();
  let count = 0;
  while (!segments.next().done) {
    if (++count > 160) return false;
  }
  return true;
}
function readPlacement(value: unknown): CanvasPlacement {
  if (!object(value)) return {};
  const input = value as PlacementInput;
  const canvas: CanvasPlacement = {};
  if (coordinate(input.x)) canvas.x = input.x;
  if (coordinate(input.y)) canvas.y = input.y;
  if (validWidth(input.width)) canvas.width = input.width;
  if (validColor(input.color)) canvas.color = input.color;
  return canvas;
}
function readConnections(value: unknown, index: number, count: number): number[] {
  if (!Array.isArray(value)) return [];
  return [
    ...new Set(
      value.filter(
        (target: unknown): target is number =>
          typeof target === "number" &&
          Number.isInteger(target) &&
          target >= 0 &&
          target < count &&
          target !== index,
      ),
    ),
  ].slice(0, MAX_NOTES);
}
function readNote(value: unknown, index: number, count: number): NoteCopy | null {
  if (!object(value)) return null;
  const input = value as NoteInput;
  if (
    typeof input.body !== "string" ||
    !sized(input.body, MAX_BODY_BYTES) ||
    !validTitle(input.title)
  )
    return null;
  const body = pasteContent(input.body);
  if (!textOf(body) || !sized(body, MAX_BODY_BYTES)) return null;
  return {
    title: input.title,
    body,
    canvas: readPlacement(input.canvas),
    connections: readConnections(input.connections, index, count),
  };
}
/** Synchronous native clipboard writing keeps browser copy/cut permissions intact. */
export function writeNotes(event: ClipboardEvent, notes: Idea[]): boolean {
  if (!event.clipboardData || !notes.length || notes.length > MAX_NOTES) return false;
  const indices = new Map(notes.map((note, index) => [note.id, index]));
  const content: NoteCopy[] = notes.map((note) => ({
    title: note.title,
    body: pasteContent(note.body),
    canvas: readPlacement({ ...note.canvas, ...notePosition(note) }),
    connections: (note.canvas?.links ?? []).flatMap((id) => {
      const index = indices.get(id);
      return index === undefined || id === note.id ? [] : [index];
    }),
  }));
  if (content.some((note) => !sized(note.body, MAX_BODY_BYTES))) return false;
  const payload = JSON.stringify({ version: 1, notes: content });
  if (!sized(payload, MAX_PAYLOAD_BYTES)) return false;
  const html = content
    .map(
      (note) => `${note.title ? `<p><strong>${escaped(note.title)}</strong></p>` : ""}${note.body}`,
    )
    .join("<p><br></p>");
  try {
    event.clipboardData.setData("text/plain", textOf(html));
    event.clipboardData.setData("text/html", html);
    // Some browsers permit only the standard formats. Text remains portable.
    try {
      event.clipboardData.setData(MIME, payload);
    } catch {
      /* standard formats already written */
    }
    event.preventDefault();
    return true;
  } catch {
    return false;
  }
}

function payloadEntries(value: unknown): unknown[] | null {
  if (!object(value)) return null;
  const input = value as ClipboardInput;
  if (
    input.version !== 1 ||
    !Array.isArray(input.notes) ||
    !input.notes.length ||
    input.notes.length > MAX_NOTES
  )
    return null;
  return input.notes;
}
function readPayload(payload: string): NoteCopy[] | null {
  if (!sized(payload, MAX_PAYLOAD_BYTES)) return null;
  try {
    const entries = payloadEntries(JSON.parse(payload));
    if (!entries) return null;
    const notes = entries.map((note, index) => readNote(note, index, entries.length));
    return notes.every((note) => note !== null) ? notes : null;
  } catch {
    return null;
  }
}
function readExternal(data: DataTransfer): NoteCopy[] | null {
  const html = data.getData("text/html");
  const text = data.getData("text/plain");
  if (!sized(html, MAX_PAYLOAD_BYTES) || !sized(text, MAX_BODY_BYTES)) return null;
  const body = html
    ? pasteContent(html)
    : text
        .split(/\r?\n/)
        .map((line) => `<p>${escaped(line)}</p>`)
        .join("");
  if (!textOf(body) || !sized(body, MAX_BODY_BYTES)) return null;
  return [{ title: null, body, canvas: {} }];
}
/** No identity, publication state, revision or out-of-selection reference crosses the clipboard. */
export function readNotes(event: ClipboardEvent): NoteCopy[] | null {
  const data = event.clipboardData;
  if (!data) return null;
  const payload = data.getData(MIME);
  return payload ? readPayload(payload) : readExternal(data);
}
