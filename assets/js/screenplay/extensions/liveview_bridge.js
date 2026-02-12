/**
 * LiveViewBridge — TipTap extension for bidirectional sync with Phoenix LiveView.
 *
 * Client → Server: debounced (500ms) push of the full element list on every
 *   document change, with immediate flush on blur.
 * Server → Client: listens for "set_editor_content" to replace the entire doc.
 *
 * A suppress flag prevents infinite loops when server-pushed content triggers
 * an editor update that would push back to the server.
 */

import { Extension } from "@tiptap/core";
import { docToElements, elementsToDoc } from "../serialization.js";

const DEBOUNCE_MS = 500;

/** Serialize the current doc and push to the server. */
function pushSync(editor, hook) {
  const elements = docToElements(editor);
  hook.pushEvent("sync_editor_content", { elements });
}

export const LiveViewBridge = Extension.create({
  name: "liveViewBridge",

  addOptions() {
    return {
      /** The Phoenix LiveView hook instance (must have pushEvent/handleEvent). */
      liveViewHook: null,
    };
  },

  addStorage() {
    return {
      debounceTimer: null,
      suppressUpdate: false,
      destroyed: false,
    };
  },

  onCreate() {
    const hook = this.options.liveViewHook;
    if (!hook) return;

    // Listen for server-pushed content replacement
    hook.handleEvent("set_editor_content", ({ elements }) => {
      if (this.storage.destroyed) return;

      this.storage.suppressUpdate = true;

      const doc = elementsToDoc(elements, this.editor.schema);
      this.editor.commands.setContent(doc);

      // Allow the next tick to finish before re-enabling updates
      requestAnimationFrame(() => {
        this.storage.suppressUpdate = false;
      });
    });
  },

  onUpdate() {
    if (this.storage.suppressUpdate || this.storage.destroyed) return;

    const hook = this.options.liveViewHook;
    if (!hook) return;

    // Clear previous debounce
    if (this.storage.debounceTimer) {
      clearTimeout(this.storage.debounceTimer);
    }

    this.storage.debounceTimer = setTimeout(() => {
      if (this.storage.destroyed) return;
      pushSync(this.editor, hook);
    }, DEBOUNCE_MS);
  },

  onBlur() {
    if (this.storage.suppressUpdate || this.storage.destroyed) return;

    const hook = this.options.liveViewHook;
    if (!hook) return;

    // Flush immediately on blur — no data loss
    if (this.storage.debounceTimer) {
      clearTimeout(this.storage.debounceTimer);
      this.storage.debounceTimer = null;
    }

    pushSync(this.editor, hook);
  },

  onDestroy() {
    this.storage.destroyed = true;

    if (this.storage.debounceTimer) {
      clearTimeout(this.storage.debounceTimer);
      this.storage.debounceTimer = null;
    }
  },

});
