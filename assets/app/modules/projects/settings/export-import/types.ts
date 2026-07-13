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
}

export interface ValidationResult {
  status: string;
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
  formatConfig: FormatConfig;
  sectionConfig: SectionConfig;
  options: ExportOptions;
  validation?: ValidationResult | null;
  exportDownloadUrl: string;
}
