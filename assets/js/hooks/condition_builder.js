/**
 * LiveView hook for the Condition Builder.
 *
 * Manages the condition (logic + rules) client-side and pushes the full
 * state back to LiveView on every meaningful change.
 *
 * Communication:
 * - Receives initial data from data-* attributes (read in mounted())
 * - Pushes: "update_condition_builder" or "update_response_condition_builder"
 *   depending on whether context has a response-id
 * - Listens: "node_updated" push event for collaboration updates
 *
 * The element uses phx-update="ignore" so LiveView won't clear
 * JS-rendered children on re-render.
 */

import { createConditionRuleRow } from "../condition_builder/condition_rule_row";
import { OPERATOR_LABELS as DEFAULT_OPERATOR_LABELS } from "../condition_builder/condition_sentence_templates";

const DEFAULT_TRANSLATIONS = {
  operator_labels: DEFAULT_OPERATOR_LABELS,
  match: "Match",
  all: "all",
  any: "any",
  of_the_rules: "of the rules",
  switch_mode_info: "Each condition creates an output. First match wins.",
  add_condition: "Add condition",
  no_conditions: "No conditions set",
  placeholder_sheet: "sheet",
  placeholder_variable: "variable",
  placeholder_operator: "op",
  placeholder_value: "value",
  placeholder_label: "label",
};

export const ConditionBuilder = {
  mounted() {
    this.nodeId = null;
    this.condition = JSON.parse(this.el.dataset.condition || '{"logic":"all","rules":[]}');
    this.variables = JSON.parse(this.el.dataset.variables || "[]");
    this.canEdit = JSON.parse(this.el.dataset.canEdit || "true");
    this.switchMode = JSON.parse(this.el.dataset.switchMode || "false");
    this.context = JSON.parse(this.el.dataset.context || "{}");
    this.t = {
      ...DEFAULT_TRANSLATIONS,
      ...JSON.parse(this.el.dataset.translations || "{}"),
    };
    // Merge operator_labels with defaults
    this.t.operator_labels = {
      ...DEFAULT_OPERATOR_LABELS,
      ...(this.t.operator_labels || {}),
    };
    this._pendingPushCount = 0;

    // Extract node ID from element ID (format: "condition-builder-{nodeId}")
    const idMatch = this.el.id.match(/condition-builder-(\d+)/);
    if (idMatch) this.nodeId = parseInt(idMatch[1], 10);

    // For response conditions, extract from context
    if (!this.nodeId && this.context["node-id"]) {
      this.nodeId = parseInt(this.context["node-id"], 10);
    }

    this.sheetsWithVariables = groupVariablesBySheet(this.variables);
    this.rows = [];
    this.render();

    // Listen for server push events (collaboration updates)
    this.handleEvent("node_updated", (data) => {
      // Only handle updates for our node
      if (data.id !== this.nodeId) return;

      // Skip if this is our own update coming back
      if (this._pendingPushCount > 0) {
        this._pendingPushCount--;
        return;
      }

      // External update — refresh from server data
      let newCondition;
      if (this.context["response-id"]) {
        // For response conditions, find our response in the data
        const responses = data.data?.responses || [];
        const response = responses.find(
          (r) => r.id === this.context["response-id"],
        );
        if (response && response.condition) {
          try {
            newCondition = JSON.parse(response.condition);
          } catch {
            return;
          }
        } else {
          return;
        }
      } else {
        newCondition = data.data?.condition;
      }

      if (newCondition && !deepEqual(newCondition, this.condition)) {
        this.condition = newCondition;
        this.switchMode = data.data?.switch_mode || false;
        this.render();
      }
    });
  },

  destroyed() {
    this.destroyRows();
  },

  destroyRows() {
    if (this.rows) {
      this.rows.forEach((row) => row.destroy?.());
      this.rows = [];
    }
  },

  pushCondition() {
    this._pendingPushCount++;
    const eventName = this.context["response-id"]
      ? "update_response_condition_builder"
      : "update_condition_builder";

    const payload = { condition: this.condition };

    // Include context fields for response conditions
    if (this.context["response-id"]) {
      payload["response-id"] = this.context["response-id"];
      payload["node-id"] = this.context["node-id"];
    }

    this.pushEvent(eventName, payload);
  },

  render() {
    this.destroyRows();
    this.el.innerHTML = "";

    const rules = this.condition.rules || [];

    // Logic toggle (only show when 2+ rules AND not in switch mode)
    if (rules.length >= 2 && !this.switchMode) {
      const logicToggle = this.renderLogicToggle();
      this.el.appendChild(logicToggle);
    }

    // Switch mode info
    if (this.switchMode && rules.length > 0) {
      const info = document.createElement("p");
      info.className = "text-xs text-base-content/60 mb-2";
      info.textContent = this.t.switch_mode_info;
      this.el.appendChild(info);
    }

    // Rule rows
    const rowsContainer = document.createElement("div");
    rowsContainer.className = "space-y-0";
    this.el.appendChild(rowsContainer);

    rules.forEach((rule, index) => {
      const rowEl = document.createElement("div");
      rowsContainer.appendChild(rowEl);

      const row = createConditionRuleRow({
        container: rowEl,
        rule,
        variables: this.variables,
        sheetsWithVariables: this.sheetsWithVariables,
        canEdit: this.canEdit,
        switchMode: this.switchMode,
        translations: this.t,
        onChange: (updatedRule) => {
          this.condition.rules[index] = updatedRule;
          this.pushCondition();
        },
        onRemove: () => {
          this.condition.rules.splice(index, 1);
          this.pushCondition();
          this.render();
        },
        onAdvance: () => {
          const nextRow = this.rows[index + 1];
          if (nextRow) {
            nextRow.focusFirstEmpty();
          } else if (this.addButton) {
            this.addButton.focus();
          }
        },
      });

      this.rows.push(row);
    });

    // Add rule button
    if (this.canEdit) {
      const addBtn = document.createElement("button");
      addBtn.type = "button";
      addBtn.className =
        "btn btn-ghost btn-xs gap-1 border border-dashed border-base-300 mt-2";
      addBtn.innerHTML =
        `<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg> ${this.t.add_condition}`;
      addBtn.addEventListener("click", () => {
        const newRule = {
          id: `rule_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`,
          sheet: null,
          variable: null,
          operator: "equals",
          value: null,
        };
        if (this.switchMode) {
          newRule.label = "";
        }
        this.condition.rules.push(newRule);
        this.pushCondition();
        this.render();

        requestAnimationFrame(() => {
          const lastRow = this.rows[this.rows.length - 1];
          if (lastRow) lastRow.focusFirstEmpty();
        });
      });

      this.addButton = addBtn;
      this.el.appendChild(addBtn);
    }

    // Empty state
    if (rules.length === 0 && !this.canEdit) {
      const empty = document.createElement("p");
      empty.className = "text-xs text-base-content/50 italic";
      empty.textContent = this.t.no_conditions;
      this.el.appendChild(empty);
    }
  },

  renderLogicToggle() {
    const wrapper = document.createElement("div");
    wrapper.className = "flex items-center gap-2 text-xs mb-2";

    const matchLabel = document.createElement("span");
    matchLabel.className = "text-base-content/60";
    matchLabel.textContent = this.t.match;
    wrapper.appendChild(matchLabel);

    const joinDiv = document.createElement("div");
    joinDiv.className = "join";

    const allBtn = document.createElement("button");
    allBtn.type = "button";
    allBtn.className = `join-item btn btn-xs ${this.condition.logic === "all" ? "btn-active" : ""}`;
    allBtn.textContent = this.t.all;
    allBtn.disabled = !this.canEdit;
    allBtn.addEventListener("click", () => {
      this.condition.logic = "all";
      this.pushCondition();
      this.render();
    });

    const anyBtn = document.createElement("button");
    anyBtn.type = "button";
    anyBtn.className = `join-item btn btn-xs ${this.condition.logic === "any" ? "btn-active" : ""}`;
    anyBtn.textContent = this.t.any;
    anyBtn.disabled = !this.canEdit;
    anyBtn.addEventListener("click", () => {
      this.condition.logic = "any";
      this.pushCondition();
      this.render();
    });

    joinDiv.appendChild(allBtn);
    joinDiv.appendChild(anyBtn);
    wrapper.appendChild(joinDiv);

    const ofLabel = document.createElement("span");
    ofLabel.className = "text-base-content/60";
    ofLabel.textContent = this.t.of_the_rules;
    wrapper.appendChild(ofLabel);

    return wrapper;
  },
};

