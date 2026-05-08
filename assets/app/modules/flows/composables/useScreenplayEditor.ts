import Placeholder from "@tiptap/extension-placeholder";
import StarterKit from "@tiptap/starter-kit";
import { useEditor, type Editor } from "@tiptap/vue-3";
import type { Ref } from "vue";

export interface UseScreenplayEditorOptions {
  content?: string;
  placeholder?: string;
  editable?: boolean;
  onUpdate?: (editor: Editor) => void;
  onBlur?: (editor: Editor) => void;
  onFocus?: (editor: Editor) => void;
}

/**
 * Screenplay-format TipTap editor. Aligns with industry game-narrative tools
 * (Articy / Pixel Crushers / Chat Mapper / Yarn / Ink): plain text with
 * paragraphs and hard breaks, no inline marks, no block-level structure.
 *
 * Disables every StarterKit extension that would surface formatting controls
 * the user shouldn't have here: bold/italic/strike/code/underline/link marks,
 * heading/list/blockquote/codeBlock/horizontalRule blocks. Keeps document,
 * paragraph, text, hardBreak, undo-redo, drop/gap cursors, trailing-node.
 *
 * Single source of truth for both the canvas inline editor (DialogueNode) and
 * the side-panel editor (FlowDialoguePanel).
 */
export function useScreenplayEditor(
  opts: UseScreenplayEditorOptions = {},
): Ref<Editor | undefined> {
  return useEditor({
    extensions: [
      StarterKit.configure({
        bold: false,
        italic: false,
        strike: false,
        code: false,
        underline: false,
        link: false,
        heading: false,
        blockquote: false,
        bulletList: false,
        orderedList: false,
        listItem: false,
        listKeymap: false,
        codeBlock: false,
        horizontalRule: false,
      }),
      Placeholder.configure({ placeholder: opts.placeholder ?? "" }),
    ],
    editable: opts.editable ?? true,
    content: opts.content ?? "",
    onUpdate: opts.onUpdate ? ({ editor }) => opts.onUpdate!(editor as Editor) : undefined,
    onBlur: opts.onBlur ? ({ editor }) => opts.onBlur!(editor as Editor) : undefined,
    onFocus: opts.onFocus ? ({ editor }) => opts.onFocus!(editor as Editor) : undefined,
  });
}
