/**
 * DialogueScreenplayEditor - Phoenix LiveView Hook for the screenplay editor panel.
 *
 * Handles panel animations (WAAPI) and keyboard shortcuts:
 * - Entry animation: slides in from the right on mount (desktop only)
 * - Exit animation: slides out to the right before server removal (desktop only)
 * - Escape: close the editor with animation
 * - Tab: focus stage directions input
 *
 * Also manages the speaker combobox (searchable floating popover that replaces
 * the native <select>). Uses createSearchableDropdown so it escapes overflow:hidden.
 *
 * Close flow: close buttons dispatch "panel:close" DOM event → hook animates
 * out → pushEvent("close_editor") to server → server unmounts component.
 */

import { createSearchableDropdown } from "../utils/searchable_dropdown.js";

const OPEN_DURATION = 280;
const CLOSE_DURATION = 180;
const ANIMATION_EASING = "ease-out";
// Small lateral drift — panel appears near its final position, not from offscreen
const SLIDE_OFFSET = "20px";

export const DialogueScreenplayEditor = {
  mounted() {
    this.handleKeyDown = this.handleKeyDown.bind(this);
    document.addEventListener("keydown", this.handleKeyDown);

    // Entry animation (desktop only — mobile is fullscreen, no slide)
    this.animateIn();

    // Intercept close requests to animate out first.
    // "panel:close"           → pushes "close_editor" (node stays selected)
    // "panel:close-deselect"  → pushes "deselect_node" (canvas click, full deselect)
    this.el.addEventListener("panel:close", () => this.closeWithAnimation("close_editor"));
    this.el.addEventListener("panel:close-deselect", () =>
      this.closeWithAnimation("deselect_node"),
    );

    this.setupSpeakerCombobox();
  },

  updated() {
    this.setupSpeakerCombobox();
  },

  setupSpeakerCombobox() {
    const btn = this.el.querySelector("#screenplay-speaker-btn");
    if (!btn || btn._comboboxAttached) return;
    btn._comboboxAttached = true;

    createSearchableDropdown(btn, {
      // Read data attributes at open time so LiveView updates stay in sync
      options: () => {
        const speakers = JSON.parse(btn.dataset.speakers || "[]");
        const noSpeakerLabel = btn.dataset.noSpeakerLabel || "Dialogue";
        return [
          { value: "", label: noSpeakerLabel, italic: true },
          ...speakers.map((s) => ({ value: s.id, label: s.name })),
        ];
      },
      currentValue: () => btn.dataset.speakerId || "",
      placeholder: btn.dataset.searchPlaceholder || "Search…",
      // pushEventTo routes to the LiveComponent (this.el has phx-target={@myself})
      onSelect: (value) => {
        this.pushEventTo(this.el, "update_speaker", { speaker_sheet_id: value });
      },
    });
  },

  animateIn() {
    if (window.innerWidth < 1280) return;

    const el = this.el;

    // Set initial hidden state synchronously so the browser paints it before animating
    el.style.opacity = "0";
    el.style.transform = `translateX(${SLIDE_OFFSET})`;

    // Double rAF: first ensures the hidden state is painted, second triggers the transition
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        el.style.transition = `transform ${OPEN_DURATION}ms ${ANIMATION_EASING}, opacity ${OPEN_DURATION}ms ${ANIMATION_EASING}`;
        el.style.opacity = "1";
        el.style.transform = "translateX(0)";

        // Clean up inline styles after animation so CSS takes over
        setTimeout(() => {
          el.style.transition = "";
          el.style.opacity = "";
          el.style.transform = "";
        }, OPEN_DURATION);
      });
    });
  },

  closeWithAnimation(serverEvent = "close_editor") {
    if (window.innerWidth < 1280) {
      this.pushEvent(serverEvent);
      return;
    }

    const el = this.el;
    el.style.transition = `transform ${CLOSE_DURATION}ms ${ANIMATION_EASING}, opacity ${CLOSE_DURATION}ms ${ANIMATION_EASING}`;
    el.style.opacity = "0";
    el.style.transform = `translateX(${SLIDE_OFFSET})`;

    // Guard against pushEvent after hook is destroyed
    this._closeTimer = setTimeout(() => {
      if (!this._destroyed) this.pushEvent(serverEvent);
    }, CLOSE_DURATION);
  },

  handleKeyDown(event) {
    if (event.key === "Escape") {
      event.preventDefault();
      this.closeWithAnimation("close_editor");
    } else if (event.key === "Tab" && !event.shiftKey) {
      const stageDirectionsInput = this.el.querySelector("#screenplay-stage-directions");
      if (stageDirectionsInput && document.activeElement !== stageDirectionsInput) {
        const activeElement = document.activeElement;
        const isInEditor = activeElement?.closest(".ProseMirror");

        if (isInEditor) {
          event.preventDefault();
          stageDirectionsInput.focus();
          stageDirectionsInput.select();
        }
      }
    }
  },

  destroyed() {
    this._destroyed = true;
    if (this._closeTimer) clearTimeout(this._closeTimer);
    document.removeEventListener("keydown", this.handleKeyDown);
  },
};
