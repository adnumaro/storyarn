/**
 * Shared utilities for the condition builder UI.
 *
 * - createLogicToggle: AND/OR toggle used by blocks, groups, and top-level.
 * - generateId: ID generation for blocks, groups, and rules.
 */

/**
 * Creates an AND/OR logic toggle: "Match [all|any] of the {label}"
 *
 * @param {Object} opts
 * @param {string} opts.logic - Current logic ("all" or "any")
 * @param {boolean} opts.canEdit - Whether toggle is interactive
 * @param {string} opts.ofLabel - Text after the toggle ("of the rules", "of the blocks")
 * @param {Object} opts.translations - {match, all, any}
 * @param {Function} opts.onChange - Callback: (newLogic) => void
 * @returns {HTMLElement}
 */
export function createLogicToggle({ logic, canEdit, ofLabel, translations: t, onChange }) {
  const wrapper = document.createElement("div");
  wrapper.className = "flex items-center gap-2 text-xs";

  const matchLabel = document.createElement("span");
  matchLabel.className = "text-base-content/60";
  matchLabel.textContent = t?.match || "Match";
  wrapper.appendChild(matchLabel);

  const joinDiv = document.createElement("div");
  joinDiv.className = "join";

  const allBtn = document.createElement("button");
  allBtn.type = "button";
  allBtn.className = `join-item btn btn-xs ${logic === "all" ? "btn-active" : ""}`;
  allBtn.textContent = t?.all || "all";
  allBtn.disabled = !canEdit;
  allBtn.addEventListener("click", () => onChange("all"));

  const anyBtn = document.createElement("button");
  anyBtn.type = "button";
  anyBtn.className = `join-item btn btn-xs ${logic === "any" ? "btn-active" : ""}`;
  anyBtn.textContent = t?.any || "any";
  anyBtn.disabled = !canEdit;
  anyBtn.addEventListener("click", () => onChange("any"));

  joinDiv.appendChild(allBtn);
  joinDiv.appendChild(anyBtn);
  wrapper.appendChild(joinDiv);

  const ofLabelEl = document.createElement("span");
  ofLabelEl.className = "text-base-content/60";
  ofLabelEl.textContent = ofLabel;
  wrapper.appendChild(ofLabelEl);

  return wrapper;
}

/**
 * Generates a unique ID with the given prefix.
 *
 * @param {string} [prefix="block"] - Prefix for the ID ("block", "group", "rule")
 * @returns {string}
 */
export function generateId(prefix = "block") {
  return `${prefix}_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;
}
