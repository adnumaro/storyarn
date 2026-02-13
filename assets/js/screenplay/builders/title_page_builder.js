/**
 * Title page builder — renders an editable form for title page metadata.
 *
 * Used by the TitlePage TipTap NodeView. Accepts a pushEvent callback
 * instead of relying on a LiveView hook directly.
 */

const FIELDS = [
  { key: "title", label: "Title" },
  { key: "credit", label: "Credit" },
  { key: "author", label: "Author" },
  { key: "draft_date", label: "Draft date" },
  { key: "contact", label: "Contact" },
];

/**
 * Create a title page builder UI inside the given container.
 *
 * @param {Object} opts
 * @param {HTMLElement} opts.container - DOM element to render into
 * @param {Object} opts.data - Initial title page data
 * @param {boolean} opts.canEdit - Whether editing is allowed
 * @param {Object} opts.context - Context map for event payload (element-id)
 * @param {string} opts.eventName - Event name to push
 * @param {Function} opts.pushEvent - Callback: pushEvent(eventName, payload)
 * @returns {{ destroy: Function, update: Function }}
 */
export function createTitlePageBuilder({
  container,
  data,
  canEdit,
  context,
  eventName,
  pushEvent,
}) {
  let currentData = data || {};

  function render() {
    container.innerHTML = "";

    const fieldsContainer = document.createElement("div");
    fieldsContainer.className = "sp-title-page-fields";

    for (const { key, label } of FIELDS) {
      const row = document.createElement("div");
      row.className = "sp-title-page-field";

      const labelEl = document.createElement("label");
      labelEl.className = "sp-title-page-label";
      labelEl.textContent = label;
      row.appendChild(labelEl);

      if (canEdit) {
        const input = document.createElement("input");
        input.type = "text";
        input.className = "sp-title-page-input";
        input.value = currentData[key] || "";
        input.placeholder = label;

        input.addEventListener("blur", () => {
          const newValue = input.value;
          if (newValue !== (currentData[key] || "")) {
            currentData[key] = newValue;
            pushEvent(eventName, {
              ...context,
              field: key,
              value: newValue,
            });
          }
        });

        input.addEventListener("keydown", (e) => {
          if (e.key === "Enter") {
            e.preventDefault();
            input.blur();
          }
        });

        row.appendChild(input);
      } else {
        const span = document.createElement("span");
        span.className = "sp-title-page-value";
        span.textContent = currentData[key] || "";
        row.appendChild(span);
      }

      fieldsContainer.appendChild(row);
    }

    container.appendChild(fieldsContainer);
  }

  // Initial render
  render();

  return {
    destroy() {
      container.innerHTML = "";
    },
    update(newData) {
      currentData = newData || {};
      render();
    },
  };
}
