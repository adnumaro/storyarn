/**
 * CharacterSheetPicker — floating dropdown for searching and selecting
 * a sheet to reference as a character name.
 *
 * Triggered by pressing `#` on a character element.
 * Pushes LiveView events for search and selection.
 */

import { escapeHtml } from "./utils.js";

const DEBOUNCE_MS = 300;

export class CharacterSheetPicker {
  constructor(hook) {
    this.hook = hook;
    this.popup = null;
    this.items = [];
    this.selectedIndex = 0;
    this.debounceTimer = null;

    this.handleKeyDown = this.handleKeyDown.bind(this);
    this.handleClickOutside = this.handleClickOutside.bind(this);
  }

  open() {
    if (this.popup) this.close();

    this.popup = document.createElement("div");
    this.popup.className = "sp-character-picker";

    // Search input
    const search = document.createElement("input");
    search.type = "text";
    search.className = "sp-character-picker-input";
    search.placeholder = "Search sheets...";
    search.addEventListener("input", () => this.onSearchInput(search.value));
    this.searchInput = search;

    // Results list
    const list = document.createElement("div");
    list.className = "sp-character-picker-list";
    this.listEl = list;

    this.popup.appendChild(search);
    this.popup.appendChild(list);

    // Position below the element
    const el = this.hook.el;
    const rect = el.getBoundingClientRect();
    this.popup.style.top = `${rect.bottom + 4}px`;
    this.popup.style.left = `${rect.left}px`;

    document.body.appendChild(this.popup);
    document.addEventListener("keydown", this.handleKeyDown, true);
    document.addEventListener("mousedown", this.handleClickOutside, true);

    // Initial empty search to get all results
    requestAnimationFrame(() => {
      search.focus();
      this.onSearchInput("");
    });
  }

  close() {
    if (this.popup) {
      this.popup.remove();
      this.popup = null;
    }
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = null;
    }
    document.removeEventListener("keydown", this.handleKeyDown, true);
    document.removeEventListener("mousedown", this.handleClickOutside, true);
  }

  onSearchInput(query) {
    if (this.debounceTimer) clearTimeout(this.debounceTimer);

    this.debounceTimer = setTimeout(() => {
      this.hook.pushEvent("search_character_sheets", { query });
    }, DEBOUNCE_MS);
  }

  onResults(items) {
    this.items = items || [];
    this.selectedIndex = 0;
    this.renderList();
  }

  renderList() {
    if (!this.listEl) return;

    if (this.items.length === 0) {
      this.listEl.innerHTML =
        '<div class="sp-character-picker-empty">No sheets found</div>';
      return;
    }

    this.listEl.innerHTML = this.items
      .map(
        (item, index) =>
          `<button type="button" class="sp-character-picker-item ${index === this.selectedIndex ? "sp-character-picker-highlighted" : ""}" data-index="${index}">
            <span class="sp-character-picker-name">${escapeHtml(item.name)}</span>
            ${item.shortcut ? `<span class="sp-character-picker-shortcut">#${escapeHtml(item.shortcut)}</span>` : ""}
          </button>`,
      )
      .join("");

    for (const button of this.listEl.querySelectorAll("button")) {
      button.addEventListener("click", () => {
        const idx = Number.parseInt(button.dataset.index, 10);
        if (this.items[idx]) this.selectItem(this.items[idx]);
      });
      button.addEventListener("mouseenter", () => {
        this.selectedIndex = Number.parseInt(button.dataset.index, 10);
        this.updateHighlight();
      });
    }
  }

  updateHighlight() {
    if (!this.listEl) return;
    const buttons = this.listEl.querySelectorAll(".sp-character-picker-item");
    buttons.forEach((btn, i) => {
      btn.classList.toggle(
        "sp-character-picker-highlighted",
        i === this.selectedIndex,
      );
    });
    if (buttons[this.selectedIndex]) {
      buttons[this.selectedIndex].scrollIntoView({ block: "nearest" });
    }
  }

  selectItem(item) {
    this.hook.pushEvent("set_character_sheet", {
      id: this.hook.elementId,
      sheet_id: item.id,
      name: item.name,
    });
    this.close();
  }

  handleKeyDown(event) {
    if (!this.popup) return;

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault();
        event.stopPropagation();
        this.selectedIndex =
          (this.selectedIndex + 1) % Math.max(this.items.length, 1);
        this.updateHighlight();
        break;

      case "ArrowUp":
        event.preventDefault();
        event.stopPropagation();
        this.selectedIndex =
          (this.selectedIndex - 1 + this.items.length) % Math.max(this.items.length, 1);
        this.updateHighlight();
        break;

      case "Enter":
        event.preventDefault();
        event.stopPropagation();
        if (this.items[this.selectedIndex]) {
          this.selectItem(this.items[this.selectedIndex]);
        }
        break;

      case "Escape":
        event.preventDefault();
        event.stopPropagation();
        this.close();
        // Refocus the editable block
        if (this.hook.editableBlock) {
          this.hook.editableBlock.focus();
        }
        break;
    }
  }

  handleClickOutside(event) {
    if (this.popup && !this.popup.contains(event.target)) {
      this.close();
    }
  }
}
