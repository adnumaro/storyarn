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
 * Container-level data attributes:
 *   data-target=".css-selector"   — pushEventTo target (for LiveComponents)
 *   data-width="14rem"            — popover width
 *   data-placement="bottom-start" — floating-ui placement
 *   data-offset="12"              — floating-ui offset
 *
 * Toolbar pinning:
 *   When placed inside a toolbar with [data-toolbar], the hook pins
 *   the toolbar visible (opacity + pointer-events) while the popover
 *   is open, and unpins it when the popover closes.
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
      this._pinToolbar(true);
    }
  },

  setup() {
    this.trigger = this.el.querySelector('[data-role="trigger"]');
    this.template = this.el.querySelector('[data-role="popover-template"]');

    if (!this.trigger || !this.template) return;

    this._target = this.el.dataset.target || null;
    this._toolbar = this.el.closest("[data-toolbar]");

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

    // Clone content — <template> uses .content, hidden <div> uses children directly.
    // Hidden divs are preferred when LiveView needs to diff the content reactively.
    if (this.template.content) {
      this._fp.el.appendChild(this.template.content.cloneNode(true));
    } else {
      this._fp.el.innerHTML = this.template.innerHTML;
    }

    // Trigger click toggles
    this._onTriggerClick = (e) => {
      e.stopPropagation();
      if (this.trigger.disabled) return;
      if (this._fp.isOpen) {
        this._closePopover();
      } else {
        this._fp.open();
        this._pinToolbar(true);
      }
    };
    this.trigger.addEventListener("click", this._onTriggerClick);

    // Click-outside closes popover
    this._onDocumentClick = (e) => {
      if (!this._fp?.isOpen) return;
      if (this._fp.el.contains(e.target)) return;
      if (this.trigger.contains(e.target)) return;
      this._closePopover();
    };
    document.addEventListener("mousedown", this._onDocumentClick);

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

      this._pushEvent(event, parseParams(btn));

      // Close after selection (default behavior)
      if (btn.dataset.closeOnClick !== "false") {
        requestAnimationFrame(() => this._closePopover());
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

      this._pushEvent(event, payload);
    };
    this._fp.el.addEventListener("focusout", this._onPopoverBlur);
  },

  _closePopover() {
    this._fp?.close();
    this._pinToolbar(false);
  },

  _pinToolbar(pinned) {
    if (!this._toolbar) return;
    if (pinned) {
      this._toolbar.style.opacity = "1";
      this._toolbar.style.pointerEvents = "auto";
    } else {
      this._toolbar.style.opacity = "";
      this._toolbar.style.pointerEvents = "";
    }
  },

  _pushEvent(event, payload) {
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
    if (this._onDocumentClick) {
      document.removeEventListener("mousedown", this._onDocumentClick);
    }
    this._pinToolbar(false);
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
