/**
 * Interactive header builder — shared by conditional, instruction, and response NodeViews.
 *
 * Builds the `.sp-interactive-header` DOM: icon + label + optional actions + delete button.
 */

import { createElement } from "lucide";
import * as icons from "lucide";

/**
 * Build an interactive block header element.
 *
 * @param {string} iconName - Lucide icon name (e.g. "git-branch", "zap", "list")
 * @param {string} label - Header label text
 * @param {Object} options
 * @param {boolean} options.canEdit - Whether delete button should be shown
 * @param {Function} [options.onDelete] - Callback when delete button is clicked
 * @returns {HTMLElement} The header DOM element
 */
export function buildInteractiveHeader(iconName, label, { canEdit, onDelete } = {}) {
  const header = document.createElement("div");
  header.className = "sp-interactive-header";

  // Icon
  const iconKey = iconNameToKey(iconName);
  const IconComponent = icons[iconKey];
  if (IconComponent) {
    const iconEl = createElement(IconComponent, { width: 16, height: 16 });
    iconEl.classList.add("sp-interactive-header-icon");
    iconEl.style.opacity = "0.6";
    header.appendChild(iconEl);
  }

  // Label
  const labelEl = document.createElement("span");
  labelEl.className = "sp-interactive-label";
  labelEl.textContent = label;
  header.appendChild(labelEl);

  // Actions slot (caller can append to header before delete button)
  const actionsSlot = document.createElement("span");
  actionsSlot.className = "sp-interactive-header-actions";
  header.appendChild(actionsSlot);

  // Delete button
  if (canEdit && onDelete) {
    const deleteBtn = document.createElement("button");
    deleteBtn.type = "button";
    deleteBtn.className = "sp-interactive-delete";
    deleteBtn.title = "Delete block";
    const trashIcon = icons.Trash2;
    if (trashIcon) {
      deleteBtn.appendChild(createElement(trashIcon, { width: 14, height: 14 }));
    }
    deleteBtn.addEventListener("click", (e) => {
      e.preventDefault();
      e.stopPropagation();
      onDelete();
    });
    header.appendChild(deleteBtn);
  }

  return { header, actionsSlot };
}

/**
 * Convert kebab-case icon name to PascalCase key for lucide import.
 * e.g. "git-branch" → "GitBranch", "zap" → "Zap"
 */
function iconNameToKey(name) {
  return name
    .split("-")
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join("");
}
