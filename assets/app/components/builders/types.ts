/**
 * Shared types for condition and instruction builders.
 */

import type { ConditionOperator } from "../../shared/domain/operators/condition-operators";
import type { InstructionOperator } from "../../shared/domain/operators/instruction-operators";

export interface ConditionRule {
  id: string;
  sheet: string | null;
  variable: string | null;
  operator: ConditionOperator;
  value: string | null;
}

export interface ConditionBlock {
  id: string;
  type: "block";
  logic: "all" | "any";
  rules: ConditionRule[];
  label?: string;
}

export interface ConditionGroup {
  id: string;
  type: "group";
  logic: "all" | "any";
  blocks: ConditionBlock[];
}

export interface ConditionData {
  logic: "all" | "any";
  blocks: (ConditionBlock | ConditionGroup)[];
}

export interface Assignment {
  operator: InstructionOperator;
  sheet: string | null;
  variable: string | null;
  value_type: "literal" | "variable_ref";
  value: string | null;
  value_sheet: string | null;
}
