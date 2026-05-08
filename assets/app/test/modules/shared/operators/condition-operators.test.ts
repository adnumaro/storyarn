import {
  operatorsForType,
  CONDITION_OPERATORS_BY_TYPE,
  OPERATOR_LABELS,
  NO_VALUE_OPERATORS,
} from "../../../../shared/domain/operators/condition-operators";
import type {
  ConditionOperator,
  VariableType,
} from "../../../../shared/domain/operators/condition-operators";

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

describe("OPERATOR_LABELS", () => {
  it("has a label for every operator used across all types", () => {
    const allOperators = new Set<ConditionOperator>();
    for (const ops of Object.values(CONDITION_OPERATORS_BY_TYPE)) {
      for (const op of ops) {
        allOperators.add(op);
      }
    }
    for (const op of allOperators) {
      expect(OPERATOR_LABELS[op]).toBeDefined();
      expect(typeof OPERATOR_LABELS[op]).toBe("string");
    }
  });

  it("has specific expected labels", () => {
    expect(OPERATOR_LABELS.equals).toBe("equals");
    expect(OPERATOR_LABELS.not_equals).toBe("not equals");
    expect(OPERATOR_LABELS.is_nil).toBe("is not set");
    expect(OPERATOR_LABELS.not_contains).toBe("does not contain");
    expect(OPERATOR_LABELS.greater_than_or_equal).toBe("greater than or equal");
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
