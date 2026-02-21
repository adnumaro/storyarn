/**
 * @vitest-environment jsdom
 */

import { CompletionContext } from "@codemirror/autocomplete";
import { EditorState } from "@codemirror/state";
import { describe, expect, it } from "vitest";
import { createVariableCompletionSource } from "../../expression_editor/autocomplete.js";

const TEST_VARIABLES = [
  { sheet_shortcut: "mc.jaime", variable_name: "health", block_type: "number" },
  { sheet_shortcut: "mc.jaime", variable_name: "class", block_type: "select" },
  { sheet_shortcut: "mc.jaime", variable_name: "alive", block_type: "boolean" },
  { sheet_shortcut: "mc.link", variable_name: "sword", block_type: "boolean" },
  { sheet_shortcut: "global", variable_name: "quest_progress", block_type: "number" },
  { sheet_shortcut: "global", variable_name: "fortress", block_type: "number" },
  { sheet_shortcut: "party", variable_name: "present", block_type: "boolean" },
];

const complete = createVariableCompletionSource(TEST_VARIABLES);

function getResult(doc, pos, explicit = false) {
  const state = EditorState.create({ doc });
  const context = new CompletionContext(state, pos, explicit);
  return complete(context);
}

describe("variableAutocomplete", () => {
  it("suggests sheet shortcuts when typing from scratch", () => {
    const result = getResult("mc", 2);
    expect(result).not.toBeNull();
    expect(result.options.length).toBeGreaterThan(0);

    const labels = result.options.map((o) => o.label);
    expect(labels).toContain("mc.jaime");
    expect(labels).toContain("mc.link");
  });

  it("suggests variables after sheet shortcut and dot", () => {
    const result = getResult("mc.jaime.", 9);
    expect(result).not.toBeNull();

    const labels = result.options.map((o) => o.label);
    expect(labels).toContain("health");
    expect(labels).toContain("class");
    expect(labels).toContain("alive");
  });

  it("shows block type as detail", () => {
    const result = getResult("mc.jaime.", 9);
    expect(result).not.toBeNull();

    const healthOption = result.options.find((o) => o.label === "health");
    expect(healthOption).toBeDefined();
    expect(healthOption.detail).toBe("(number)");
  });

  it("filters variables by prefix", () => {
    const result = getResult("mc.jaime.he", 11);
    expect(result).not.toBeNull();

    const labels = result.options.map((o) => o.label);
    expect(labels).toContain("health");
    expect(labels).not.toContain("class");
    expect(labels).not.toContain("alive");
  });

  it("returns no completions for unknown prefix", () => {
    const result = getResult("zzz", 3);
    expect(result === null || result.options.length === 0).toBe(true);
  });

  it("suggests single-segment sheets", () => {
    const result = getResult("gl", 2);
    expect(result).not.toBeNull();

    const labels = result.options.map((o) => o.label);
    expect(labels).toContain("global");
  });

  it("appends dot to sheet selection", () => {
    const result = getResult("gl", 2);
    expect(result).not.toBeNull();

    const globalOption = result.options.find((o) => o.label === "global");
    expect(globalOption).toBeDefined();
    expect(globalOption.apply).toBe("global.");
  });

  it("handles explicit activation on empty input", () => {
    const result = getResult("", 0, true);
    expect(result).not.toBeNull();
    const labels = result.options.map((o) => o.label);
    expect(labels.length).toBeGreaterThan(0);
  });
});

describe("table variable autocomplete", () => {
  const TABLE_VARIABLES = [
    ...TEST_VARIABLES,
    {
      sheet_shortcut: "mc.jaime",
      variable_name: "attributes.strength.value",
      block_type: "number",
      table_name: "attributes",
      row_name: "strength",
      column_name: "value",
    },
    {
      sheet_shortcut: "mc.jaime",
      variable_name: "attributes.strength.max",
      block_type: "number",
      table_name: "attributes",
      row_name: "strength",
      column_name: "max",
    },
    {
      sheet_shortcut: "mc.jaime",
      variable_name: "attributes.wisdom.value",
      block_type: "number",
      table_name: "attributes",
      row_name: "wisdom",
      column_name: "value",
    },
  ];

  const completeTable = createVariableCompletionSource(TABLE_VARIABLES);

  function getTableResult(doc, pos, explicit = false) {
    const state = EditorState.create({ doc });
    const context = new CompletionContext(state, pos, explicit);
    return completeTable(context);
  }

  it("shows regular vars and table names after sheet.", () => {
    const result = getTableResult("mc.jaime.", 9);
    expect(result).not.toBeNull();
    const labels = result.options.map((o) => o.label);
    expect(labels).toContain("health");
    expect(labels).toContain("attributes");
  });

  it("marks table names as namespace with arrow detail", () => {
    const result = getTableResult("mc.jaime.", 9);
    const tableOpt = result.options.find((o) => o.label === "attributes");
    expect(tableOpt).toBeDefined();
    expect(tableOpt.type).toBe("namespace");
    expect(tableOpt.apply).toBe("attributes.");
  });

  it("shows row names after sheet.table.", () => {
    const result = getTableResult("mc.jaime.attributes.", 20);
    expect(result).not.toBeNull();
    const labels = result.options.map((o) => o.label);
    expect(labels).toContain("strength");
    expect(labels).toContain("wisdom");
  });

  it("shows column names after sheet.table.row.", () => {
    const result = getTableResult("mc.jaime.attributes.strength.", 29);
    expect(result).not.toBeNull();
    const labels = result.options.map((o) => o.label);
    expect(labels).toContain("value");
    expect(labels).toContain("max");
  });

  it("filters columns by prefix", () => {
    const result = getTableResult("mc.jaime.attributes.strength.v", 30);
    expect(result).not.toBeNull();
    const labels = result.options.map((o) => o.label);
    expect(labels).toContain("value");
    expect(labels).not.toContain("max");
  });

  it("filters row names by prefix", () => {
    const result = getTableResult("mc.jaime.attributes.str", 23);
    expect(result).not.toBeNull();
    const labels = result.options.map((o) => o.label);
    expect(labels).toContain("strength");
    expect(labels).not.toContain("wisdom");
  });

  it("filters table names and regular vars by prefix", () => {
    const result = getTableResult("mc.jaime.a", 10);
    expect(result).not.toBeNull();
    const labels = result.options.map((o) => o.label);
    expect(labels).toContain("attributes");
    expect(labels).toContain("alive");
    expect(labels).not.toContain("health");
  });

  it("shows column detail with block type", () => {
    const result = getTableResult("mc.jaime.attributes.strength.", 29);
    const valueOpt = result.options.find((o) => o.label === "value");
    expect(valueOpt.detail).toBe("(number)");
  });
});
