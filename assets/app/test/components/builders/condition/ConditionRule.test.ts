import { describe, it, expect, vi, beforeEach } from "vitest";
import { defineComponent, nextTick } from "vue";
import { mount } from "@vue/test-utils";
import ConditionRule from "@components/builders/condition/ConditionRule.vue";
import type { Variable } from "../../../../shared/domain/variables";
import type { ConditionRule as ConditionRuleData } from "@components/builders/types";

/**
 * Each VariableCombobox stub gets its own `focus` spy. We collect every
 * stub instance in `stubs[]` so tests can assert which one was focused
 * after a parent update.
 */
const stubs: Array<{ placeholder: string; focus: ReturnType<typeof vi.fn> }> = [];

const VariableComboboxStub = defineComponent({
  name: "VariableCombobox",
  props: {
    modelValue: { type: String, default: "" },
    options: { type: Array, default: () => [] },
    groups: { type: Array, default: () => [] },
    placeholder: { type: String, default: "" },
    disabled: { type: Boolean, default: false },
    emptyText: { type: String, default: "" },
    freeText: { type: Boolean, default: false },
    inputType: { type: String, default: "text" },
  },
  emits: ["update:modelValue"],
  setup(props, { expose }) {
    const focus = vi.fn();
    stubs.push({ placeholder: props.placeholder, focus });
    expose({ focus });
    return { focus };
  },
  template: '<button :data-stub-placeholder="placeholder" />',
});

const VARIABLES: Variable[] = [
  {
    sheet_shortcut: "mc",
    sheet_name: "Main Character",
    variable_name: "health",
    block_type: "number",
  },
  {
    sheet_shortcut: "mc",
    sheet_name: "Main Character",
    variable_name: "alive",
    block_type: "boolean",
  },
];

function makeRule(overrides: Partial<ConditionRuleData> = {}): ConditionRuleData {
  return {
    id: "r1",
    sheet: null,
    variable: null,
    operator: "equals",
    value: null,
    ...overrides,
  };
}

function mountIt(
  props: Partial<{ rule: ConditionRuleData; variables: Variable[]; disabled: boolean }> = {},
) {
  stubs.length = 0;
  return mount(ConditionRule, {
    props: {
      rule: makeRule(),
      variables: VARIABLES,
      disabled: false,
      ...props,
    },
    global: {
      stubs: { VariableCombobox: VariableComboboxStub },
    },
  });
}

function pickerFocus(placeholder: string) {
  return stubs.find((s) => s.placeholder === placeholder)?.focus;
}

describe("ConditionRule — auto-advance focus chain", () => {
  beforeEach(() => {
    stubs.length = 0;
  });

  it("after picking sheet, focuses the variable combobox", async () => {
    const w = mountIt();
    const sheetCb = w
      .findAllComponents(VariableComboboxStub)
      .find((c) => c.props("placeholder") === "sheet");
    sheetCb!.vm.$emit("update:modelValue", "mc");
    await nextTick();
    await nextTick();
    expect(pickerFocus("variable")).toHaveBeenCalledTimes(1);
    expect(pickerFocus("op")).not.toHaveBeenCalled();
    expect(pickerFocus("value")).not.toHaveBeenCalled();
  });

  it("after picking variable, focuses the operator combobox (operator needs a value)", async () => {
    const w = mountIt({ rule: makeRule({ sheet: "mc" }) });
    const varCb = w
      .findAllComponents(VariableComboboxStub)
      .find((c) => c.props("placeholder") === "variable");
    varCb!.vm.$emit("update:modelValue", "health");
    await nextTick();
    await nextTick();
    // For block_type=number, first operator is "equals" (needs value), so focus operator.
    expect(pickerFocus("op")).toHaveBeenCalledTimes(1);
  });

  it("after picking variable, skips operator/value when auto-operator is NO_VALUE_OPERATORS (boolean → is_true)", async () => {
    const w = mountIt({ rule: makeRule({ sheet: "mc" }) });
    const varCb = w
      .findAllComponents(VariableComboboxStub)
      .find((c) => c.props("placeholder") === "variable");
    varCb!.vm.$emit("update:modelValue", "alive");
    await nextTick();
    await nextTick();
    // For boolean, first operator is "is_true" → no value needed → no advance.
    expect(pickerFocus("op")).not.toHaveBeenCalled();
    expect(pickerFocus("value")).not.toHaveBeenCalled();
  });

  it("after picking operator that needs a value, focuses the value combobox", async () => {
    const w = mountIt({ rule: makeRule({ sheet: "mc", variable: "health" }) });
    const opCb = w
      .findAllComponents(VariableComboboxStub)
      .find((c) => c.props("placeholder") === "op");
    opCb!.vm.$emit("update:modelValue", "greater_than");
    await nextTick();
    await nextTick();
    expect(pickerFocus("value")).toHaveBeenCalledTimes(1);
  });

  it("after picking operator that does NOT need a value (is_empty), no advance", async () => {
    const w = mountIt({
      rule: makeRule({ sheet: "mc", variable: "health", operator: "equals" }),
    });
    const opCb = w
      .findAllComponents(VariableComboboxStub)
      .find((c) => c.props("placeholder") === "op");
    opCb!.vm.$emit("update:modelValue", "is_empty");
    await nextTick();
    await nextTick();
    expect(pickerFocus("value")).not.toHaveBeenCalled();
  });
});
