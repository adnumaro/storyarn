import katex from "katex";

export const FormulaPreview = {
  mounted() {
    this._render();
  },

  updated() {
    this._render();
  },

  _render() {
    const latex = this.el.dataset.latex || "";
    if (!latex) {
      this.el.textContent = "";
      return;
    }

    try {
      katex.render(latex, this.el, { displayMode: true, throwOnError: false });
    } catch (_e) {
      this.el.textContent = latex;
    }
  },
};
