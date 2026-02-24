/**
 * ToolbarPopover — Generic floating popover hook for toolbar dropdowns.
 *
 * Replaces JS.toggle + phx-click-away pattern with createFloatingPopover.
 * Re-pushes data-event/data-params clicks from cloned template content.
 *
 * Supported data attributes on elements inside the template:
 *   data-event="event_name"        — pushEvent on click
 *   data-params='{"key":"val"}'    — JSON payload merged into event
 *   data-close-on-click="false"    — don't close popover after click
 *   data-blur-event="event_name"   — pushEvent on blur (for inputs)
 *   data-click-input="selector"    — click an element matching selector on click
 *
 * Expected DOM structure:
 *   <div phx-hook="ToolbarPopover" id="..." data-width="14rem" data-placement="bottom-start">
 *     <button data-role="trigger">...</button>
 *     <template data-role="popover-template">
 *       ... popover content ...
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

    // Stretch wrapper to parent height so popover anchors below the toolbar pill,
    // not below the (potentially centered) trigger button.
    // Also center children vertically within the stretched wrapper.
    this.el.style.alignSelf = "stretch";
    this.el.style.display = "inline-flex";
    this.el.style.alignItems = "center";

    this._fp = createFloatingPopover(this.el, {
      class: "bg-base-200 border border-base-300 rounded-lg shadow-lg",
      width,
      placement,
      offset: Number.isFinite(offsetVal) ? offsetVal : 12,
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

    // Re-push click events from cloned buttons
    this._onPopoverClick = (e) => {
      // data-click-input: click an element in the main DOM (e.g. file input)
      const clickInputBtn = e.target.closest("[data-click-input]");
      if (clickInputBtn) {
        const target = document.querySelector(clickInputBtn.dataset.clickInput);
        if (target) target.click();
        return;
      }

      const btn = e.target.closest("[data-event]");
      if (!btn || btn.disabled) return;

      const event = btn.dataset.event;
      if (!event) return;

      this.pushEvent(event, parseParams(btn));

      // Close after selection (default behavior)
      if (btn.dataset.closeOnClick !== "false") {
        requestAnimationFrame(() => this._fp.close());
      }
    };
    this._fp.el.addEventListener("click", this._onPopoverClick);

    // Re-push blur events from cloned inputs
    this._onPopoverBlur = (e) => {
      const input = e.target.closest("[data-blur-event]");
      if (!input) return;

      const event = input.dataset.blurEvent;
      if (!event) return;

      const payload = parseParams(input);
      payload.value = input.value;

      this.pushEvent(event, payload);
    };
    this._fp.el.addEventListener("focusout", this._onPopoverBlur);
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

function parseParams(el) {
  const payload = {};
  if (el.dataset.params) {
    try {
      Object.assign(payload, JSON.parse(el.dataset.params));
    } catch {
      /* no params */
    }
  }
  return payload;
}
