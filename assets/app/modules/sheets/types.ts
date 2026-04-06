/**
 * Shared types for the sheets module.
 */
import type { FunctionalComponent } from "vue";

// ── Block types ──

export interface SelectOption {
  key: string;
  value: string;
}

export interface BlockConfig {
  label?: string;
  placeholder?: string;
  options?: SelectOption[];
  mode?: "two_state" | "tri_state";
  true_label?: string;
  false_label?: string;
  neutral_label?: string;
  min?: number | null;
  max?: number | null;
  step?: number | null;
  width?: number;
  multiple?: boolean;
  [key: string]: unknown;
}

export interface BlockValue {
  content?: string | number | boolean | string[] | null;
  target_type?: string;
  target_id?: number | string;
}

export interface ReferenceTarget {
  name: string;
  shortcut?: string;
}

export interface GalleryImage {
  id: number | string;
  url: string;
  label?: string;
  description?: string;
  position?: number;
}

export interface Block {
  id: number | string;
  type: string;
  config?: BlockConfig;
  value?: BlockValue;
  variable_name?: string;
  is_constant?: boolean;
  required?: boolean;
  detached?: boolean;
  scope?: string;
  collapsed?: boolean;
  columns?: TableColumn[];
  rows?: TableRow[];
  gallery_images?: GalleryImage[];
  reference_target?: ReferenceTarget | null;
  can_reattach?: boolean;
}

// ── Table types ──

export interface TableColumn {
  id: number | string;
  name: string;
  slug: string;
  type: string;
  required?: boolean;
  is_constant?: boolean;
  config?: BlockConfig;
}

export interface TableRow {
  id: number | string;
  name: string;
  slug: string;
  cells?: Record<string, unknown>;
}

// ── Sheet types ──

export interface SheetAvatar {
  id: number | string;
  url: string;
  name?: string;
  notes?: string;
  is_default?: boolean;
}

export interface Sheet {
  id: number | string;
  name: string;
  shortcut?: string;
  color?: string;
  bannerUrl?: string;
  avatars?: SheetAvatar[];
}

// ── Tree types ──

export interface SheetTreeNodeData {
  id: number | string;
  name: string;
  avatar_url?: string | null;
  children?: SheetTreeNodeData[];
}

// ── Inherited block group ──

export interface InheritedBlockGroup {
  sourceSheet: {
    id: number | string;
    name: string;
  };
  blocks: Block[];
}

// ── Block lock ──

export interface BlockLock {
  userId: number;
  userEmail?: string;
  userColor?: string;
}

// ── Formula editing ──

export interface FormulaBindingOption {
  value: string;
  label: string;
}

export interface FormulaSearchGroup {
  heading: string;
  items: FormulaBindingOption[];
}

export interface FormulaEditing {
  expression?: string;
  preview_latex?: string;
  result_latex?: string;
  result?: number | string | null;
  parse_error?: string;
  symbols?: string[];
  symbol_bindings?: Record<string, string>;
  same_row_options?: FormulaBindingOption[];
  search_results?: FormulaSearchGroup[];
  has_more?: boolean;
  row_id?: number | string;
  column_slug?: string;
  table_name?: string;
  row_name?: string;
  column_name?: string;
}

// ── Dashboard types ──

export interface DashboardStats {
  sheet_count: number;
  block_count: number;
  variable_count: number;
  variables_in_use: number;
  word_count: number;
}

export interface DashboardRow {
  id: number | string;
  name: string;
  block_count: number;
  variable_count: number;
  word_count: number;
  updated_at: string;
}

export interface DashboardPagination {
  sortBy: string;
  sortDir: string;
  page: number;
  totalPages: number;
  total: number;
}

export interface DashboardIssue {
  severity: string;
  message: string;
  href: string;
}

// ── Layout types ──

export interface FullWidthLayoutItem {
  type: "full_width";
  block: Block;
}

export interface ColumnGroupLayoutItem {
  type: "column_group";
  group_id: string;
  blocks: Block[];
  column_count: number;
}

export type LayoutItem = FullWidthLayoutItem | ColumnGroupLayoutItem;

// ── Tabs types ──

export interface TabDefinition {
  value: string;
  label: string;
  icon: FunctionalComponent;
  disabled?: boolean;
}

// ── Audio tab types ──

export interface AudioAsset {
  id: number | string;
  filename: string;
  url?: string;
  contentType?: string;
}

export interface VoiceLine {
  nodeId: number | string;
  flowId: number | string;
  text?: string;
  audioAsset?: AudioAsset | null;
}

export interface VoiceLineGroup {
  flow: {
    id: number | string;
    name: string;
    shortcut?: string;
  };
  lines: VoiceLine[];
}

// ── References tab types ──

export interface VariableRef {
  flowId?: number | string;
  flowName?: string;
  nodeId?: number | string;
  nodeType?: string;
  detail?: string;
  stale?: boolean;
  sourceType?: string;
  sceneId?: number | string;
  sceneName?: string;
  zoneName?: string;
}

export interface VariableUsageEntry {
  blockId: number | string;
  label: string;
  shortcut: string;
  type: string;
  reads: VariableRef[];
  writes: VariableRef[];
}

export interface BacklinkSourceInfo {
  type: string;
  name: string;
  shortcut?: string;
  sheetId?: number | string;
  flowId?: number | string;
  screenplayId?: number | string;
  sceneId?: number | string;
  contextType?: string;
  contextLabel?: string;
}

export interface Backlink {
  id: number | string;
  sourceId: number | string;
  sourceInfo: BacklinkSourceInfo;
  date?: string;
}

export interface SceneAppearance {
  sceneId: number | string;
  sceneName: string;
  elementType: string;
  elementName?: string;
}

// ── Search result types (ReferenceBlock) ──

export interface ReferenceSearchResult {
  id: number | string;
  type: string;
  name: string;
  shortcut?: string;
}

// ── Column header panel type ──

export type ColumnHeaderPanel = "main" | "type" | "options" | "number" | "reference";

// ── Stat card ──

export interface StatCard {
  icon: FunctionalComponent;
  label: string;
  value: number;
  color: string;
}

export interface DashboardColumn {
  key: string;
  label: string;
  align: "left" | "right";
}
