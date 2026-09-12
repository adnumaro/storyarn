import type { CommentContextReference, CommentPosition } from "./types";

export interface StoredCommentDraft {
  coordinateSpace?: "canvas";
  position?: CommentPosition;
  context?: CommentContextReference | null;
  body?: string;
  mentionIds?: number[];
  requestId?: string;
  fingerprint?: string;
}

function normalizedDraft(value: unknown): StoredCommentDraft | null {
  if (!value || typeof value !== "object") return null;
  const candidate = value as {
    coordinateSpace?: unknown;
    position?: unknown;
    context?: unknown;
    body?: unknown;
    mentionIds?: unknown;
    requestId?: unknown;
    fingerprint?: unknown;
  };
  const draft: StoredCommentDraft = {
    ...draftCoordinates(candidate),
    ...(validContext(candidate.context) ? { context: candidate.context } : {}),
    ...(validBody(candidate.body) ? { body: candidate.body } : {}),
    ...(validMentionIds(candidate.mentionIds)
      ? { mentionIds: [...new Set(candidate.mentionIds)] }
      : {}),
    ...(validRequestId(candidate.requestId) ? { requestId: candidate.requestId } : {}),
    ...(validFingerprint(candidate.fingerprint) ? { fingerprint: candidate.fingerprint } : {}),
  };
  return Object.keys(draft).length ? draft : null;
}

function draftCoordinates(candidate: {
  coordinateSpace?: unknown;
  position?: unknown;
}): StoredCommentDraft {
  const canvas = candidate.coordinateSpace === "canvas";
  return {
    ...(canvas ? { coordinateSpace: "canvas" as const } : {}),
    ...(validPosition(candidate.position, canvas) ? { position: candidate.position } : {}),
  };
}

function validBody(value: unknown): value is string {
  return typeof value === "string" && value.length <= 10_000;
}
function validOffsetCoordinate(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value) && Math.abs(value) <= 10_000_000;
}
function validOffset(value: unknown): boolean {
  if (value == null) return true;
  if (typeof value !== "object") return false;
  const offset = value as { x?: unknown; y?: unknown };
  return validOffsetCoordinate(offset.x) && validOffsetCoordinate(offset.y);
}
function validContext(value: unknown): value is CommentContextReference | null {
  if (value === null) return true;
  if (!value || typeof value !== "object") return false;
  const context = value as { type?: unknown; id?: unknown; offset?: unknown };
  return (
    typeof context.type === "string" &&
    /^[a-z_]{1,60}$/.test(context.type) &&
    typeof context.id === "string" &&
    context.id.length > 0 &&
    context.id.length <= 100 &&
    validOffset(context.offset)
  );
}

function validRequestId(value: unknown): value is string {
  return (
    typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)
  );
}

function validFingerprint(value: unknown): value is string {
  return typeof value === "string" && value.length <= 25_000;
}

function validPosition(value: unknown, canvas: boolean): value is CommentPosition {
  if (!value || typeof value !== "object") return false;
  const position = value as { x?: unknown; y?: unknown };
  if (!validOffsetCoordinate(position.x) || !validOffsetCoordinate(position.y)) return false;
  return canvas || (position.x >= 0 && position.x <= 100 && position.y >= 0);
}

function validMentionIds(value: unknown): value is number[] {
  return (
    Array.isArray(value) &&
    value.length <= 50 &&
    value.every((id) => Number.isInteger(id) && id > 0)
  );
}

export function readCommentDraft(key: string | null): StoredCommentDraft | null {
  if (!key || typeof window === "undefined") return null;

  try {
    const raw = window.sessionStorage.getItem(key);
    if (!raw) return null;
    return normalizedDraft(JSON.parse(raw) as unknown);
  } catch {
    return null;
  }
}

export function updateCommentDraft(key: string | null, patch: StoredCommentDraft): void {
  if (!key || typeof window === "undefined") return;

  try {
    const current = readCommentDraft(key) ?? {};
    window.sessionStorage.setItem(key, JSON.stringify({ ...current, ...patch }));
  } catch {
    // Draft persistence is best-effort when browser storage is unavailable.
  }
}

export function clearCommentDraft(key: string | null): void {
  if (!key || typeof window === "undefined") return;

  try {
    window.sessionStorage.removeItem(key);
  } catch {
    // Draft persistence is best-effort when browser storage is unavailable.
  }
}
