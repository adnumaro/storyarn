/**
 * FormulaBinding — LiveView hook for a searchable variable binding combobox.
 *
 * Wraps the existing `createCombobox` from instruction_builder/combobox.js
 * to provide a searchable dropdown for binding formula symbols to variables.
 *
 * Data attributes:
 *   data-symbol       — the formula symbol name (e.g., "a")
 *   data-value        — current binding value (e.g., "same_row:value" or "seven.stats.con.value")
 *   data-display      — display text for current value (e.g., "Value" or "seven.stats.con.value")
 *   data-options      — JSON array of {value, label, group} options
 *   data-row-id       — the table row ID
 *   data-column-slug  — the formula column slug
 */

import { createCombobox } from "../instruction_builder/combobox";

export const FormulaBinding = {
  mounted() {
    this.setup();
  },

  destroyed() {
    if (this._combobox) {
      this._combobox.destroy();
      this._combobox = null;
    }
  },

  setup() {
    const options = JSON.parse(this.el.dataset.options || "[]");
    const currentValue = this.el.dataset.value || "";
    const displayValue = this.el.dataset.display || "";

    // ContentTab component target for event routing
    this._target = this.el.dataset.phxTarget || null;

    this._combobox = createCombobox({
      container: this.el,
      options,
      value: currentValue,
      displayValue,
      placeholder: "Search variable...",
      fixedWidth: true,
      onSelect: (option) => {
        if (!option.confirmed) return;
        const payload = {
          binding_value: option.value,
          symbol: this.el.dataset.symbol,
          "row-id": this.el.dataset.rowId,
          "column-slug": this.el.dataset.columnSlug,
        };
        if (this._target) {
          this.pushEventTo(this._target, "save_formula_binding", payload);
        } else {
          this.pushEvent("save_formula_binding", payload);
        }
      },
    });

    // Override the input styling to match the sidebar
    if (this._combobox.input) {
      this._combobox.input.className = "input input-sm input-bordered w-full text-sm font-mono";
    }
  },
};
