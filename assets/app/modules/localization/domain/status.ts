/**
 * One vocabulary for the Localization tool: five translation statuses, two
 * derived flags (outdated, machine translated), four voice-over states, the
 * three source types and the content roles. Every surface renders a status
 * with the same colour and the same label.
 */

export const STATUS_KEYS = ["pending", "draft", "in_progress", "review", "final"] as const;
export type TranslationStatus = (typeof STATUS_KEYS)[number];

export const VO_STATUS_KEYS = ["none", "needed", "recorded", "approved"] as const;
export type VoStatus = (typeof VO_STATUS_KEYS)[number];

export const SOURCE_TYPE_KEYS = ["flow_node", "block", "sheet"] as const;
export type SourceType = (typeof SOURCE_TYPE_KEYS)[number];

export const CONTENT_ROLE_KEYS = [
  "dialogue",
  "response",
  "stage_direction",
  "menu",
  "exit",
  "runtime_value",
  "speaker_name",
] as const;
export type ContentRole = (typeof CONTENT_ROLE_KEYS)[number];

export type Tone =
  | TranslationStatus
  | "outdated"
  | "machine"
  | "vo_none"
  | "vo_needed"
  | "vo_recorded"
  | "vo_approved";

export interface ToneSwatch {
  /** Solid fill for dots and bar segments. */
  dot: string;
  /** Foreground colour for inline labels. */
  text: string;
  /** Tinted background + foreground for pills. */
  pill: string;
}

export const TONES: Record<Tone, ToneSwatch> = {
  pending: {
    dot: "bg-slate-400",
    text: "text-slate-500 dark:text-slate-400",
    pill: "bg-slate-500/12 text-slate-600 dark:text-slate-300",
  },
  draft: {
    dot: "bg-sky-400",
    text: "text-sky-600 dark:text-sky-400",
    pill: "bg-sky-400/15 text-sky-700 dark:text-sky-300",
  },
  in_progress: {
    dot: "bg-amber-400",
    text: "text-amber-600 dark:text-amber-400",
    pill: "bg-amber-400/15 text-amber-700 dark:text-amber-300",
  },
  review: {
    dot: "bg-violet-400",
    text: "text-violet-600 dark:text-violet-400",
    pill: "bg-violet-400/15 text-violet-700 dark:text-violet-300",
  },
  final: {
    dot: "bg-primary",
    text: "text-primary",
    pill: "bg-primary/15 text-primary",
  },
  outdated: {
    dot: "bg-orange-500",
    text: "text-orange-600 dark:text-orange-400",
    pill: "bg-orange-500/12 text-orange-700 dark:text-orange-300",
  },
  machine: {
    dot: "bg-muted-foreground",
    text: "text-muted-foreground",
    pill: "bg-muted text-muted-foreground",
  },
  vo_none: {
    dot: "bg-slate-400",
    text: "text-slate-500 dark:text-slate-400",
    pill: "bg-slate-500/12 text-slate-600 dark:text-slate-300",
  },
  vo_needed: {
    dot: "bg-amber-400",
    text: "text-amber-600 dark:text-amber-400",
    pill: "bg-amber-400/15 text-amber-700 dark:text-amber-300",
  },
  vo_recorded: {
    dot: "bg-sky-400",
    text: "text-sky-600 dark:text-sky-400",
    pill: "bg-sky-400/15 text-sky-700 dark:text-sky-300",
  },
  vo_approved: {
    dot: "bg-emerald-500",
    text: "text-emerald-600 dark:text-emerald-400",
    pill: "bg-emerald-500/12 text-emerald-700 dark:text-emerald-300",
  },
};

export const STATUS_I18N: Record<TranslationStatus, string> = {
  pending: "localization.status.pending",
  draft: "localization.status.draft",
  in_progress: "localization.status.in_progress",
  review: "localization.status.review",
  final: "localization.status.final",
};

export const VO_I18N: Record<VoStatus, string> = {
  none: "localization.vo.none",
  needed: "localization.vo.needed",
  recorded: "localization.vo.recorded",
  approved: "localization.vo.approved",
};

export const SOURCE_TYPE_I18N: Record<SourceType, string> = {
  flow_node: "localization.types.flow_node",
  block: "localization.types.block",
  sheet: "localization.types.sheet",
};

export function isTranslationStatus(value: string): value is TranslationStatus {
  return (STATUS_KEYS as readonly string[]).includes(value);
}

export function isVoStatus(value: string): value is VoStatus {
  return (VO_STATUS_KEYS as readonly string[]).includes(value);
}

export function voTone(status: VoStatus): Tone {
  return `vo_${status}`;
}

export function statusTone(status: string): Tone {
  return isTranslationStatus(status) ? status : "pending";
}

export interface StatusCounts {
  pending: number;
  draft: number;
  inProgress: number;
  review: number;
  final: number;
}

export interface StatusSegment {
  key: TranslationStatus;
  value: number;
}

/** Segments in bar order: done first, untouched last. */
export function statusSegments(counts: StatusCounts): StatusSegment[] {
  return [
    { key: "final", value: counts.final },
    { key: "review", value: counts.review },
    { key: "in_progress", value: counts.inProgress },
    { key: "draft", value: counts.draft },
    { key: "pending", value: counts.pending },
  ];
}

export function percentFinal(final: number, total: number): number {
  return total > 0 ? Math.round((final * 100) / total) : 0;
}
