/**
 * Builds a deep link into the workbench of one language. The query keys match
 * what `LocalizationLive.Index.handle_params/3` reads, so every count on the
 * overview opens the list already filtered.
 */
export interface WorkbenchQuery {
  status?: string | null;
  sourceType?: string | null;
  voStatus?: string | null;
  speaker?: number | null;
  stale?: boolean;
  search?: string | null;
}

export function workbenchUrl(base: string, query: WorkbenchQuery = {}, textId?: number): string {
  const params = new URLSearchParams();
  if (query.status) params.set("status", query.status);
  if (query.sourceType) params.set("source_type", query.sourceType);
  if (query.voStatus) params.set("vo_status", query.voStatus);
  if (query.speaker) params.set("speaker", String(query.speaker));
  if (query.stale) params.set("stale", "1");
  if (query.search) params.set("search", query.search);

  const path = textId ? `${base}/${textId}` : base;
  const search = params.toString();
  return search ? `${path}?${search}` : path;
}
