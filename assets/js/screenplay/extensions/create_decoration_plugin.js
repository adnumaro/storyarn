/**
 * Factory for ProseMirror decoration plugins.
 *
 * Both ContdPlugin and TransitionAlignPlugin share the same structure:
 * a plugin that recomputes a DecorationSet on every doc change.
 * This factory extracts the boilerplate.
 */

import { Extension } from "@tiptap/core";
import { Plugin, PluginKey } from "@tiptap/pm/state";

/**
 * Creates a TipTap extension that wraps a ProseMirror decoration plugin.
 *
 * @param {string} name - Extension name (must be unique)
 * @param {(doc: import("prosemirror-model").Node) => import("prosemirror-view").DecorationSet} computeFn
 *   Function that takes a doc and returns a DecorationSet
 * @returns {Extension} TipTap extension
 */
export function createDecorationPlugin(name, computeFn) {
  const pluginKey = new PluginKey(name);

  return Extension.create({
    name,

    addProseMirrorPlugins() {
      return [
        new Plugin({
          key: pluginKey,
          state: {
            init(_, { doc }) {
              return computeFn(doc);
            },
            apply(tr, oldDecorations) {
              if (!tr.docChanged) return oldDecorations;
              return computeFn(tr.doc);
            },
          },
          props: {
            decorations(state) {
              return this.getState(state);
            },
          },
        }),
      ];
    },
  });
}
