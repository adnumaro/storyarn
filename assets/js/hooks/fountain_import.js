/**
 * FountainImport hook — triggers a file picker and pushes content to the server.
 *
 * Usage: <button phx-hook="FountainImport" id="...">Import</button>
 *
 * On click the hook creates a hidden <input type="file">, reads the selected
 * file as text, and pushes the `import_fountain` event with `{ content }`.
 */
export const FountainImport = {
  mounted() {
    this._clickHandler = () => this.openFilePicker();
    this.el.addEventListener("click", this._clickHandler);
  },

  destroyed() {
    this.el.removeEventListener("click", this._clickHandler);
  },

  openFilePicker() {
    const input = document.createElement("input");
    input.type = "file";
    input.accept = ".fountain,.txt";
    input.style.display = "none";

    input.addEventListener("change", () => {
      const file = input.files?.[0];
      if (!file) return;

      const reader = new FileReader();
      reader.onload = () => {
        this.pushEvent("import_fountain", { content: reader.result });
      };
      reader.readAsText(file);
    });

    document.body.appendChild(input);
    input.click();
    input.remove();
  },
};
