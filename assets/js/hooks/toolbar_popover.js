/**
 * ToolbarPopover — Generic floating popover hook for toolbar dropdowns.
 *
 * Replaces JS.toggle + phx-click-away pattern with createFloatingPopover.
 * Re-pushes data-event/data-params clicks from cloned template content.
 *
 * Expected DOM structure:
 *   <div phx-hook="ToolbarPopover" id="..." data-width="14rem" data-placement="bottom-start">
 *     <button data-role="trigger">...</button>
 *     <template data-role="popover-template">
 *       ... popover content with data-event/data-params buttons ...
 *     </template>
 *   </div>
 */
import { createFloatingPopover } from "../utils/floating_popover";

export const ToolbarPopover = {
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

    if (!this.trigger || !this.template) return;

    const width = this.el.dataset.width || "";
    const placement = this.el.dataset.placement || "bottom-start";
    const offsetVal = parseInt(this.el.dataset.offset, 10);

    this._fp = createFloatingPopover(this.trigger, {
      class:
        "bg-base-100 border border-base-300 rounded-[10px] shadow-[0_8px_24px_rgba(0,0,0,0.18)]",
      width,
      placement,
      offset: Number.isFinite(offsetVal) ? offsetVal : undefined,
    });

    // Clone template content
    const content = this.template.content.cloneNode(true);
    this._fp.el.appendChild(content);

    // Trigger click toggles
    this._onTriggerClick = (e) => {
      e.stopPropagation();
      if (this.trigger.disabled) return;
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

      this.pushEvent(event, payload);

      // Close after selection (default behavior)
      if (btn.dataset.closeOnClick !== "false") {
        requestAnimationFrame(() => this._fp.close());
      }
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
