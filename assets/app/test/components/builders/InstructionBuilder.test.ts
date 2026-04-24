import { describe, it, expect } from "vitest";
import { mount } from "@vue/test-utils";
import InstructionBuilder from "@components/builders/InstructionBuilder.vue";
import type { Assignment } from "@components/builders/types";

function makeAssignment(overrides: Partial<Assignment> = {}): Assignment {
  return {
    operator: "set",
    sheet: "mc",
    variable: "health",
    value_type: "literal",
    value: "100",
    value_sheet: null,
    ...overrides,
  };
}

function mountBuilder(assignments: Assignment[] = [], extra: Record<string, unknown> = {}) {
  return mount(InstructionBuilder, {
    props: { assignments, ...extra },
    shallow: true,
  });
}

function lastEmitted(wrapper: ReturnType<typeof mount>): Assignment[] {
  // `wrapper.emitted(name)` returns `unknown[][]` — one outer array per emit
  // call, each inner array being that call's arg list. `update:assignments`
  // passes a single `Assignment[]`, so the correct cast is
  // `[Assignment[]][]` (array of one-arg tuples), not `Assignment[][]`
  // (which collapses the "call × args" shape into one dimension).
  const events = wrapper.emitted("update:assignments") as [Assignment[]][];
  return events[events.length - 1][0];
}

describe("InstructionBuilder", () => {
  describe("addAssignment", () => {
    it("adds a new assignment with defaults", async () => {
      const w = mountBuilder([]);
      await w.find("button").trigger("click");

      const emitted = lastEmitted(w);
      expect(emitted).toHaveLength(1);
      expect(emitted[0]).toMatchObject({
        operator: "set",
        sheet: null,
        variable: null,
        value_type: "literal",
        value: null,
        value_sheet: null,
      });
    });

    it("appends to existing assignments", async () => {
      const existing = makeAssignment();
      const w = mountBuilder([existing]);
      await w.find("button").trigger("click");

      const emitted = lastEmitted(w);
      expect(emitted).toHaveLength(2);
      expect(emitted[0].variable).toBe("health");
    });
  });

  describe("updateAssignment", () => {
    it("replaces the assignment at the given index", () => {
      const a1 = makeAssignment({ variable: "health" });
      const a2 = makeAssignment({ variable: "mana" });
      const w = mountBuilder([a1, a2]);

      const updated = { ...a1, value: "50" };
      const rows = w.findAllComponents({ name: "AssignmentRow" });
      rows[0].vm.$emit("update:assignment", updated);

      const emitted = lastEmitted(w);
      expect(emitted[0].value).toBe("50");
      expect(emitted[1].variable).toBe("mana");
    });
  });

  describe("removeAssignment", () => {
    it("removes the assignment at the given index", () => {
      const a1 = makeAssignment({ variable: "health" });
      const a2 = makeAssignment({ variable: "mana" });
      const w = mountBuilder([a1, a2]);

      const rows = w.findAllComponents({ name: "AssignmentRow" });
      rows[0].vm.$emit("remove");

      const emitted = lastEmitted(w);
      expect(emitted).toHaveLength(1);
      expect(emitted[0].variable).toBe("mana");
    });

    it("emits empty array when last assignment removed", () => {
      const w = mountBuilder([makeAssignment()]);
      w.findComponent({ name: "AssignmentRow" }).vm.$emit("remove");

      const emitted = lastEmitted(w);
      expect(emitted).toHaveLength(0);
    });
  });

  describe("disabled state", () => {
    it("hides add button when disabled", () => {
      const w = mountBuilder([], { disabled: true });
      expect(w.findAll("button")).toHaveLength(0);
    });

    it("shows empty state text when disabled with no assignments", () => {
      const w = mountBuilder([], { disabled: true });
      expect(w.text()).toContain("No assignments set");
    });

    it("does not show empty state when there are assignments", () => {
      const w = mountBuilder([makeAssignment()], { disabled: true });
      expect(w.text()).not.toContain("No assignments set");
    });
  });

  describe("reactivity", () => {
    it("updates internal state when prop changes", async () => {
      const w = mountBuilder([makeAssignment({ variable: "health" })]);

      await w.setProps({
        assignments: [makeAssignment({ variable: "mana" })],
      });

      // Add a new one to trigger emit and inspect state
      await w.find("button").trigger("click");
      const emitted = lastEmitted(w);
      expect(emitted[0].variable).toBe("mana");
      expect(emitted).toHaveLength(2);
    });
  });
});
