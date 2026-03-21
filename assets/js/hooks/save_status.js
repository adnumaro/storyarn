/**
 * SaveStatus — JS-driven save indicator that avoids root LiveView re-renders.
 *
 * Listens for "save_status" push_events and updates the indicator DOM directly.
 * This prevents morphdom from walking 1700+ elements just to show/hide a tiny indicator.
 *
 * Labels are read from data attributes on the hook element for i18n support:
 *   data-saved-label="Saved"  data-saving-label="Saving..."
 */
export const SaveStatus = {
  mounted() {
    this._timer = null;
    this._labelSaved = this.el.dataset.savedLabel || "Saved";
    this._labelSaving = this.el.dataset.savingLabel || "Saving...";

    this.handleEvent("save_status", ({ status }) => {
      clearTimeout(this._timer);

      if (status === "saved") {
        this.el.innerHTML = `
          <div class="flex items-center gap-2 px-3 py-1.5 rounded-lg text-sm font-medium bg-success/10 text-success animate-in fade-in duration-300">
            <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg>
            <span>${this._labelSaved}</span>
          </div>`;
      } else if (status === "saving") {
        this.el.innerHTML = `
          <div class="flex items-center gap-2 px-3 py-1.5 rounded-lg text-sm font-medium bg-base-200 text-base-content animate-in fade-in duration-300">
            <span class="loading loading-spinner loading-xs"></span>
            <span>${this._labelSaving}</span>
          </div>`;
      } else {
        // idle — fade out then clear
        const inner = this.el.firstElementChild;
        if (inner) {
          inner.classList.add("animate-out", "fade-out", "duration-300");
          this._timer = setTimeout(() => {
            this.el.innerHTML = "";
          }, 300);
        }
      }
    });
  },

  destroyed() {
    clearTimeout(this._timer);
  },
};
