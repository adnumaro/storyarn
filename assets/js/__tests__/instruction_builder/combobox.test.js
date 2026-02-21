/**
 * Tests for the instruction_builder combobox component.
 *
 * Covers: grouped rendering, inline search filtering (by label, value,
 * group, meta), "No matches" state, keyboard navigation, free-text mode,
 * and basic select behaviour.
 *
 * @vitest-environment jsdom
 */

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { createCombobox } from "../../instruction_builder/combobox.js";

// jsdom doesn't implement scrollIntoView
Element.prototype.scrollIntoView = Element.prototype.scrollIntoView || (() => {});

// -- DOM helpers --

function container() {
  const el = document.createElement("div");
  document.body.appendChild(el);
  return el;
}

/** Returns the body-appended dropdown that createCombobox creates. */
function dropdown() {
  return document.querySelector(".combobox-dropdown");
}

function visibleOptions() {
  const dd = dropdown();
  if (!dd) return [];
  return [...dd.querySelectorAll(".combobox-option")];
}

function groupHeaders() {
  const dd = dropdown();
  if (!dd) return [];
  return [...dd.querySelectorAll(".combobox-group-header")];
}

function fire(el, event, opts = {}) {
  el.dispatchEvent(new Event(event, { bubbles: true, ...opts }));
}

function fireKeydown(el, key) {
  el.dispatchEvent(new KeyboardEvent("keydown", { key, bubbles: true }));
}

// -- Fixtures --

const FLAT_OPTIONS = [
  { value: "a", label: "Alpha" },
  { value: "b", label: "Beta" },
  { value: "c", label: "Charlie" },
];

const GROUPED_OPTIONS = [
  { value: "health", label: "health", group: "mc.jaime", meta: "number" },
  { value: "class", label: "class", group: "mc.jaime", meta: "select" },
  { value: "alive", label: "alive", group: "mc.jaime", meta: "boolean" },
  { value: "quest_progress", label: "quest_progress", group: "global", meta: "number" },
  { value: "fortress", label: "fortress", group: "global", meta: "number" },
];

// -- Tests --

