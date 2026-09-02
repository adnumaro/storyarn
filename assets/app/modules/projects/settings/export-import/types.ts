export type LocalizationMode = "full_state" | "embedded" | "external_catalog" | "none";
export type LocalizationPolicy = "release" | "preview";

export interface FormatOption {
  format: string;
  label: string;
  localizationMode: LocalizationMode;
  extension?: string;
}

export interface FormatConfig {
  selected: string;
  formats: FormatOption[];
  extension: string;
}

export interface SectionConfig {
  selected: string[];
  supported: string[];
  entityCounts: Record<string, number>;
}

export interface ExportOptions {
  assetMode: string;
  localizationPolicy: LocalizationPolicy;
  validateBeforeExport: boolean;
  prettyPrint: boolean;
}

export interface ValidationFinding {
  message: string;
  rule: string;
  label?: string | null;
  count?: number | null;
  entityType?: string | null;
  entityId?: number | null;
  href?: string | null;
}

export interface ValidationResult {
  status: string;
  stale?: boolean;
  errors?: ValidationFinding[];
  warnings?: ValidationFinding[];
  info?: ValidationFinding[];
}

export interface ExportConfig {
  formatConfig: FormatConfig;
  sectionConfig: SectionConfig;
  options: ExportOptions;
  validation: ValidationResult | null;
  downloadUrl: string;
}

export interface ExportPanelProps {
  /** `:edit_content` — matches the permission enforced by the download controller. */
  canExport: boolean;
  formatConfig: FormatConfig;
  sectionConfig: SectionConfig;
  options: ExportOptions;
  validation?: ValidationResult | null;
  exportDownloadUrl: string;
}

export type ImportStep = "upload" | "preview" | "queued" | "done" | "error";

export type ImportMode = "additive" | "replace_project";
export type ImportConflictStrategy = "skip" | "overwrite" | "rename";
export type MainFlowImportOutcome =
  | "preserve_existing"
  | "replace_existing"
  | "import_candidate"
  | "none";

export type ImportAttemptStage =
  | "parsed"
  | "awaiting_snapshot"
  | "queued"
  | "materializing"
  | "retrying"
  | "completed"
  | "failed"
  | "expired";

export type ImportAttemptStatus =
  | "ready"
  | "queued"
  | "running"
  | "retrying"
  | "completed"
  | "failed"
  | "expired";

export type YarnSpeakerDirectAction = "create_sheet" | "preserve_literal";
export type YarnSpeakerAction = YarnSpeakerDirectAction | "map_to_sheet";
export type YarnSpeakerConfidence = "high" | "medium" | "low";

export interface YarnSpeakerDecision {
  speaker: string;
  occurrences: number;
  suggested_action: YarnSpeakerDirectAction;
  allowed_actions: YarnSpeakerAction[];
  confidence: YarnSpeakerConfidence;
  reasons: string[];
}

export interface YarnReviewDecision {
  speaker: string;
  action: YarnSpeakerAction;
  target_speaker?: string;
}

export interface YarnImportReviewDraft {
  version: 1;
  decisions: YarnReviewDecision[];
  decision_fingerprint: string;
}

export interface YarnImportReviewResolution {
  version: 2;
  decisions: YarnReviewDecision[];
  decision_fingerprint: string;
}

export interface YarnImportIssueSummary {
  warning_count: number;
  error_count: number;
  issue_count: number;
  issues_truncated: boolean;
  counts_by_code: Record<string, number>;
}

export interface YarnSpeakerAliasReview {
  left: string;
  left_occurrences: number;
  right: string;
  right_occurrences: number;
  more_frequent: string;
  less_frequent: string;
  evidence: string;
  decision: "review";
}

export interface YarnImportReview {
  variable_count: number;
  sheet_speaker_count: number;
  preserved_channel_count: number;
  speaker_decision_count: number;
  speaker_decisions: YarnSpeakerDecision[];
  speaker_decisions_truncated: boolean;
  possible_speaker_alias_count: number;
  possible_speaker_aliases: YarnSpeakerAliasReview[];
  possible_speaker_aliases_truncated: boolean;
  compatibility_warning_count: number;
  compatibility_warning_counts_by_code: Record<string, number>;
  requires_acknowledgement: boolean;
}

export interface ImportPreview {
  counts?: Record<string, number>;
  has_conflicts?: boolean;
  conflicts?: Record<string, string[]>;
  main_flow?: {
    additive: Record<ImportConflictStrategy, MainFlowImportOutcome>;
    replace_project: MainFlowImportOutcome;
  } | null;
  import_review?: YarnImportReview | null;
  import_review_draft?: YarnImportReviewDraft | null;
  import_review_resolution?: YarnImportReviewResolution | null;
  issue_summary?: YarnImportIssueSummary | null;
}

export interface ImportState {
  step: ImportStep;
  stage: ImportAttemptStage | null;
  attemptId?: number | null;
  preview?: ImportPreview | null;
  /** Stable, content-free server code. UI copy is always resolved through i18n. */
  errorCode?: string | null;
  conflictStrategy?: ImportConflictStrategy;
  importMode: ImportMode;
  /** True only for a validated archive that contains one real `.yarnproject`. */
  replaceEligible: boolean;
  /** Server-derived internal route to the exact replacement recovery snapshot card. */
  recoverySnapshotUrl?: string | null;
  warningCodes?: string[];
  status?: ImportAttemptStatus | null;
}

export interface SpeakerActionOption {
  value: string;
  action: YarnSpeakerAction;
  targetSpeaker?: string;
  labelKey: string;
  descriptionKey: string;
  accent: "primary" | "warning" | "info";
  suggested: boolean;
}

export interface ImportPanelProps {
  /**
   * `:manage_project`. Importing rewrites project content, so it is owner-only.
   * The panel used to render its file picker for `canEdit`, which showed
   * editors an upload they were then rejected for.
   */
  canImport: boolean;
  /** Opaque, server-derived namespace; contains no user or project identifier. */
  resumeStorageKey: string;
  importState: ImportState;
}
