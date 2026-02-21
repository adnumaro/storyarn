/**
 * TableRowMenu — LiveView hook for table row action menu.
 *
 * Replaces DaisyUI dropdown with a floating popover (appended to body)
 * so it escapes the overflow-x-clip on the table container.
 *
 * Uses createFloatingPopover for positioning + outside-click.
 * Re-pushes events and triggers modals from the cloned template.
 *
 * Expected DOM structure:
 *   <div phx-hook="TableRowMenu" id="..." data-phx-target="#content-tab">
 *     <button data-role="trigger">...</button>
 *     <template data-role="popover-template">
 *       <ul class="menu ...">
 *         <li><button data-event="..." data-params="..." data-modal-id="...">...</button></li>
 *       </ul>
 *     </template>
 *   </div>
 */
import { createFloatingPopover } from "../utils/floating_popover";

export const TableRowMenu = {
  mounted() {
    this.setup();
  },

  updated() {
    const wasOpen = this._fp?.isOpen;
    this._destroyPopover();
    this.setup();
    if (wasOpen && this._fp) {
      this._fp.open();
    }
  },

  setup() {
    this.trigger = this.el.querySelector('[data-role="trigger"]');
    this.template = this.el.querySelector('[data-role="popover-template"]');
    this._target = this.el.dataset.phxTarget || null;

    if (!this.trigger || !this.template) return;

    // Create floating popover
    this._fp = createFloatingPopover(this.trigger, {
      class:
        "bg-base-200 border border-base-content/20 rounded-lg shadow-lg",
      width: "11rem",
      placement: "bottom-end",
    });

    // Clone template content
    const content = this.template.content.cloneNode(true);
    this._fp.el.appendChild(content);

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

      if (this._target) {
        this.pushEventTo(this._target, event, payload);
      } else {
        this.pushEvent(event, payload);
      }

      // Close the menu
      this._fp.close();
    };
    this._fp.el.addEventListener("click", this._onPopoverClick);
  },

  _destroyPopover() {
    if (this.trigger && this._onTriggerClick) {
      this.trigger.removeEventListener("click", this._onTriggerClick);
    }
    this._fp?.destroy();
    this._fp = null;
  },

  destroyed() {
    this._destroyPopover();
  },
};
