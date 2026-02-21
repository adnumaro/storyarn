/**
 * TableColumnDropdown — LiveView hook for table column header dropdown.
 *
 * Replaces DaisyUI dropdown with a floating popover (appended to body)
 * so it escapes the overflow-x-clip on the table container.
 *
 * Uses createFloatingPopover for positioning + outside-click.
 * Re-pushes all events from the cloned template since elements
 * are outside the LiveView DOM tree.
 *
 * Supports Notion-style sub-panels (main → type, main → options)
 * via show/hide with data-active attribute + CSS animation.
 *
 * Expected DOM structure:
 *   <div phx-hook="TableColumnDropdown" id="..." data-phx-target="#content-tab">
 *     <div data-role="trigger">icon + name + chevron</div>
 *     <template data-role="popover-template">
 *       <div class="col-dropdown-panel" data-panel="main" data-active>...</div>
 *       <div class="col-dropdown-panel" data-panel="type">...</div>
 *       <div class="col-dropdown-panel" data-panel="options">...</div>
 *     </template>
 *   </div>
 */
import { createFloatingPopover } from "../utils/floating_popover";

export const TableColumnDropdown = {
  mounted() {
    this.setup();
  },

  updated() {
    const wasOpen = this._fp?.isOpen;
    const prevPanel = this._currentPanel || "main";
    this._destroyPopover();
    this.setup();
    if (wasOpen && this._fp) {
      this._fp.open();
      if (prevPanel !== "main") {
        this._showPanel(prevPanel);
      }
    }
  },

  setup() {
    this.trigger = this.el.querySelector('[data-role="trigger"]');
    this.template = this.el.querySelector('[data-role="popover-template"]');
    this._target = this.el.dataset.phxTarget || null;
    this._currentPanel = "main";

    if (!this.trigger || !this.template) return;

    // Create floating popover with onClose to reset panel
    this._fp = createFloatingPopover(this.trigger, {
      class: "bg-base-200 border border-base-content/20 rounded-lg shadow-lg p-2",
      width: "12rem",
      placement: "bottom-end",
      onClose: () => this._showPanel("main"),
    });

    // Clone children from the hidden source div into the popover.
    // We use a hidden <div> (not <template>) so LiveView can patch its
    // content on re-renders, keeping the dropdown state fresh.
    const fragment = document.createDocumentFragment();
    for (const child of this.template.children) {
      fragment.appendChild(child.cloneNode(true));
    }
    this._fp.el.appendChild(fragment);

    // Trigger click toggles
    this._onTriggerClick = (e) => {
      e.stopPropagation();
      if (this._fp.isOpen) {
        this._fp.close();
      } else {
        this._fp.open();
      }
    };
    this.trigger.addEventListener("click", this._onTriggerClick);

    // Re-push events from cloned buttons
    this._onPopoverClick = (e) => {
      // Handle panel navigation
      const navBtn = e.target.closest("[data-navigate]");
      if (navBtn) {
        this._showPanel(navBtn.dataset.navigate);
        return;
      }

      const backBtn = e.target.closest("[data-back]");
      if (backBtn) {
        this._showPanel("main");
        return;
      }

      // Handle regular events
      const btn = e.target.closest("[data-event]");
      if (!btn || btn.disabled) return;

      const event = btn.dataset.event;
      if (!event) return;

      const payload = {};
      if (btn.dataset.params) {
        try {
          Object.assign(payload, JSON.parse(btn.dataset.params));
        } catch {
          /* no params */
        }
      }

      this._push(event, payload);

      // Close dropdown for most actions, but not for toggles or type changes
      if (btn.dataset.closeOnClick !== "false") {
        requestAnimationFrame(() => this._fp.close());
      }
    };
    this._fp.el.addEventListener("click", this._onPopoverClick);

    // Handle rename input (blur and Enter keydown)
    const renameInput = this._fp.el.querySelector('[data-role="rename-input"]');
    if (renameInput) {
      let lastPushedRename = null;
      this._onRenameBlur = () => {
        const event = renameInput.dataset.renameEvent;
        if (!event) return;
        const value = renameInput.value;
        if (value === lastPushedRename) return;
        lastPushedRename = value;
        const payload = { value };
        if (renameInput.dataset.columnId) {
          payload["column-id"] = renameInput.dataset.columnId;
        }
        this._push(event, payload);
      };
      this._onRenameKeydown = (e) => {
        if (e.key !== "Enter") return;
        e.preventDefault();
        renameInput.blur();
      };
      renameInput.addEventListener("blur", this._onRenameBlur);
      renameInput.addEventListener("keydown", this._onRenameKeydown);
    }

    // Handle option inputs (blur for update)
    this._fp.el.querySelectorAll('[data-role="option-input"]').forEach((input) => {
      input.addEventListener("blur", () => {
        const event = input.dataset.blurEvent;
        if (!event) return;

        const payload = { value: input.value };
        for (const attr of input.attributes) {
          if (attr.name.startsWith("data-param-")) {
            payload[attr.name.replace("data-param-", "")] = attr.value;
          }
        }

        this._push(event, payload);
      });
    });

    // Handle add-option input (Enter keydown)
    const addOptionInput = this._fp.el.querySelector('[data-role="add-option-input"]');
    if (addOptionInput) {
      this._onAddOptionKeydown = (e) => {
        if (e.key !== "Enter") return;
        e.preventDefault();

        const event = addOptionInput.dataset.keydownEvent;
        if (!event) return;

        const payload = { key: "Enter", value: addOptionInput.value };
        if (addOptionInput.dataset.columnId) {
          payload["column-id"] = addOptionInput.dataset.columnId;
        }

        this._push(event, payload);
        requestAnimationFrame(() => {
          addOptionInput.value = "";
        });
      };
      addOptionInput.addEventListener("keydown", this._onAddOptionKeydown);
    }
  },

  /**
   * Show a panel by name, hide all others.
   * @param {string} panelName - "main", "type", or "options"
   */
  _showPanel(panelName) {
    if (!this._fp) return;
    this._currentPanel = panelName;
    this._fp.el.querySelectorAll("[data-panel]").forEach((panel) => {
      if (panel.dataset.panel === panelName) {
        panel.setAttribute("data-active", "");
      } else {
        panel.removeAttribute("data-active");
      }
    });
  },

  /** Push event to the LiveComponent target (or fallback to LiveView). */
  _push(event, payload) {
    if (this._target) {
      this.pushEventTo(this._target, event, payload);
    } else {
      this.pushEvent(event, payload);
    }
  },

  _destroyPopover() {
    if (this.trigger && this._onTriggerClick) {
      this.trigger.removeEventListener("click", this._onTriggerClick);
    }
    this._fp?.destroy();
    this._fp = null;
    this._currentPanel = "main";
  },

  destroyed() {
    this._destroyPopover();
  },
};
