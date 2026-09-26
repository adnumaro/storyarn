import {
  operatorsForType,
  CONDITION_OPERATORS_BY_TYPE,
  OPERATOR_LABEL_KEYS,
  NO_VALUE_OPERATORS,
} from "@modules/flows/editor/expression/domain/condition-operators";
import type {
  ConditionOperator,
  VariableType,
} from "@modules/flows/editor/expression/domain/condition-operators";
import enCommon from "../../../../locales/en/common.json";
import esCommon from "../../../../locales/es/common.json";

type Messages = { [key: string]: string | Messages };

// Reads a translation straight from a locale file, so a missing key fails.
function message(messages: Messages, key: string): string | undefined {
  let node: string | Messages | undefined = messages;
  for (const part of key.split(".")) node = typeof node === "object" ? node[part] : undefined;
  return typeof node === "string" ? node : undefined;
}

const en = enCommon as Messages;
const es = esCommon as Messages;

describe("operatorsForType", () => {
  it("returns text operators for type 'text'", () => {
    expect(operatorsForType("text")).toEqual([
      "equals",
      "not_equals",
      "contains",
      "starts_with",
      "ends_with",
      "is_empty",
    ]);
  });

  it("returns rich_text operators (same as text)", () => {
    expect(operatorsForType("rich_text")).toEqual([
      "equals",
      "not_equals",
      "contains",
      "starts_with",
      "ends_with",
      "is_empty",
    ]);
  });

  it("returns number operators", () => {
    expect(operatorsForType("number")).toEqual([
      "equals",
      "not_equals",
      "greater_than",
      "greater_than_or_equal",
      "less_than",
      "less_than_or_equal",
    ]);
  });

  it("returns boolean operators", () => {
    expect(operatorsForType("boolean")).toEqual(["is_true", "is_false", "is_nil"]);
  });

  it("returns select operators", () => {
    expect(operatorsForType("select")).toEqual(["equals", "not_equals", "is_nil"]);
  });

  it("returns multi_select operators", () => {
    expect(operatorsForType("multi_select")).toEqual(["contains", "not_contains", "is_empty"]);
  });

  it("returns date operators", () => {
    expect(operatorsForType("date")).toEqual(["equals", "not_equals", "before", "after"]);
  });

  it("returns reference operators", () => {
    expect(operatorsForType("reference")).toEqual(["equals", "not_equals", "is_nil"]);
  });

  it("falls back to text operators for unknown types", () => {
    expect(operatorsForType("unknown_type")).toEqual(CONDITION_OPERATORS_BY_TYPE.text);
    expect(operatorsForType("")).toEqual(CONDITION_OPERATORS_BY_TYPE.text);
  });
});

describe("OPERATOR_LABEL_KEYS", () => {
  it("has a label in English and Spanish for every operator used across all types", () => {
    const allOperators = new Set<ConditionOperator>();
    for (const ops of Object.values(CONDITION_OPERATORS_BY_TYPE)) {
      for (const op of ops) {
        allOperators.add(op);
      }
    }
    for (const op of allOperators) {
      expect(message(en, OPERATOR_LABEL_KEYS[op])).toBeTruthy();
      expect(message(es, OPERATOR_LABEL_KEYS[op])).toBeTruthy();
    }
  });

  it("labels operators in the viewer's language", () => {
    expect(message(en, OPERATOR_LABEL_KEYS.not_equals)).toBe("not equals");
    expect(message(en, OPERATOR_LABEL_KEYS.is_nil)).toBe("is not set");
    expect(message(es, OPERATOR_LABEL_KEYS.not_equals)).toBe("no es igual a");
    expect(message(es, OPERATOR_LABEL_KEYS.greater_than_or_equal)).toBe("mayor o igual que");
  });
});

describe("NO_VALUE_OPERATORS", () => {
  it("contains the correct operators that need no value", () => {
    expect(NO_VALUE_OPERATORS.has("is_empty")).toBe(true);
    expect(NO_VALUE_OPERATORS.has("is_true")).toBe(true);
    expect(NO_VALUE_OPERATORS.has("is_false")).toBe(true);
    expect(NO_VALUE_OPERATORS.has("is_nil")).toBe(true);
  });

  it("does not include operators that require a value", () => {
    expect(NO_VALUE_OPERATORS.has("equals")).toBe(false);
    expect(NO_VALUE_OPERATORS.has("not_equals")).toBe(false);
    expect(NO_VALUE_OPERATORS.has("greater_than")).toBe(false);
    expect(NO_VALUE_OPERATORS.has("contains")).toBe(false);
    expect(NO_VALUE_OPERATORS.has("before")).toBe(false);
  });

  it("has exactly 4 entries", () => {
    expect(NO_VALUE_OPERATORS.size).toBe(4);
  });
});

describe("CONDITION_OPERATORS_BY_TYPE completeness", () => {
  const expectedTypes: VariableType[] = [
    "text",
    "rich_text",
    "number",
    "boolean",
    "select",
    "multi_select",
    "date",
    "reference",
  ];

  it("covers all variable types", () => {
    for (const type of expectedTypes) {
      expect(CONDITION_OPERATORS_BY_TYPE[type]).toBeDefined();
      expect(CONDITION_OPERATORS_BY_TYPE[type].length).toBeGreaterThan(0);
    }
  });
});
