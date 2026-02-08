/**
 * ColorPicker hook — wraps vanilla-colorful's <hex-color-picker>.
 *
 * Usage in HEEX:
 *   <div id="color-X" phx-hook="ColorPicker" data-color="#3b82f6" data-event="update_color" data-field="color">
 *     <!-- picker injected here by hook -->
 *   </div>
 *
 * Attributes:
 *   data-color   — initial hex color
 *   data-event   — LiveView event to push (e.g., "update_hub_color")
 *   data-field   — field name sent in event payload
 */
import "vanilla-colorful/hex-color-picker.js";
import "vanilla-colorful/hex-input.js";

export const ColorPicker = {
  // Note: phx-update="ignore" is set on the container, so updated() won't fire.
  // The hook fully owns its DOM; server re-renders are skipped by design.
  mounted() {
    this.render();
  },

  render() {
    const color = this.el.dataset.color || "#8b5cf6";
    const event = this.el.dataset.event;
    const field = this.el.dataset.field || "color";

    // Create picker
    this.picker = document.createElement("hex-color-picker");
    this.picker.color = color;
    this.picker.style.width = "100%";

    // Create hex input row
    const inputRow = document.createElement("div");
    inputRow.style.cssText = "display:flex;align-items:center;gap:6px;margin-top:6px;";

    const swatch = document.createElement("div");
    swatch.style.cssText = `width:24px;height:24px;border-radius:6px;border:1px solid rgba(0,0,0,0.15);background:${color};flex-shrink:0;`;
    this.swatch = swatch;

    const label = document.createElement("span");
    label.textContent = "#";
    label.style.cssText = "font-size:12px;opacity:0.5;";

    this.input = document.createElement("hex-input");
    this.input.color = color;
    this.input.setAttribute("alpha", "");
    this.input.style.cssText = "flex:1;";

    // Style the inner input
    const innerInput = document.createElement("input");
    innerInput.style.cssText = "width:100%;font-family:monospace;font-size:12px;border:1px solid rgba(0,0,0,0.15);border-radius:4px;padding:2px 6px;background:transparent;color:inherit;";
    this.input.appendChild(innerInput);

    inputRow.append(swatch, label, this.input);
    this.el.append(this.picker, inputRow);

    // Debounce pushEvent to avoid flooding server
    let debounceTimer;
    const pushColor = (hex) => {
      swatch.style.background = hex;
      clearTimeout(debounceTimer);
      debounceTimer = setTimeout(() => {
        this.pushEvent(event, { [field]: hex });
      }, 150);
    };

    this.picker.addEventListener("color-changed", (e) => {
      this.input.color = e.detail.value;
      pushColor(e.detail.value);
    });

    this.input.addEventListener("color-changed", (e) => {
      this.picker.color = e.detail.value;
      pushColor(e.detail.value);
    });
  },

  destroyed() {
    // Web components clean up automatically
  },
};
