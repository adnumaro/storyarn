/**
 * ColorPicker hook — Figma-style dropdown color picker.
 * Trigger: swatch + editable hex. Dropdown: spectrum + hue + eyedropper + hex input.
 * Positioning handled by createFloatingPopover utility.
 *
 * Attributes:
 *   data-color   — initial hex color
 *   data-event   — LiveView event to push
 *   data-field   — field name sent in event payload
 */
import "vanilla-colorful/hex-color-picker.js";
import "vanilla-colorful/hex-input.js";
import { createFloatingPopover } from "../utils/floating_popover";
import { ChevronDown, createElement, Pipette } from "lucide";

export const ColorPicker = {
  mounted() {
    this.render();
  },

  render() {
    const color = this.el.dataset.color || "#8b5cf6";
    const event = this.el.dataset.event;
    const field = this.el.dataset.field || "color";

    // ── Trigger: [swatch] [# hex] [chevron] ──
    const trigger = document.createElement("div");
    trigger.style.cssText =
      "display:inline-flex;align-items:center;gap:6px;padding:4px 8px;border:1px solid var(--color-base-300);border-radius:0.375rem;background-color:var(--color-base-100);cursor:pointer;";
    this.trigger = trigger;

    const swatch = document.createElement("div");
    swatch.style.cssText = `width:16px;height:16px;border-radius:4px;border:1px solid var(--color-base-300);background:${color};flex-shrink:0;`;
    this.swatch = swatch;

    const triggerHex = document.createElement("span");
    triggerHex.textContent = color;
    triggerHex.style.cssText =
      "font-family:monospace;font-size:11px;color:var(--color-base-content);opacity:0.6;flex:1;";
    this.triggerHex = triggerHex;

    const chevron = document.createElement("span");
    chevron.appendChild(
      createElement(ChevronDown, {
        width: 10,
        height: 10,
        "stroke-width": 2.5,
        style: "opacity:0.35",
      }),
    );
    chevron.style.cssText = "flex-shrink:0;display:flex;transition:transform 0.15s;";
    this.chevron = chevron;

    trigger.append(swatch, triggerHex, chevron);
    trigger.addEventListener("click", () => (this._fp.isOpen ? this.close() : this.openPanel()));

    // ── Floating popover panel ──
    this._fp = createFloatingPopover(trigger, {
      width: "240px",
      onClose: () => {
        this.chevron.style.transform = "";
      },
    });
    this._fp.el.style.cssText += "padding:12px;border:1px solid var(--color-base-300);border-radius:0.5rem;background-color:var(--color-base-100);box-shadow:0 10px 15px -3px rgb(0 0 0 / 0.1), 0 4px 6px -4px rgb(0 0 0 / 0.1);";

    // Picker (spectrum + hue)
    this.picker = document.createElement("hex-color-picker");
    this.picker.color = color;
    this.picker.style.width = "100%";
    this.picker.style.setProperty("--hcp-height", "140px");

    // Bottom row: [eyedropper] [swatch] [# hex-input]
    const bottomRow = document.createElement("div");
    bottomRow.style.cssText = "display:flex;align-items:center;gap:8px;margin-top:10px;";

    // Eyedropper button (only if EyeDropper API available)
    if (window.EyeDropper) {
      const eyedropperBtn = document.createElement("button");
      eyedropperBtn.type = "button";
      eyedropperBtn.appendChild(createElement(Pipette, { width: 14, height: 14 }));
      eyedropperBtn.style.cssText =
        "display:flex;align-items:center;justify-content:center;width:28px;height:28px;border-radius:0.375rem;border:1px solid var(--color-base-300);background-color:var(--color-base-200);cursor:pointer;color:var(--color-base-content);opacity:0.6;flex-shrink:0;";
      eyedropperBtn.title = "Pick color from screen";
      eyedropperBtn.addEventListener("click", async () => {
        try {
          const dropper = new EyeDropper();
          const result = await dropper.open();
          this.setColor(result.sRGBHex);
        } catch {
          /* user cancelled */
        }
      });
      bottomRow.appendChild(eyedropperBtn);
    }

    const inputSwatch = document.createElement("div");
    inputSwatch.style.cssText = `width:22px;height:22px;border-radius:5px;border:1px solid var(--color-base-300);background:${color};flex-shrink:0;`;
    this.inputSwatch = inputSwatch;

    const hashLabel = document.createElement("span");
    hashLabel.textContent = "#";
    hashLabel.style.cssText =
      "font-family:monospace;font-size:11px;color:var(--color-base-content);opacity:0.4;flex-shrink:0;";

    this.hexInput = document.createElement("hex-input");
    this.hexInput.color = color;
    this.hexInput.setAttribute("alpha", "");
    this.hexInput.style.cssText = "flex:1;min-width:0;";

    const innerInput = document.createElement("input");
    innerInput.style.cssText =
      "width:100%;font-family:monospace;font-size:11px;border:1px solid var(--color-base-300);border-radius:0.25rem;padding:3px 6px;background-color:var(--color-base-200);color:var(--color-base-content);outline:none;";
    this.hexInput.appendChild(innerInput);

    bottomRow.append(inputSwatch, hashLabel, this.hexInput);
    this._fp.el.append(this.picker, bottomRow);
    this.el.appendChild(trigger);

    // ── Sync ──
    let debounceTimer;
    this._pushColor = (hex) => {
      swatch.style.background = hex;
      inputSwatch.style.background = hex;
      triggerHex.textContent = hex;
      clearTimeout(debounceTimer);
      debounceTimer = setTimeout(() => {
        this.pushEvent(event, { [field]: hex });
      }, 150);
    };

    this.picker.addEventListener("color-changed", (e) => {
      this.hexInput.color = e.detail.value;
      this._pushColor(e.detail.value);
    });

    this.hexInput.addEventListener("color-changed", (e) => {
      this.picker.color = e.detail.value;
      this._pushColor(e.detail.value);
    });
  },

  setColor(hex) {
    this.picker.color = hex;
    this.hexInput.color = hex;
    this._pushColor(hex);
  },

  openPanel() {
    this.chevron.style.transform = "rotate(180deg)";
    this._fp.open();
  },

  close() {
    this._fp.close();
  },

  destroyed() {
    this._fp?.destroy();
  },
};