/**
 * Groups flat variable list into sheets with their variables.
 */
function groupVariablesBySheet(variables) {
  const sheetMap = new Map();

  for (const v of variables) {
    const key = v.sheet_shortcut;
    if (!sheetMap.has(key)) {
      sheetMap.set(key, {
        shortcut: v.sheet_shortcut,
        name: v.sheet_name || v.sheet_shortcut,
        vars: [],
      });
    }
    sheetMap.get(key).vars.push({
      variable_name: v.variable_name,
      block_type: v.block_type,
      options: v.options,
    });
  }

  return Array.from(sheetMap.values()).sort((a, b) =>
    a.name.localeCompare(b.name),
  );
}

/**
 * Deep equality comparison for condition objects.
 */
function deepEqual(a, b) {
  if (a === b) return true;
  if (a == null || b == null) return a == b;
  if (Array.isArray(a) && Array.isArray(b)) {
    if (a.length !== b.length) return false;
    return a.every((item, i) => deepEqual(item, b[i]));
  }
  if (typeof a === "object" && typeof b === "object") {
    const keysA = Object.keys(a).sort();
    const keysB = Object.keys(b).sort();
    if (keysA.length !== keysB.length) return false;
    return keysA.every(
      (key, i) => keysB[i] === key && deepEqual(a[key], b[key]),
    );
  }
  return false;
}
