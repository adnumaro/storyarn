import {
  Calendar,
  CircleDot,
  Columns2,
  Hash,
  Link,
  List,
  Sigma,
  ToggleLeft,
  Type,
} from "lucide-vue-next";
import type { FunctionalComponent } from "vue";

export type TableColumnType =
  | "number"
  | "text"
  | "boolean"
  | "select"
  | "multi_select"
  | "date"
  | "formula"
  | "reference";

export const typeIcons: Record<string, FunctionalComponent> = {
  number: Hash,
  text: Type,
  boolean: ToggleLeft,
  select: CircleDot,
  multi_select: List,
  date: Calendar,
  formula: Sigma,
  reference: Link,
};

export const typeLabels: Record<string, string> = {
  number: "Number",
  text: "Text",
  boolean: "Boolean",
  select: "Select",
  multi_select: "Multi Select",
  date: "Date",
  reference: "Reference",
  formula: "Formula",
};

export const allTypes: TableColumnType[] = [
  "number",
  "text",
  "boolean",
  "select",
  "multi_select",
  "date",
  "reference",
  "formula",
];

export function typeIcon(type: string): FunctionalComponent {
  return typeIcons[type] || Columns2;
}
