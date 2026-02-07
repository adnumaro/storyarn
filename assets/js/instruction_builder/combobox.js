/**
 * Searchable combobox widget for instruction builder.
 *
 * A reusable dropdown with search-as-you-type filtering.
 * Options can be grouped (e.g., variables grouped by page).
 *
 * The dropdown is appended to document.body to escape any
 * overflow:hidden/auto containers in the panel.
 *
 * For freeText mode (literal value inputs), onSelect fires only on
 * blur or Enter — NOT on every keystroke. The option includes a
 * `confirmed` flag: true for Enter/click, false for blur.
 */

/**
 * Creates a combobox instance attached to a container element.
 *
 * @param {Object} opts
 * @param {HTMLElement} opts.container - Parent element to render into
 * @param {Array} opts.options - [{value, label, group?, meta?}]
 * @param {string} opts.value - Current selected value
 * @param {string} opts.displayValue - Current display text
 * @param {string} opts.placeholder - Placeholder text
 * @param {boolean} opts.disabled - Whether the input is disabled
 * @param {Function} opts.onSelect - Callback when an option is selected: (option) => void
 * @param {boolean} opts.freeText - Allow free text input (no dropdown). Default false.
 */
export function createCombobox(opts) {
  const {
    container,
    options = [],
    value = "",
    displayValue = "",
    placeholder = "",
    disabled = false,
    onSelect,
    freeText = false,
  } = opts;

  let isOpen = false;
  let highlightedIndex = -1;
  let filteredOptions = [...options];
  let currentValue = value;

  // Create input element
  const input = document.createElement("input");
  input.type = "text";
  input.className = "sentence-slot";
  input.placeholder = placeholder;
  input.value = displayValue || currentValue || "";
  input.disabled = disabled;
  input.autocomplete = "off";
  input.spellcheck = false;

  adjustInputWidth(input);
  container.appendChild(input);

  // Create dropdown — appended to body to escape overflow containers
  const dropdown = document.createElement("div");
  dropdown.className = "combobox-dropdown hidden";
  document.body.appendChild(dropdown);

  if (currentValue) {
    input.classList.add("filled");
  }

  // --- Event handlers ---

  input.addEventListener("focus", () => {
    if (disabled || freeText) return;
    openDropdown();
  });

  input.addEventListener("blur", () => {
    if (freeText) {
      // Save current value on blur (confirmed: false = don't advance)
      currentValue = input.value;
      input.classList.toggle("filled", !!input.value);
      if (onSelect)
        onSelect({ value: input.value, label: input.value, confirmed: false });
      return;
    }
    // Delay close to allow mousedown on dropdown options
    setTimeout(() => closeDropdown(), 150);
  });

  input.addEventListener("input", () => {
    adjustInputWidth(input);
    if (freeText) {
      // Only update local state — don't fire onSelect until blur/Enter
      currentValue = input.value;
      input.classList.toggle("filled", !!input.value);
      return;
    }
    filterOptions(input.value);
    if (!isOpen) openDropdown();
  });

  input.addEventListener("keydown", (e) => {
    if (freeText) {
      if (e.key === "Enter") {
        e.preventDefault();
        currentValue = input.value;
        if (onSelect)
          onSelect({
            value: input.value,
            label: input.value,
            confirmed: true,
          });
      }
      return;
    }

    switch (e.key) {
      case "ArrowDown":
        e.preventDefault();
        if (!isOpen) {
          openDropdown();
        } else {
          highlightedIndex = Math.min(
            highlightedIndex + 1,
            filteredOptions.length - 1,
          );
          renderDropdown();
          scrollToHighlighted();
        }
        break;

      case "ArrowUp":
        e.preventDefault();
        if (isOpen) {
          highlightedIndex = Math.max(highlightedIndex - 1, 0);
          renderDropdown();
          scrollToHighlighted();
        }
        break;

      case "Enter":
        e.preventDefault();
        if (
          isOpen &&
          highlightedIndex >= 0 &&
          filteredOptions[highlightedIndex]
        ) {
          selectOption(filteredOptions[highlightedIndex]);
        }
        break;

      case "Escape":
        e.preventDefault();
        closeDropdown();
        break;

      case "Tab":
        closeDropdown();
        break;
    }
  });

  // Close dropdown when any scrollable ancestor scrolls
  const scrollHandler = () => {
    if (isOpen) closeDropdown();
  };
  window.addEventListener("scroll", scrollHandler, true);

  // --- Methods ---

  function openDropdown() {
    if (disabled || freeText) return;
    isOpen = true;
    filterOptions(input.value);
    dropdown.classList.remove("hidden");
    positionDropdown();
  }

  function closeDropdown() {
    isOpen = false;
    highlightedIndex = -1;
    dropdown.classList.add("hidden");
  }

  function filterOptions(query) {
    const q = (query || "").toLowerCase().trim();
    if (!q) {
      filteredOptions = [...options];
    } else {
      filteredOptions = options.filter((opt) => {
        const label = (opt.label || "").toLowerCase();
        const val = (opt.value || "").toLowerCase();
        const group = (opt.group || "").toLowerCase();
        const meta = (opt.meta || "").toLowerCase();
        return (
          label.includes(q) ||
          val.includes(q) ||
          group.includes(q) ||
          meta.includes(q)
        );
      });
    }
    highlightedIndex = filteredOptions.length > 0 ? 0 : -1;
    renderDropdown();
  }

  function selectOption(option) {
    if (!option) return;
    currentValue = option.value;
    input.value = option.displayValue || option.label || option.value;
    input.classList.add("filled");
    adjustInputWidth(input);
    closeDropdown();
    if (onSelect) onSelect({ ...option, confirmed: true });
  }

  function renderDropdown() {
    dropdown.innerHTML = "";

    if (filteredOptions.length === 0) {
      const empty = document.createElement("div");
      empty.className = "px-3 py-2 text-xs text-base-content/40 italic";
      empty.textContent = "No matches";
      dropdown.appendChild(empty);
      return;
    }

    let currentGroup = null;
    filteredOptions.forEach((opt, idx) => {
      if (opt.group && opt.group !== currentGroup) {
        currentGroup = opt.group;
        const header = document.createElement("div");
        header.className = "combobox-group-header";
        header.textContent = opt.group;
        dropdown.appendChild(header);
      }

      const optEl = document.createElement("div");
      optEl.className = "combobox-option";
      if (idx === highlightedIndex) optEl.classList.add("highlighted");

      const labelSpan = document.createElement("span");
      labelSpan.textContent = opt.label || opt.value;
      optEl.appendChild(labelSpan);

      if (opt.meta) {
        const metaSpan = document.createElement("span");
        metaSpan.className = "ml-2 text-base-content/40";
        metaSpan.textContent = `(${opt.meta})`;
        optEl.appendChild(metaSpan);
      }

      optEl.addEventListener("mousedown", (e) => {
        e.preventDefault();
        e.stopPropagation();
        selectOption(opt);
      });

      optEl.addEventListener("mouseenter", () => {
        highlightedIndex = idx;
        // Only update highlight class, don't rebuild entire dropdown
        dropdown
          .querySelectorAll(".combobox-option")
          .forEach((el, i) => el.classList.toggle("highlighted", i === idx));
      });

      dropdown.appendChild(optEl);
    });
  }

  function scrollToHighlighted() {
    const highlighted = dropdown.querySelector(".combobox-option.highlighted");
    if (highlighted) {
      highlighted.scrollIntoView({ block: "nearest" });
    }
  }

  function positionDropdown() {
    // Position dropdown in viewport coordinates (since it's on body)
    const rect = input.getBoundingClientRect();
    const spaceBelow = window.innerHeight - rect.bottom;

    dropdown.style.position = "fixed";
    dropdown.style.left = `${rect.left}px`;
    dropdown.style.width = `${Math.max(rect.width, 200)}px`;

    if (spaceBelow < 200) {
      dropdown.style.bottom = `${window.innerHeight - rect.top + 4}px`;
      dropdown.style.top = "auto";
    } else {
      dropdown.style.top = `${rect.bottom + 4}px`;
      dropdown.style.bottom = "auto";
    }
  }

  // --- Cleanup ---
  function destroy() {
    closeDropdown();
    window.removeEventListener("scroll", scrollHandler, true);
    if (dropdown.parentNode) {
      dropdown.parentNode.removeChild(dropdown);
    }
  }

  // --- Public API ---
  return {
    input,
    destroy,
    getValue: () => currentValue,
    setValue: (val, display) => {
      currentValue = val;
      input.value = display || val || "";
      input.classList.toggle("filled", !!val);
      adjustInputWidth(input);
    },
    focus: () => {
      input.focus();
    },
  };
}

/**
 * Auto-adjusts input width to fit its content.
 */
function adjustInputWidth(input) {
  const minWidth = 3;
  const text = input.value || input.placeholder || "";
  const charCount = Math.max(text.length, minWidth);
  input.style.width = `${charCount + 2}ch`;
}
