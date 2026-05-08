import { describe, it, expect, vi, beforeEach } from "vitest";
import { defineComponent, nextTick } from "vue";
import { mount } from "@vue/test-utils";
import AssignmentRow from "@components/builders/instruction/AssignmentRow.vue";
import type { Variable } from "@modules/shared/variables";
import type { Assignment } from "@components/builders/types";

/**
 * Same stub strategy as ConditionRule: per-instance focus spies tagged by
 * placeholder. Filtering by placeholder ("sheet" / "variable" / "value-sheet"
 * / "value") lets us assert the right combobox advanced.
 *
 * AssignmentRow's slot placeholders come from the operator template
 * (`getTemplate(operator)`), so we have to be a bit defensive — the actual
 * placeholder text passed to VariableCombobox depends on the operator.
 * To keep tests stable we match by `key` via a custom `data-key` attribute
 * the stub reads from props (forwarded via `placeholder`).
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
];

function makeAssignment(overrides: Partial<Assignment> = {}): Assignment {
  return {
    operator: "set",
    sheet: null,
    variable: null,
    value_type: "literal",
    value: null,
    value_sheet: null,
    ...overrides,
  };
}

function mountIt(
  props: Partial<{ assignment: Assignment; variables: Variable[]; disabled: boolean }> = {},
) {
  stubs.length = 0;
  return mount(AssignmentRow, {
    props: {
      assignment: makeAssignment(),
      variables: VARIABLES,
      disabled: false,
      ...props,
    },
    global: {
      stubs: { VariableCombobox: VariableComboboxStub },
    },
  });
}

/** Find the focus spy whose stub had the matching placeholder substring.
 * Placeholders come from operator templates and may be localised; matching
 * substring keeps tests resilient. */
function pickerFocus(placeholderLike: string) {
  return stubs.find((s) => s.placeholder.toLowerCase().includes(placeholderLike.toLowerCase()))
    ?.focus;
}

describe("AssignmentRow — auto-advance focus chain", () => {
  beforeEach(() => {
    stubs.length = 0;
  });

  it("after picking sheet, focuses the variable combobox", async () => {
    const w = mountIt();
    const sheetCb = w
      .findAllComponents(VariableComboboxStub)
      .find((c) => /sheet/i.test(String(c.props("placeholder"))));
    sheetCb!.vm.$emit("update:modelValue", "mc");
    await nextTick();
    await nextTick();
    expect(pickerFocus("variable")).toHaveBeenCalledTimes(1);
  });

  it("after picking variable in literal mode, focuses the value combobox", async () => {
    const w = mountIt({ assignment: makeAssignment({ sheet: "mc", value_type: "literal" }) });
    const varCb = w
      .findAllComponents(VariableComboboxStub)
      .find((c) => /variable/i.test(String(c.props("placeholder"))));
    varCb!.vm.$emit("update:modelValue", "health");
    await nextTick();
    await nextTick();
    expect(pickerFocus("value")).toHaveBeenCalledTimes(1);
  });

  it("after picking variable in variable_ref mode, focuses the value_sheet combobox", async () => {
    const w = mountIt({ assignment: makeAssignment({ sheet: "mc", value_type: "variable_ref" }) });
    const varCb = w
      .findAllComponents(VariableComboboxStub)
      .find((c) => /variable/i.test(String(c.props("placeholder"))));
    varCb!.vm.$emit("update:modelValue", "health");
    await nextTick();
    await nextTick();
    // value_sheet picker is looked up by its placeholder containing "sheet"
    // again — but the rule sheet has already been picked, so the matching
    // call belongs to value_sheet.
    const sheetSpies = stubs.filter((s) => /sheet/i.test(s.placeholder)).map((s) => s.focus);
    // At least one of the sheet-placeholder spies should have been called
    // (the value_sheet one). The original `sheet` spy would not — focus()
    // is only called on the next combobox in the chain.
    expect(sheetSpies.some((spy) => spy.mock.calls.length > 0)).toBe(true);
  });

  it("after picking value_sheet, focuses the value combobox", async () => {
    const w = mountIt({
      assignment: makeAssignment({ sheet: "mc", variable: "health", value_type: "variable_ref" }),
    });
    // In variable_ref mode the template expands to: sheet, variable,
    // value_sheet (placeholder="sheet"), value (placeholder="variable").
    // We can't pick value_sheet by placeholder alone — sheet is also "sheet".
    // Pick the LAST combobox whose placeholder is "sheet" (template ordering
    // puts value_sheet after sheet).
    const allCb = w.findAllComponents(VariableComboboxStub);
    const sheetLike = allCb.filter((c) => /sheet/i.test(String(c.props("placeholder"))));
    expect(sheetLike.length).toBeGreaterThanOrEqual(2);
    sheetLike[sheetLike.length - 1]!.vm.$emit("update:modelValue", "mc");
    await nextTick();
    await nextTick();
    // The value combobox in variable_ref mode has placeholder "variable" —
    // it's the LAST mounted combobox in the row. Asserting "exactly one
    // focus was called" + "that focus belongs to the last combobox" is the
    // most robust way without inspecting the slot key.
    const calledSpies = stubs.filter((s) => s.focus.mock.calls.length > 0);
    expect(calledSpies).toHaveLength(1);
    expect(stubs[stubs.length - 1].focus).toHaveBeenCalledTimes(1);
  });
});
