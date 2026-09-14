import type { Component } from "vue";
import {
  Calendar,
  Columns2,
  CornerDownRight,
  FileText,
  Film,
  GitBranch,
  Group,
  Hash,
  Heading,
  Hexagon,
  Image,
  Images,
  Lightbulb,
  Link2,
  ListChecks,
  List,
  Map,
  MapPin,
  MessageSquare,
  PanelTop,
  Play,
  Route,
  Split,
  Square,
  SquareDashed,
  StickyNote,
  Table2,
  Tag,
  Terminal,
  ToggleLeft,
  Type,
  Workflow,
} from "@lucide/vue";

export type CommentToolKey = "sheet" | "flow" | "scene" | "brainstorming";

export interface CommentToolMeta {
  key: CommentToolKey;
  icon: Component;
  /** Tailwind text colour of the tool, shared by pins, rows and reference strips. */
  colorClass: string;
}

const TOOLS: Record<CommentToolKey, CommentToolMeta> = {
  sheet: { key: "sheet", icon: FileText, colorClass: "text-[hsl(210_70%_62%)]" },
  flow: { key: "flow", icon: GitBranch, colorClass: "text-[hsl(265_60%_68%)]" },
  scene: { key: "scene", icon: Map, colorClass: "text-[hsl(30_80%_60%)]" },
  brainstorming: { key: "brainstorming", icon: Lightbulb, colorClass: "text-[hsl(48_85%_58%)]" },
};

/** Which tool owns a thread, from its source type. */
export function commentToolKey(sourceType: string): CommentToolKey {
  if (sourceType.startsWith("flow_")) return "flow";
  if (sourceType.startsWith("sheet_")) return "sheet";
  if (sourceType.startsWith("scene_")) return "scene";
  return "brainstorming";
}

export function commentTool(sourceType: string): CommentToolMeta {
  return TOOLS[commentToolKey(sourceType)];
}

const KIND_ICONS: Record<string, Component> = {
  text: Type,
  rich_text: Type,
  number: Hash,
  boolean: ToggleLeft,
  date: Calendar,
  select: List,
  multi_select: ListChecks,
  table: Table2,
  reference: Link2,
  gallery: Images,
  cover: Image,
  header: PanelTop,
  title: Heading,
  row: Columns2,
  dialogue: MessageSquare,
  entry: Play,
  exit: Square,
  condition: Split,
  instruction: Terminal,
  hub: Hexagon,
  jump: CornerDownRight,
  subflow: Workflow,
  annotation: StickyNote,
  sequence: Film,
  pin: MapPin,
  zone: SquareDashed,
  connection: Route,
  idea: StickyNote,
  group: Group,
};

const CONTEXT_TYPE_KINDS: Record<string, string> = {
  sheet_cover: "cover",
  sheet_header: "header",
  sheet_title: "title",
  sheet_column_group: "row",
  flow_node: "dialogue",
  scene_pin: "pin",
  scene_zone: "zone",
  scene_connection: "connection",
  scene_annotation: "annotation",
  ideation_idea: "idea",
  ideation_group: "group",
};

/** The kind of a context target: its preview kind when known, otherwise derived from the type. */
export function commentContextKind(type: string, kind?: string | null): string {
  return kind ?? CONTEXT_TYPE_KINDS[type] ?? "text";
}

export function commentContextIcon(type: string, kind?: string | null): Component {
  return KIND_ICONS[commentContextKind(type, kind)] ?? Tag;
}
