/**
 * Prop contracts of the Localization pages. The LiveViews serialize these
 * shapes (camelCase) for the overview and the workbench.
 */

export interface LanguageProgress {
  localeCode: string;
  name: string;
  flagCode: string | null;
  shortLabel: string;
  total: number;
  pending: number;
  draft: number;
  inProgress: number;
  review: number;
  final: number;
  stale: number;
  wordCount: number;
  percentage: number;
  workbenchUrl: string;
}

export interface SourceLanguage {
  localeCode: string;
  name: string;
  flagCode: string | null;
  shortLabel: string;
}

export interface SpeakerStat {
  speakerSheetId: number | null;
  speakerName: string | null;
  lineCount: number;
  wordCount: number;
}

export interface VoProgress {
  none: number;
  needed: number;
  recorded: number;
  approved: number;
}

export interface WorkbenchProgress {
  total: number;
  pending: number;
  draft: number;
  in_progress: number;
  review: number;
  final: number;
  stale: number;
}

export interface WorkbenchFilters {
  status: string;
  sourceType: string;
  voStatus: string;
  speaker: number | null;
  stale: boolean;
  search: string;
}

export interface WorkbenchLanguage {
  code: string;
  name: string;
  flagCode: string | null;
  shortLabel: string;
  wordCount: number;
  sourceName: string;
}

export interface SpeakerOption {
  id: number;
  name: string | null;
  lineCount: number;
  wordCount: number;
}

export interface TextRow {
  id: number;
  sourceText: string;
  translatedText: string | null;
  status: string;
  statusLabel: string;
  sourceType: string;
  sourceTypeLabel: string;
  sourceTypeIcon: string;
  sourceField: string;
  contentRole: string;
  contentRoleLabel: string;
  speakerName: string | null;
  voEligible: boolean;
  voStatus: string;
  wordCount: number;
  machineTranslated: boolean;
  stale: boolean;
  editUrl: string;
}

export interface SourceRef {
  parent: string | null;
  label: string;
  url: string | null;
}

export interface GlossaryHit {
  source: string;
  target: string;
}

export interface SelectedText {
  id: number;
  sourceType: string;
  sourceTypeLabel: string;
  sourceField: string;
  contentRole: string;
  contentRoleLabel: string;
  speakerName: string | null;
  sourceRef: SourceRef;
  sourceHtml: string;
  sourceText: string;
  wordCount: number;
  localeCode: string;
  localeName: string;
  translatedText: string;
  status: string;
  translatorNotes: string;
  voStatus: string;
  voEligible: boolean;
  machineTranslated: boolean;
  lastTranslatedAt: string | null;
  translatedBy: string | null;
  stale: boolean;
  placeholders: string[];
  glossaryHits: GlossaryHit[];
  lockVersion: number;
}

export interface SaveResponse {
  ok?: boolean;
  conflict?: boolean;
  error?: string;
  errors?: Record<string, string>;
  text?: SelectedText;
}

export type SaveState = "idle" | "dirty" | "saving" | "saved" | "error" | "conflict";

export interface PlaceholderIssue {
  missing: string[];
  extra: string[];
}
