/**
 * Searchable dropdown utility — two usage modes:
 *
 * 1. `createSearchableDropdown(trigger, opts)` — button-triggered (click to open/close).
 *    Options and currentValue can be arrays/strings OR factory functions evaluated at open
 *    time, keeping data-attribute-driven components in sync across LiveView updates.
 *
 * 2. `openSearchableDropdown(trigger, opts)` — imperative one-shot open (no click handler).
 *    Use when the open signal comes from an external event (e.g. Shadow DOM custom events).
 *
 * Both modes reuse `.combobox-option` / `.combobox-option:hover` CSS classes (CSS variables,
 * light/dark mode) and the `.searchable-dropdown` layout classes from app.css.
 *
 * Usage:
 *
 *   // Button-triggered (screenplay editor speaker selector):
 *   createSearchableDropdown(btn, {
 *     options: () => [{ value: "", label: "None", italic: true }, ...],
 *     currentValue: () => btn.dataset.selectedId || "",
 *     placeholder: "Search…",
 *     onSelect: (value) => hook.pushEventTo(hook.el, "my_event", { id: value }),
 *   });
 *
 *   // Imperative (canvas inline node speaker selector):
 *   const handle = openSearchableDropdown(trigger, {
 *     options: [{ value: "", label: "Dialogue", italic: true }, ...],
 *     currentValue: currentSpeakerId,
 *     onSelect: (value) => hook.pushEvent("update_node_field", { field: "speaker_sheet_id", value }),
 *   });
 *   // handle.isOpen, handle.destroy()
 */

import { createFloatingPopover } from "./floating_popover.js";

// ---------------------------------------------------------------------------
// Internal shared helpers
// ---------------------------------------------------------------------------

function sortOptions(options) {
  return [...options].sort((a, b) => {
    // Keep italic items (e.g. "No speaker") at top, rest alphabetical
    if (a.italic && !b.italic) return -1;
    if (!a.italic && b.italic) return 1;
    return a.label.localeCompare(b.label);
  });
}

/**
 * Builds the floating popover DOM (search input + scrollable list) and opens it.
 * Returns { fp, searchInput } — fp is already open.
 */
function buildAndOpen(trigger, { options, currentValue, placeholder, onSelect, placement, width }) {
  const fp = createFloatingPopover(trigger, {
    class: "searchable-dropdown",
    width: width ?? "14rem",
    placement: placement ?? "bottom-start",
    offset: 4,
  });

  const search = document.createElement("input");
  search.type = "text";
  search.placeholder = placeholder ?? "Search…";
  search.className = "searchable-dropdown__search";
  fp.el.appendChild(search);

  const list = document.createElement("div");
  list.className = "searchable-dropdown__list";
  fp.el.appendChild(list);

  function renderList(query) {
    const q = (query || "").toLowerCase().trim();
    const filtered = q ? options.filter((opt) => opt.label.toLowerCase().includes(q)) : options;
    list.innerHTML = "";

    if (filtered.length === 0) {
      const empty = document.createElement("div");
      empty.className = "combobox-option";
      empty.style.cssText = "opacity:0.4;font-style:italic;cursor:default;pointer-events:none;";
      empty.textContent = "No matches";
      list.appendChild(empty);
      return;
    }

    for (const opt of filtered) {
      const el = document.createElement("div");
      el.className = "combobox-option";
      if (opt.italic) el.style.fontStyle = "italic";
      if (opt.value === currentValue) el.style.fontWeight = "600";
      if (opt.italic && opt.value !== currentValue) el.style.opacity = "0.6";
      el.textContent = opt.label;

      el.addEventListener("mousedown", (e) => {
        e.preventDefault();
        fp.destroy();
        onSelect?.(opt.value);
      });

      list.appendChild(el);
    }
  }

  search.addEventListener("input", (e) => renderList(e.target.value));
  renderList("");
  fp.open();
  requestAnimationFrame(() => search.focus());

  return { fp, search };
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Attaches a click handler to `trigger` that opens/closes the dropdown.
 * Options and currentValue may be factory functions (called at open time).
 *
 * @returns {{ isOpen: boolean, destroy: () => void }}
 */
export function createSearchableDropdown(trigger, opts = {}) {
  const { placeholder = "Search…", onSelect, placement = "bottom-start", width = "14rem" } = opts;

  let fp = null;

  function open() {
    if (fp?.isOpen) {
      fp.destroy();
      fp = null;
      return;
    }

    const options = sortOptions(
      typeof opts.options === "function" ? opts.options() : (opts.options ?? []),
    );
    const currentValue = String(
      typeof opts.currentValue === "function" ? opts.currentValue() : (opts.currentValue ?? ""),
    );

    const result = buildAndOpen(trigger, {
      options,
      currentValue,
      placeholder,
      onSelect: (value) => {
        fp = null;
        onSelect?.(value);
      },
      placement,
      width,
    });
    fp = result.fp;
  }

  trigger.addEventListener("click", open);

  return {
    get isOpen() {
      return fp?.isOpen ?? false;
    },
    destroy() {
      trigger.removeEventListener("click", open);
      fp?.destroy();
      fp = null;
    },
  };
}

/**
 * Opens the dropdown immediately (no click handler attached).
 * Use when the open trigger is an external event (e.g. Shadow DOM custom events).
 *
 * @returns {{ isOpen: boolean, destroy: () => void }}
 */
export function openSearchableDropdown(trigger, opts = {}) {
  const {
    options = [],
    currentValue = "",
    placeholder = "Search…",
    onSelect,
    placement = "bottom-start",
    width = "14rem",
  } = opts;

  let done = false;

  const { fp } = buildAndOpen(trigger, {
    options: sortOptions(options),
    currentValue: String(currentValue),
    placeholder,
    onSelect: (value) => {
      done = true;
      onSelect?.(value);
    },
    placement,
    width,
  });

  return {
    get isOpen() {
      return !done && fp.isOpen;
    },
    destroy() {
      done = true;
      fp.destroy();
    },
  };
}