describe("createCombobox", () => {
  let el;
  let cb;

  beforeEach(() => {
    el = container();
  });

  afterEach(() => {
    cb?.destroy();
    el?.remove();
    // Clean up any stray dropdowns
    document.querySelectorAll(".combobox-dropdown").forEach((d) => {
      d.remove();
    });
  });

  // =========================================================================
  // Basic behaviour
  // =========================================================================

  describe("basic behaviour", () => {
    it("renders an input element", () => {
      cb = createCombobox({ container: el, options: FLAT_OPTIONS });
      expect(el.querySelector("input")).toBeTruthy();
    });

    it("appends dropdown to document.body", () => {
      cb = createCombobox({ container: el, options: FLAT_OPTIONS });
      expect(dropdown()).toBeTruthy();
      expect(dropdown().parentElement).toBe(document.body);
    });

    it("shows placeholder text", () => {
      cb = createCombobox({
        container: el,
        options: FLAT_OPTIONS,
        placeholder: "pick one",
      });
      expect(cb.input.placeholder).toBe("pick one");
    });

    it("shows displayValue in input", () => {
      cb = createCombobox({
        container: el,
        options: FLAT_OPTIONS,
        value: "a",
        displayValue: "Alpha",
      });
      expect(cb.input.value).toBe("Alpha");
    });

    it("adds 'filled' class when value is set", () => {
      cb = createCombobox({
        container: el,
        options: FLAT_OPTIONS,
        value: "a",
      });
      expect(cb.input.classList.contains("filled")).toBe(true);
    });
  });

  // =========================================================================
  // Dropdown open / close
  // =========================================================================

  describe("dropdown open/close", () => {
    it("opens dropdown on focus", () => {
      cb = createCombobox({ container: el, options: FLAT_OPTIONS });
      fire(cb.input, "focus");
      expect(dropdown().style.display).toBe("block");
    });

    it("renders all options when opened", () => {
      cb = createCombobox({ container: el, options: FLAT_OPTIONS });
      fire(cb.input, "focus");
      expect(visibleOptions()).toHaveLength(3);
    });

    it("does not open dropdown when disabled", () => {
      cb = createCombobox({
        container: el,
        options: FLAT_OPTIONS,
        disabled: true,
      });
      fire(cb.input, "focus");
      expect(dropdown().style.display).not.toBe("block");
    });
  });

  // =========================================================================
  // Grouped rendering
  // =========================================================================

  describe("grouped rendering", () => {
    it("renders group headers when options have group property", () => {
      cb = createCombobox({ container: el, options: GROUPED_OPTIONS });
      fire(cb.input, "focus");

      const headers = groupHeaders();
      expect(headers).toHaveLength(2);
      expect(headers[0].textContent).toBe("mc.jaime");
      expect(headers[1].textContent).toBe("global");
    });

    it("renders options under their group headers", () => {
      cb = createCombobox({ container: el, options: GROUPED_OPTIONS });
      fire(cb.input, "focus");

      const dd = dropdown();
      const children = [...dd.children];
      // Structure: header, opt, opt, opt, header, opt, opt
      expect(children).toHaveLength(7); // 2 headers + 5 options
      expect(children[0].classList.contains("combobox-group-header")).toBe(true);
      expect(children[0].textContent).toBe("mc.jaime");
      expect(children[1].classList.contains("combobox-option")).toBe(true);
      expect(children[1].textContent).toContain("health");
    });

    it("shows meta in parentheses when present", () => {
      cb = createCombobox({ container: el, options: GROUPED_OPTIONS });
      fire(cb.input, "focus");

      const opts = visibleOptions();
      expect(opts[0].textContent).toContain("(number)");
    });

    it("does not render group headers for ungrouped options", () => {
      cb = createCombobox({ container: el, options: FLAT_OPTIONS });
      fire(cb.input, "focus");

      expect(groupHeaders()).toHaveLength(0);
      expect(visibleOptions()).toHaveLength(3);
    });
  });

  // =========================================================================
  // Search filtering
  // =========================================================================

  describe("search filtering", () => {
    it("filters options by label", () => {
      cb = createCombobox({ container: el, options: GROUPED_OPTIONS });
      fire(cb.input, "focus");
      cb.input.value = "health";
      fire(cb.input, "input");

      expect(visibleOptions()).toHaveLength(1);
      expect(visibleOptions()[0].textContent).toContain("health");
    });

    it("filters options by group name", () => {
      cb = createCombobox({ container: el, options: GROUPED_OPTIONS });
      fire(cb.input, "focus");
      cb.input.value = "jaime";
      fire(cb.input, "input");

      // All 3 mc.jaime variables should show
      expect(visibleOptions()).toHaveLength(3);
      expect(groupHeaders()).toHaveLength(1);
      expect(groupHeaders()[0].textContent).toBe("mc.jaime");
    });

    it("filters options by meta", () => {
      cb = createCombobox({ container: el, options: GROUPED_OPTIONS });
      fire(cb.input, "focus");
      cb.input.value = "boolean";
      fire(cb.input, "input");

      expect(visibleOptions()).toHaveLength(1);
      expect(visibleOptions()[0].textContent).toContain("alive");
    });

    it("filters options by value", () => {
      cb = createCombobox({ container: el, options: GROUPED_OPTIONS });
      fire(cb.input, "focus");
      cb.input.value = "quest";
      fire(cb.input, "input");

      expect(visibleOptions()).toHaveLength(1);
      expect(visibleOptions()[0].textContent).toContain("quest_progress");
    });

    it("shows all options when search is empty", () => {
      cb = createCombobox({ container: el, options: GROUPED_OPTIONS });
      fire(cb.input, "focus");
      cb.input.value = "jaime";
      fire(cb.input, "input");
      expect(visibleOptions()).toHaveLength(3);

      // Clear search
      cb.input.value = "";
      fire(cb.input, "input");
      expect(visibleOptions()).toHaveLength(5);
    });

    it("is case-insensitive", () => {
      cb = createCombobox({ container: el, options: GROUPED_OPTIONS });
      fire(cb.input, "focus");
      cb.input.value = "HEALTH";
      fire(cb.input, "input");

      expect(visibleOptions()).toHaveLength(1);
    });

    it("hides group headers when no options match in that group", () => {
      cb = createCombobox({ container: el, options: GROUPED_OPTIONS });
      fire(cb.input, "focus");
      cb.input.value = "fortress";
      fire(cb.input, "input");

      // Only "global" group should show
      const headers = groupHeaders();
      expect(headers).toHaveLength(1);
      expect(headers[0].textContent).toBe("global");
    });
  });

  // =========================================================================
  // No matches state
  // =========================================================================

  describe("no matches state", () => {
    it("shows 'No matches' when no options match the search", () => {
      cb = createCombobox({ container: el, options: GROUPED_OPTIONS });
      fire(cb.input, "focus");
      cb.input.value = "zzzzz";
      fire(cb.input, "input");

      expect(visibleOptions()).toHaveLength(0);
      expect(groupHeaders()).toHaveLength(0);

      const dd = dropdown();
      expect(dd.textContent).toContain("No matches");
    });

    it("shows 'No matches' for flat options too", () => {
      cb = createCombobox({ container: el, options: FLAT_OPTIONS });
      fire(cb.input, "focus");
      cb.input.value = "zzzzz";
      fire(cb.input, "input");

      expect(dropdown().textContent).toContain("No matches");
    });
  });

  // =========================================================================
  // Keyboard navigation
  // =========================================================================

  describe("keyboard navigation", () => {
    it("highlights first option by default on open", () => {
      cb = createCombobox({ container: el, options: FLAT_OPTIONS });
      fire(cb.input, "focus");

      const opts = visibleOptions();
      expect(opts[0].classList.contains("highlighted")).toBe(true);
    });

    it("moves highlight down with ArrowDown", () => {
      cb = createCombobox({ container: el, options: FLAT_OPTIONS });
      fire(cb.input, "focus");
      fireKeydown(cb.input, "ArrowDown");

      const opts = visibleOptions();
      expect(opts[1].classList.contains("highlighted")).toBe(true);
    });

    it("moves highlight up with ArrowUp", () => {
      cb = createCombobox({ container: el, options: FLAT_OPTIONS });
      fire(cb.input, "focus");
      fireKeydown(cb.input, "ArrowDown");
      fireKeydown(cb.input, "ArrowUp");

      const opts = visibleOptions();
      expect(opts[0].classList.contains("highlighted")).toBe(true);
    });

    it("selects highlighted option on Enter", () => {
      const onSelect = vi.fn();
      cb = createCombobox({
        container: el,
        options: FLAT_OPTIONS,
        onSelect,
      });
      fire(cb.input, "focus");
      fireKeydown(cb.input, "Enter");

      expect(onSelect).toHaveBeenCalledWith(
        expect.objectContaining({ value: "a", confirmed: true }),
      );
    });

    it("closes dropdown on Escape", () => {
      cb = createCombobox({ container: el, options: FLAT_OPTIONS });
      fire(cb.input, "focus");
      expect(dropdown().style.display).toBe("block");

      fireKeydown(cb.input, "Escape");
      expect(dropdown().style.display).not.toBe("block");
    });
  });

  // =========================================================================
  // Selection
  // =========================================================================

  describe("selection", () => {
    it("calls onSelect when an option is clicked", () => {
      const onSelect = vi.fn();
      cb = createCombobox({
        container: el,
        options: FLAT_OPTIONS,
        onSelect,
      });
      fire(cb.input, "focus");

      const opts = visibleOptions();
      opts[1].dispatchEvent(new MouseEvent("mousedown", { bubbles: true }));

      expect(onSelect).toHaveBeenCalledWith(
        expect.objectContaining({ value: "b", confirmed: true }),
      );
    });

    it("updates input value after selection", () => {
      cb = createCombobox({ container: el, options: FLAT_OPTIONS });
      fire(cb.input, "focus");

      const opts = visibleOptions();
      opts[2].dispatchEvent(new MouseEvent("mousedown", { bubbles: true }));

      expect(cb.input.value).toBe("Charlie");
    });

    it("uses displayValue from option when available", () => {
      const opts = [{ value: "x", label: "X Label", displayValue: "X Display" }];
      cb = createCombobox({ container: el, options: opts });
      fire(cb.input, "focus");

      visibleOptions()[0].dispatchEvent(new MouseEvent("mousedown", { bubbles: true }));

      expect(cb.input.value).toBe("X Display");
    });
  });

  // =========================================================================
  // Free text mode
  // =========================================================================

  describe("free text mode", () => {
    it("does not open dropdown on focus", () => {
      cb = createCombobox({
        container: el,
        options: FLAT_OPTIONS,
        freeText: true,
      });
      fire(cb.input, "focus");
      expect(dropdown().style.display).not.toBe("block");
    });

    it("fires onSelect with confirmed:false on blur", () => {
      const onSelect = vi.fn();
      cb = createCombobox({
        container: el,
        options: [],
        freeText: true,
        onSelect,
      });
      cb.input.value = "hello";
      fire(cb.input, "blur");

      expect(onSelect).toHaveBeenCalledWith(
        expect.objectContaining({ value: "hello", confirmed: false }),
      );
    });

    it("fires onSelect with confirmed:true on Enter", () => {
      const onSelect = vi.fn();
      cb = createCombobox({
        container: el,
        options: [],
        freeText: true,
        onSelect,
      });
      cb.input.value = "world";
      fireKeydown(cb.input, "Enter");

      expect(onSelect).toHaveBeenCalledWith(
        expect.objectContaining({ value: "world", confirmed: true }),
      );
    });
  });

  // =========================================================================
  // Public API
  // =========================================================================

  describe("public API", () => {
    it("getValue returns current value", () => {
      cb = createCombobox({
        container: el,
        options: FLAT_OPTIONS,
        value: "b",
      });
      expect(cb.getValue()).toBe("b");
    });

    it("setValue updates input and internal value", () => {
      cb = createCombobox({ container: el, options: FLAT_OPTIONS });
      cb.setValue("c", "Charlie");
      expect(cb.input.value).toBe("Charlie");
      expect(cb.getValue()).toBe("c");
    });

    it("destroy removes dropdown from body", () => {
      cb = createCombobox({ container: el, options: FLAT_OPTIONS });
      const dd = dropdown();
      expect(dd).toBeTruthy();
      cb.destroy();
      cb = null;
      expect(document.querySelector(".combobox-dropdown")).toBeNull();
    });
  });
});
