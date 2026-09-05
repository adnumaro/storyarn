import type { CommentPosition } from "./types";

export interface StoredCommentDraft {
  position?: CommentPosition;
  body?: string;
  mentionIds?: number[];
  requestId?: string;
  fingerprint?: string;
}

function normalizedDraft(value: unknown): StoredCommentDraft | null {
  if (!value || typeof value !== "object") return null;
  const candidate = value as {
    position?: unknown;
    body?: unknown;
    mentionIds?: unknown;
    requestId?: unknown;
    fingerprint?: unknown;
  };
  const draft: StoredCommentDraft = {
    ...(validPosition(candidate.position) ? { position: candidate.position } : {}),
    ...(typeof candidate.body === "string" && candidate.body.length <= 10_000
      ? { body: candidate.body }
      : {}),
    ...(validMentionIds(candidate.mentionIds)
      ? { mentionIds: [...new Set(candidate.mentionIds)] }
      : {}),
    ...(validRequestId(candidate.requestId) ? { requestId: candidate.requestId } : {}),
    ...(validFingerprint(candidate.fingerprint) ? { fingerprint: candidate.fingerprint } : {}),
  };
  return Object.keys(draft).length ? draft : null;
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

function validPosition(value: unknown): value is CommentPosition {
  if (!value || typeof value !== "object") return false;
  const position = value as { x?: unknown; y?: unknown };
  return (
    typeof position.x === "number" &&
    Number.isFinite(position.x) &&
    position.x >= 0 &&
    position.x <= 100 &&
    typeof position.y === "number" &&
    Number.isFinite(position.y) &&
    position.y >= 0 &&
    position.y <= 10_000_000
  );
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
