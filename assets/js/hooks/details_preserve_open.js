/**
 * DetailsPreserveOpen - Preserves the open/closed state of a <details> element
 * across LiveView re-renders.
 *
 * Without this hook, LiveView's DOM patching resets the `open` attribute to
 * whatever the server sent, closing sections the user had manually opened.
 * This hook captures the current open state before each patch and restores it
 * after, so the user's toggle preference survives server-side re-renders.
 */
export const DetailsPreserveOpen = {
  mounted() {
    this._open = this.el.open;
  },

  beforeUpdate() {
    this._open = this.el.open;
  },

  updated() {
    this.el.open = this._open;
  },
};
