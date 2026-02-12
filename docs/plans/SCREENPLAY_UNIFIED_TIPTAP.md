# Screenplay Editor — Unified TipTap Architecture

> **Status:** Plan
> **Goal:** Replace the current hybrid editor (per-element TipTap + contenteditable + non-editable blocks) with a single TipTap instance where each screenplay element type is a custom node. The result is a Google Docs-like experience with strict screenplay formatting.

---

## Problem Statement

The current editor uses a different rendering strategy per element type:

| Type                                                                      | Current approach                        | Problems                                          |
|---------------------------------------------------------------------------|-----------------------------------------|---------------------------------------------------|
| dialogue, action, scene_heading, parenthetical, transition, note, section | Individual TipTap instances per element | No cursor flow between elements, each is isolated |
| character                                                                 | Plain contenteditable                   | Different styling from TipTap elements            |
| page_break                                                                | Static HTML, no hook                    | Cannot be deleted via keyboard                    |
| conditional, instruction, response                                        | Phoenix components, no editor           | Cannot be navigated into or deleted via keyboard  |
| dual_dialogue                                                             | Textarea inputs                         | Completely different editing model                |
| hub_marker, jump_marker, title_page                                       | Static badge stubs                      | Not deletable                                     |

This creates: inconsistent styling, artificial block boundaries, "Add element" buttons (Notion-like instead of document-like), no native cursor navigation, and blocks that can only be deleted by clicking a trash icon.

---

## Target Architecture

One TipTap `Editor` instance for the entire document. Each element type is a custom `Node.create()` extension. The editor is mounted by a single LiveView hook (`ScreenplayEditor`). All keyboard navigation, deletion, and creation is handled natively by TipTap/ProseMirror.

```
LiveView (show.ex)
  └─ ScreenplayEditor hook (single)
       └─ TipTap Editor instance
            ├─ SceneHeading node (content: "inline*")
            ├─ Action node (content: "inline*")
            ├─ Character node (content: "inline*")
            ├─ Dialogue node (content: "inline*")
            ├─ Parenthetical node (content: "inline*")
            ├─ Transition node (content: "inline*")
            ├─ Note node (content: "inline*")
            ├─ Section node (content: "inline*")
            ├─ PageBreak node (atom)
            ├─ DualDialogue node (atom, NodeView)
            ├─ Conditional node (atom, NodeView)
            ├─ Instruction node (atom, NodeView)
            ├─ Response node (atom, NodeView)
            ├─ HubMarker node (atom, NodeView)
            ├─ JumpMarker node (atom, NodeView)
            └─ Extensions
                 ├─ ScreenplayKeymap (Enter, Tab, Backspace logic)
                 ├─ SlashCommands (via Suggestion API)
                 ├─ MentionExtension (existing, # trigger)
                 ├─ AutoDetect (InputRules)
                 └─ LiveViewBridge (server sync)
```

---

## Phase 1 — Core Text Nodes + Single Editor

**Goal:** Replace all per-element TipTap instances and the contenteditable character hook with a single TipTap editor. Text-based types only. Interactive blocks remain as server-rendered components outside TipTap for now.

### 1.1 Define Custom Node Extensions

Create one file per node type in `assets/js/screenplay/nodes/`.

**Text nodes** (all share the same structure, differ only in name, group membership, and CSS class):

```
assets/js/screenplay/nodes/
├── scene_heading.js    # group: "screenplayBlock", class: "sp-scene_heading"
├── action.js           # group: "screenplayBlock", class: "sp-action"
├── character.js        # group: "screenplayBlock", class: "sp-character"
├── dialogue.js         # group: "screenplayBlock", class: "sp-dialogue"
├── parenthetical.js    # group: "screenplayBlock", class: "sp-parenthetical"
├── transition.js       # group: "screenplayBlock", class: "sp-transition"
├── note.js             # group: "screenplayBlock", class: "sp-note"
└── section.js          # group: "screenplayBlock", class: "sp-section"
```

Each node:

```javascript
import { Node, mergeAttributes } from "@tiptap/core";

export const SceneHeading = Node.create({
  name: "sceneHeading",
  group: "screenplayBlock",
  content: "inline*",
  defining: true,

  addAttributes() {
    return {
      // Server element ID — used for sync, preserved through edits
      elementId: { default: null, parseHTML: el => el.dataset.elementId, renderHTML: () => ({}) },
    };
  },

  parseHTML() {
    return [{ tag: 'div[data-node-type="scene_heading"]' }];
  },

  renderHTML({ HTMLAttributes }) {
    return [
      "div",
      mergeAttributes(HTMLAttributes, {
        "data-node-type": "scene_heading",
        class: "sp-scene_heading",
      }),
      0, // content hole
    ];
  },
});
```

**Atom nodes:**

```
assets/js/screenplay/nodes/
└── page_break.js       # group: "screenplayBlock", atom: true
```

```javascript
export const PageBreak = Node.create({
  name: "pageBreak",
  group: "screenplayBlock",
  atom: true,
  selectable: true,

  parseHTML() {
    return [{ tag: 'div[data-node-type="page_break"]' }];
  },

  renderHTML() {
    return ["div", { "data-node-type": "page_break", class: "sp-page_break" },
      ["div", { class: "sp-page-break-line" }]];
  },
});
```

**Custom Document node:**

```javascript
// assets/js/screenplay/nodes/screenplay_doc.js
import { Node } from "@tiptap/core";

export const ScreenplayDoc = Node.create({
  name: "doc",
  topNode: true,
  content: "screenplayBlock+",
});
```

### 1.2 Create the ScreenplayKeymap Extension

`assets/js/screenplay/extensions/screenplay_keymap.js`

Handles all screenplay-specific keyboard behavior:

| Key                                 | Behavior                                                                                                                                                                           |
|-------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `Enter`                             | Split block. New block type follows `NEXT_TYPE` map (character→dialogue, dialogue→action, etc.). If current block is empty and non-action, convert to action instead of splitting. |
| `Shift-Enter`                       | Insert hard break (line break within same block) — TipTap default                                                                                                                  |
| `Backspace` at start of empty block | Delete block, merge with previous if text block. For atom nodes: delete and place cursor in previous.                                                                              |
| `Tab`                               | Cycle current block type forward through `TYPE_CYCLE`                                                                                                                              |
| `Shift-Tab`                         | Cycle backward                                                                                                                                                                     |
| `Escape`                            | Blur editor                                                                                                                                                                        |

```javascript
import { Extension } from "@tiptap/core";

const NEXT_TYPE = {
  sceneHeading: "action",
  action: "action",
  character: "dialogue",
  parenthetical: "dialogue",
  dialogue: "action",
  transition: "sceneHeading",
};

const TYPE_CYCLE = [
  "action", "sceneHeading", "character", "dialogue",
  "parenthetical", "transition",
];

export const ScreenplayKeymap = Extension.create({
  name: "screenplayKeymap",

  addKeyboardShortcuts() {
    return {
      Enter: ({ editor }) => {
        const { $from } = editor.state.selection;
        const currentNode = $from.parent;
        const currentType = currentNode.type.name;

        // Empty non-action text block → convert to action (like pressing Enter
        // in an empty character line in a real screenplay editor)
        if (currentNode.textContent === "" && currentType !== "action" && currentType in NEXT_TYPE) {
          return editor.commands.setNode("action");
        }

        const nextType = NEXT_TYPE[currentType] || "action";

        // Split block, then convert the new block to the next type
        return editor.chain()
          .splitBlock()
          .setNode(nextType)
          .run();
      },

      Tab: ({ editor }) => {
        const { $from } = editor.state.selection;
        const currentType = $from.parent.type.name;
        const idx = TYPE_CYCLE.indexOf(currentType);
        if (idx === -1) return false;
        const next = TYPE_CYCLE[(idx + 1) % TYPE_CYCLE.length];
        return editor.commands.setNode(next);
      },

      "Shift-Tab": ({ editor }) => {
        const { $from } = editor.state.selection;
        const currentType = $from.parent.type.name;
        const idx = TYPE_CYCLE.indexOf(currentType);
        if (idx === -1) return false;
        const prev = TYPE_CYCLE[(idx - 1 + TYPE_CYCLE.length) % TYPE_CYCLE.length];
        return editor.commands.setNode(prev);
      },

      Backspace: ({ editor }) => {
        const { $from, empty: selEmpty } = editor.state.selection;
        // Only intercept when cursor is at start of block and selection is collapsed
        if (!selEmpty || $from.parentOffset !== 0) return false;

        const currentNode = $from.parent;
        const currentType = currentNode.type.name;

        // Non-action empty text block → convert to action first
        if (currentNode.textContent === "" && currentType !== "action" && TYPE_CYCLE.includes(currentType)) {
          return editor.commands.setNode("action");
        }

        // Empty action block → delete node (ProseMirror joinBackward handles merge)
        return false; // let default backspace handle it
      },
    };
  },
});
```

### 1.3 Create the SlashCommands Extension

`assets/js/screenplay/extensions/slash_commands.js`

Uses TipTap's `Suggestion` API (already a dependency: `@tiptap/suggestion`).

- Trigger: `/` at start of empty block or after whitespace
- Renders a floating menu (reuse existing CSS classes: `.slash-menu`, `.slash-menu-item`, etc.)
- Categories: Screenplay, Interactive, Utility
- On selection: replaces the current block with the chosen type (for text nodes) or inserts an atom node (for page_break, interactive blocks)

The slash menu is rendered entirely client-side by the Suggestion `render()` lifecycle — no server round-trip needed for menu display/filtering. Only atom NodeViews (conditional, instruction, response) push events to the server on insertion.

```javascript
import { Extension } from "@tiptap/core";
import { Suggestion } from "@tiptap/suggestion";
import { PluginKey } from "@tiptap/pm/state";

const COMMANDS = [
  { type: "sceneHeading", label: "Scene Heading", desc: "INT./EXT. Location - Time", icon: "clapperboard", group: "screenplay", mode: "setNode" },
  { type: "action", label: "Action", desc: "Narrative description", icon: "align-left", group: "screenplay", mode: "setNode" },
  { type: "character", label: "Character", desc: "Character name (ALL CAPS)", icon: "user", group: "screenplay", mode: "setNode" },
  { type: "dialogue", label: "Dialogue", desc: "Spoken text", icon: "message-square", group: "screenplay", mode: "setNode" },
  { type: "parenthetical", label: "Parenthetical", desc: "(acting direction)", icon: "parentheses", group: "screenplay", mode: "setNode" },
  { type: "transition", label: "Transition", desc: "CUT TO:, FADE IN:", icon: "arrow-right", group: "screenplay", mode: "setNode" },
  { type: "conditional", label: "Condition", desc: "Branch based on variable", icon: "git-branch", group: "interactive", mode: "insertAtom" },
  { type: "instruction", label: "Instruction", desc: "Modify a variable", icon: "zap", group: "interactive", mode: "insertAtom" },
  { type: "response", label: "Responses", desc: "Player choices", icon: "list", group: "interactive", mode: "insertAtom" },
  { type: "note", label: "Note", desc: "Writer's note (not exported)", icon: "sticky-note", group: "utility", mode: "setNode" },
  { type: "section", label: "Section", desc: "Outline header", icon: "heading", group: "utility", mode: "setNode" },
  { type: "pageBreak", label: "Page Break", desc: "Force page break", icon: "scissors", group: "utility", mode: "insertAtom" },
];

export const SlashCommands = Extension.create({
  name: "slashCommands",

  addProseMirrorPlugins() {
    return [
      Suggestion({
        editor: this.editor,
        char: "/",
        pluginKey: new PluginKey("slash-commands"),
        startOfLine: false,
        allow: ({ state, range }) => {
          // Only allow when current block is empty or starts with /
          const $from = state.doc.resolve(range.from);
          return $from.parent.textContent.trim() === "/" ||
                 $from.parent.textContent.trim() === "";
        },
        items: ({ query }) =>
          COMMANDS.filter(c => c.label.toLowerCase().includes(query.toLowerCase())),
        command: ({ editor, range, props }) => {
          editor.chain().focus().deleteRange(range).run();
          if (props.mode === "setNode") {
            editor.commands.setNode(props.type);
          } else {
            editor.commands.insertContent({ type: props.type });
          }
        },
        render: () => slashMenuRenderer(),
      }),
    ];
  },
});
```

The `slashMenuRenderer()` function creates and manages the floating menu DOM. It reuses existing CSS classes and Lucide icons. Full implementation in `assets/js/screenplay/extensions/slash_menu_renderer.js`.

### 1.4 Adapt the Mention Extension

The existing `mention_extension.js` already uses `@tiptap/extension-mention` + `@tiptap/suggestion`. It needs minimal changes:

- Instead of receiving `this` (the hook) for `pushEvent`, it receives the hook reference passed via extension options: `MentionExtension.configure({ liveViewHook: hook })`
- The mention node rendering stays the same (`.mention` CSS class)
- Server events: `mention_suggestions` / `mention_suggestions_result` remain unchanged

### 1.5 Create the LiveView Bridge Extension

`assets/js/screenplay/extensions/liveview_bridge.js`

Handles bidirectional sync between TipTap document state and the server.

**Client → Server (debounced):**

On every `onUpdate`, convert the TipTap doc JSON to a flat element list and push to the server. Use a debounce (500ms) to avoid flooding.

```javascript
export const LiveViewBridge = Extension.create({
  name: "liveViewBridge",

  addOptions() {
    return { liveViewHook: null };
  },

  addStorage() {
    return { debounceTimer: null, suppressUpdate: false };
  },

  onUpdate() {
    if (this.storage.suppressUpdate) return;

    clearTimeout(this.storage.debounceTimer);
    this.storage.debounceTimer = setTimeout(() => {
      const hook = this.options.liveViewHook;
      if (!hook) return;

      const elements = docToElements(this.editor);
      hook.pushEvent("sync_editor_content", { elements });
    }, 500);
  },

  onBlur() {
    // Flush immediately on blur
    clearTimeout(this.storage.debounceTimer);
    const hook = this.options.liveViewHook;
    if (!hook || this.storage.suppressUpdate) return;

    const elements = docToElements(this.editor);
    hook.pushEvent("sync_editor_content", { elements });
  },

  onCreate() {
    const hook = this.options.liveViewHook;
    if (!hook) return;

    // Server → Client: full content replace (e.g. sync_from_flow)
    hook.handleEvent("set_editor_content", ({ elements }) => {
      this.storage.suppressUpdate = true;
      const doc = elementsToDoc(elements, this.editor.schema);
      this.editor.commands.setContent(doc, false);
      this.storage.suppressUpdate = false;
    });
  },

  onDestroy() {
    clearTimeout(this.storage.debounceTimer);
  },
});
```

**Document ↔ Element conversion functions:**

```javascript
// assets/js/screenplay/serialization.js

// TipTap node names use camelCase, server uses snake_case
const NODE_TYPE_MAP = {
  sceneHeading: "scene_heading",
  action: "action",
  character: "character",
  dialogue: "dialogue",
  parenthetical: "parenthetical",
  transition: "transition",
  note: "note",
  section: "section",
  pageBreak: "page_break",
  dualDialogue: "dual_dialogue",
  conditional: "conditional",
  instruction: "instruction",
  response: "response",
  hubMarker: "hub_marker",
  jumpMarker: "jump_marker",
};

const REVERSE_MAP = Object.fromEntries(
  Object.entries(NODE_TYPE_MAP).map(([k, v]) => [v, k])
);

/** TipTap doc → flat element list for server */
export function docToElements(editor) {
  const doc = editor.getJSON();
  return (doc.content || []).map((node, index) => {
    const serverType = NODE_TYPE_MAP[node.type] || node.type;
    const isAtom = !node.content;

    return {
      type: serverType,
      position: index,
      content: isAtom ? "" : inlineContentToHTML(node.content, editor),
      data: node.attrs?.data || {},
      element_id: node.attrs?.elementId || null,
    };
  });
}

/** Flat element list → TipTap doc JSON */
export function elementsToDoc(elements, schema) {
  return {
    type: "doc",
    content: elements.map(el => {
      const tipTapType = REVERSE_MAP[el.type] || el.type;

      if (schema.nodes[tipTapType]?.spec?.atom) {
        return { type: tipTapType, attrs: { elementId: el.id, data: el.data || {} } };
      }

      return {
        type: tipTapType,
        attrs: { elementId: el.id, data: el.data || {} },
        content: htmlToInlineContent(el.content || ""),
      };
    }),
  };
}
```

For `inlineContentToHTML` and `htmlToInlineContent`, we use TipTap's built-in `generateHTML()` / `generateJSON()` from `@tiptap/html`, or more simply, use `editor.getHTML()` on a per-node basis via the ProseMirror doc traversal.

### 1.6 Create the Single Hook

`assets/js/hooks/screenplay_editor.js`

Replaces `screenplay_editor_page.js`, `screenplay_element.js`, and `screenplay_tiptap_element.js`.

```javascript
import { Editor } from "@tiptap/core";
import StarterKit from "@tiptap/starter-kit";
// Custom nodes
import { ScreenplayDoc } from "../screenplay/nodes/screenplay_doc.js";
import { SceneHeading } from "../screenplay/nodes/scene_heading.js";
import { Action } from "../screenplay/nodes/action.js";
import { Character } from "../screenplay/nodes/character.js";
import { Dialogue } from "../screenplay/nodes/dialogue.js";
import { Parenthetical } from "../screenplay/nodes/parenthetical.js";
import { Transition } from "../screenplay/nodes/transition.js";
import { Note } from "../screenplay/nodes/note.js";
import { Section } from "../screenplay/nodes/section.js";
import { PageBreak } from "../screenplay/nodes/page_break.js";
// Extensions
import { ScreenplayKeymap } from "../screenplay/extensions/screenplay_keymap.js";
import { SlashCommands } from "../screenplay/extensions/slash_commands.js";
import { LiveViewBridge } from "../screenplay/extensions/liveview_bridge.js";
import { createMentionExtension } from "../tiptap/mention_extension.js";

export const ScreenplayEditor = {
  mounted() {
    const container = this.el;
    const contentJSON = JSON.parse(container.dataset.content || "{}");
    const canEdit = container.dataset.canEdit === "true";

    this.editor = new Editor({
      element: container,
      extensions: [
        ScreenplayDoc,
        // From StarterKit, only keep: Text, HardBreak, History, Bold, Italic, Strike
        StarterKit.configure({
          document: false, // we use ScreenplayDoc
          paragraph: false, // we use custom block nodes
          heading: false,
          bulletList: false,
          orderedList: false,
          codeBlock: false,
          code: false,
          blockquote: false,
          horizontalRule: false,
          dropcursor: true,
          gapcursor: true,
        }),
        // Text block nodes
        SceneHeading,
        Action,
        Character,
        Dialogue,
        Parenthetical,
        Transition,
        Note,
        Section,
        // Atom nodes
        PageBreak,
        // Extensions
        ScreenplayKeymap,
        SlashCommands,
        LiveViewBridge.configure({ liveViewHook: this }),
        createMentionExtension(this),
      ],
      content: contentJSON,
      editable: canEdit,
      editorProps: {
        attributes: {
          class: "screenplay-prosemirror",
        },
      },
    });

    // Server events
    this.handleEvent("focus_editor", () => {
      this.editor?.commands.focus("end");
    });

    // Character sheet events (forwarded to character node logic)
    this.handleEvent("character_sheet_results", ({ items }) => {
      // Dispatch to active character picker if open
      if (this._characterPickerResolve) {
        this._characterPickerResolve(items);
        this._characterPickerResolve = null;
      }
    });
  },

  destroyed() {
    this.editor?.destroy();
  },
};
```

### 1.7 Update the LiveView (show.ex)

**Render function changes:**

The `<.element_renderer>` loop and all per-element rendering is replaced by a single container div with initial content as JSON:

```elixir
def render(assigns) do
  ~H"""
  <Layouts.project ...>
    <div class="screenplay-container ...">
      <%!-- Toolbar stays the same --%>
      <div class="screenplay-toolbar" ...> ... </div>

      <%!-- Single TipTap editor container --%>
      <div
        id="screenplay-editor"
        class={["screenplay-page", @read_mode && "screenplay-read-mode"]}
        phx-hook="ScreenplayEditor"
        data-content={Jason.encode!(elements_to_tiptap_json(@elements))}
        data-can-edit={to_string(@can_edit && !@read_mode)}
      />

      <%!-- Slash menu is now rendered client-side by TipTap Suggestion --%>
    </div>
  </Layouts.project>
  """
end
```

**New server event:**

Replace all per-element events (`update_element_content`, `create_next_element`, `delete_element`, `change_element_type`, `create_first_element`, `create_element_at_end`) with a single sync event:

```elixir
def handle_event("sync_editor_content", %{"elements" => elements_json}, socket) do
  with_edit_permission(socket, fn ->
    do_sync_editor_content(socket, elements_json)
  end)
end
```

This handler diffs the incoming element list against the stored list and applies minimal DB operations (insert, update, delete, reorder).

**Kept events** (interactive blocks still communicate via pushEvent):
- `update_screenplay_condition`
- `update_screenplay_instruction`
- `add_response_choice`, `remove_response_choice`, `update_response_choice_text`
- `toggle_choice_condition`, `toggle_choice_instruction`
- `update_response_choice_condition`, `update_response_choice_instruction`
- `update_dual_dialogue`, `toggle_dual_parenthetical`
- `search_character_sheets`, `set_character_sheet`, `clear_character_sheet`
- `mention_suggestions`
- All linked page events
- All toolbar/sidebar events

**Removed events:**
- `update_element_content` (replaced by `sync_editor_content`)
- `create_next_element` (handled client-side by TipTap Enter key)
- `create_first_element` (editor starts with an empty action node)
- `create_element_at_end` (user just presses Enter at end)
- `delete_element` (handled client-side by Backspace)
- `change_element_type` (handled client-side by Tab)
- `open_slash_menu`, `close_slash_menu`, `select_slash_command`, `split_and_open_slash_menu` (all client-side)

**Removed assigns:**
- `@slash_menu_element_id` (no longer needed)

### 1.8 Serialization Helpers (Elixir side)

`lib/storyarn/screenplays/tiptap_serialization.ex`

```elixir
defmodule Storyarn.Screenplays.TiptapSerialization do
  @moduledoc """
  Converts between ScreenplayElement records and TipTap document JSON.
  """

  alias Storyarn.Screenplays.ScreenplayElement

  @node_type_map %{
    "scene_heading" => "sceneHeading",
    "action" => "action",
    "character" => "character",
    "dialogue" => "dialogue",
    "parenthetical" => "parenthetical",
    "transition" => "transition",
    "note" => "note",
    "section" => "section",
    "page_break" => "pageBreak",
    "dual_dialogue" => "dualDialogue",
    "conditional" => "conditional",
    "instruction" => "instruction",
    "response" => "response",
    "hub_marker" => "hubMarker",
    "jump_marker" => "jumpMarker",
    "title_page" => "titlePage",
  }

  @atom_types ~w(page_break dual_dialogue conditional instruction response hub_marker jump_marker title_page)

  @doc "Converts a list of ScreenplayElement records to TipTap JSON document."
  def elements_to_doc(elements) do
    content =
      elements
      |> Enum.sort_by(& &1.position)
      |> Enum.map(&element_to_node/1)

    # Ensure at least one node (empty action) for TipTap
    content = if content == [], do: [%{"type" => "action"}], else: content

    %{"type" => "doc", "content" => content}
  end

  @doc "Converts a TipTap JSON document to a list of element attribute maps."
  def doc_to_element_attrs(doc) do
    (doc["content"] || [])
    |> Enum.with_index()
    |> Enum.map(fn {node, idx} -> node_to_attrs(node, idx) end)
  end

  defp element_to_node(element) do
    tiptap_type = Map.get(@node_type_map, element.type, element.type)

    base = %{
      "type" => tiptap_type,
      "attrs" => %{"elementId" => element.id, "data" => element.data || %{}}
    }

    if element.type in @atom_types do
      base
    else
      Map.put(base, "content", html_to_tiptap_content(element.content))
    end
  end

  defp node_to_attrs(node, position) do
    server_type = reverse_type(node["type"])

    %{
      type: server_type,
      position: position,
      content: tiptap_content_to_html(node["content"]),
      data: get_in(node, ["attrs", "data"]) || %{},
      element_id: get_in(node, ["attrs", "elementId"])
    }
  end

  defp reverse_type(tiptap_type) do
    @node_type_map
    |> Enum.find(fn {_k, v} -> v == tiptap_type end)
    |> case do
      {k, _v} -> k
      nil -> tiptap_type
    end
  end

  # Convert HTML string to TipTap inline content array
  defp html_to_tiptap_content(nil), do: []
  defp html_to_tiptap_content(""), do: []
  defp html_to_tiptap_content(html) do
    # For Phase 1, wrap in a text node. Rich text (bold, italic, mentions)
    # is preserved as-is since TipTap parses HTML natively.
    [%{"type" => "text", "text" => html}]
  end

  # Convert TipTap inline content back to HTML string
  defp tiptap_content_to_html(nil), do: ""
  defp tiptap_content_to_html([]), do: ""
  defp tiptap_content_to_html(content) do
    # Phase 1: extract text, marks will be handled in Phase 3
    Enum.map_join(content, "", fn
      %{"type" => "text", "text" => text} -> text
      _ -> ""
    end)
  end
end
```

> **Note:** The HTML↔TipTap content conversion in Phase 1 is simplified. Full rich-text round-tripping (bold, italic, mentions) is completed in Phase 3.

### 1.9 CSS Adjustments

The existing `screenplay.css` per-type classes (`.sp-scene_heading`, `.sp-action`, etc.) already define the correct formatting. We need:

1. **Remove** wrapper-level selectors like `.screenplay-element.sp-scene_heading` and make them work on the TipTap-rendered `div[data-node-type]` elements directly.
2. **Add** a global `.screenplay-prosemirror` class for the ProseMirror editor root:

```css
.screenplay-prosemirror {
  outline: none;
  font-family: "Courier Prime", "Courier New", Courier, monospace;
  font-size: 12pt;
  line-height: 1;
  white-space: pre-wrap;
  word-wrap: break-word;
}

.screenplay-prosemirror > * {
  position: relative;
}
```

3. **Placeholder**: Each node type uses the `is-empty` class that ProseMirror's gapcursor or our custom logic adds. Alternatively, we use TipTap's Placeholder extension with per-node configuration:

```javascript
import Placeholder from "@tiptap/extension-placeholder";

Placeholder.configure({
  showOnlyCurrent: true,
  includeChildren: false,
  placeholder: ({ node }) => {
    const placeholders = {
      sceneHeading: "INT. LOCATION - TIME",
      action: "Describe the action...",
      character: "CHARACTER NAME",
      dialogue: "Dialogue text...",
      parenthetical: "(acting direction)",
      transition: "CUT TO:",
      note: "Note...",
      section: "Section heading",
    };
    return placeholders[node.type.name] || "";
  },
});
```

This requires installing `@tiptap/extension-placeholder`:
```bash
cd assets && npm install @tiptap/extension-placeholder
```

4. **Remove**: `cursor: text` on `.screenplay-page` (TipTap handles cursor natively), `cursor: auto` on `.screenplay-element`.

### 1.10 Remove Old Code

**Delete:**
- `assets/js/hooks/screenplay_element.js`
- `assets/js/hooks/screenplay_tiptap_element.js`
- `assets/js/hooks/screenplay_editor_page.js`
- `assets/js/hooks/slash_command.js`
- `assets/js/screenplay/constants.js`
- `lib/storyarn_web/components/screenplay/slash_command_menu.ex`
- `lib/storyarn_web/components/screenplay/element_renderer.ex`

**Modify:**
- `assets/js/app.js` — Remove old hook registrations, add `ScreenplayEditor`
- `lib/storyarn_web/live/screenplay_live/show.ex` — Major rewrite (see 1.7)

### 1.11 Tests

Update `test/storyarn_web/live/screenplay_live/show_test.exs`:
- Element creation tests now verify `sync_editor_content` events
- Element rendering tests check for TipTap doc JSON in `data-content`
- Remove tests for deleted events (`create_next_element`, `change_element_type`, etc.)
- Add tests for `TiptapSerialization` module

Add `test/storyarn/screenplays/tiptap_serialization_test.exs`:
- Round-trip: elements → doc → attrs → verify match
- Edge cases: empty doc, atom nodes, mixed types

---

## Phase 2 — Interactive Block NodeViews

**Goal:** Move condition, instruction, response, and dual_dialogue blocks from server-rendered Phoenix components to TipTap NodeViews. They become atom nodes with vanilla JS NodeViews that communicate with LiveView.

### 2.1 Architecture for NodeViews + LiveView

Each interactive NodeView:
1. Creates DOM elements in vanilla JS
2. Dispatches `CustomEvent` bubbling up to the hook element
3. The hook catches these events and calls `this.pushEvent()`
4. Server responds via `handleEvent()` which dispatches back to the NodeView

```
NodeView DOM
  → CustomEvent("nodeview:action", { detail: { ... } })
    → bubbles to ScreenplayEditor hook element
      → hook.pushEvent("update_screenplay_condition", ...)
        → server processes, pushes reply
          → hook.handleEvent("node_updated", ...)
            → editor.commands.updateAttributes(...)
              → NodeView.update() re-renders
```

### 2.2 Conditional Node

`assets/js/screenplay/nodes/conditional.js`

```javascript
export const Conditional = Node.create({
  name: "conditional",
  group: "screenplayBlock",
  atom: true,
  selectable: true,

  addAttributes() {
    return {
      elementId: { default: null },
      data: { default: { condition: null } },
    };
  },

  addNodeView() {
    return ({ editor, node, getPos }) => {
      // Renders the condition builder UI
      // Uses same CSS classes as current server-rendered version
      // Dispatches events via CustomEvent bubbling
      return createConditionalNodeView(editor, node, getPos);
    };
  },
});
```

The `createConditionalNodeView` function builds the DOM for the condition builder. Since the condition builder is currently a Phoenix LiveView component (`ConditionBuilder`), we have two options:

**Option A — Rebuild in JS:** Re-implement the condition builder UI in vanilla JS. More work, but fully self-contained in TipTap.

**Option B — Server-rendered island:** The NodeView creates a container div. When the node is selected or the editor mounts, the hook pushes an event asking the server to render the builder HTML for that element. The server responds with rendered HTML that is injected into the NodeView container. Events from the builder still use `phx-click` / `phx-blur` which work because the NodeView DOM is inside the LiveView tree.

**Recommended: Option B** for Phase 2 (pragmatic), with Option A as a future optimization. This means interactive blocks are "holes" in TipTap that contain server-rendered LiveView components.

### 2.3 Instruction Node

Same pattern as Conditional. NodeView renders a container, server fills it with the instruction builder component HTML.

### 2.4 Response Node

Same pattern. NodeView renders a container with choice list, add/remove buttons, linked page controls. The choice text inputs, condition/instruction toggles, and linked page buttons all dispatch events through the same bubble mechanism.

### 2.5 Dual Dialogue Node

NodeView renders the two-column layout with character, parenthetical, and dialogue fields per side. Each field dispatches blur events for saving.

### 2.6 Hub/Jump Markers

Simple atom NodeViews that render a badge (same as current stub rendering). Selectable and deletable.

---

## Phase 3 — Polish and Rich Text

**Goal:** Complete the editor experience with full rich-text support, auto-detect, and character sheet integration.

### 3.1 Rich Text Serialization

Complete the HTML ↔ TipTap content conversion to handle:
- Bold, italic, strike marks
- Mention inline nodes (`<span class="mention" data-type="sheet" data-id="..." data-label="...">`)
- Hard breaks (`<br>`)
- Multi-paragraph content (`<p>first</p><p>second</p>`)

Use `@tiptap/html`'s `generateJSON()` / `generateHTML()` for lossless conversion:

```javascript
import { generateJSON, generateHTML } from "@tiptap/html";

// Server HTML → TipTap JSON inline content
function htmlToInlineContent(html, extensions) {
  const doc = generateJSON(html, extensions);
  // doc.content[0] is a paragraph, return its content
  return doc.content?.[0]?.content || [];
}
```

### 3.2 Auto-Detect via InputRules

Move auto-detection from server-side (on content save) to client-side (on typing). This gives instant visual feedback.

```javascript
import { InputRule } from "@tiptap/core";

// When user types "INT. " or "EXT. " at start of block, convert to sceneHeading
new InputRule({
  find: /^(INT\.|EXT\.|INT\.\/EXT\.)\s$/,
  handler: ({ state, range }) => {
    const sceneHeadingType = state.schema.nodes.sceneHeading;
    if (sceneHeadingType) {
      state.tr.setBlockType(range.from, range.from, sceneHeadingType);
    }
  },
});
```

Add InputRules for:
- `INT.`/`EXT.` → scene_heading
- `CUT TO:` etc. → transition
- `(text)` → parenthetical
- ALL CAPS → character (debounced, after user stops typing)

Keep server-side auto-detect as a fallback/validation layer on `sync_editor_content`.

### 3.3 Character Sheet Picker (# trigger)

Two approaches:

**For the `character` node type:** Add a custom keyboard shortcut (`#`) that opens the character sheet picker. When a sheet is selected, store the `sheet_id` in the node attrs and make the node content non-editable (showing the sheet name). This mirrors the current behavior but within TipTap.

```javascript
const Character = Node.create({
  name: "character",
  // ...

  addKeyboardShortcuts() {
    return {
      "#": ({ editor }) => {
        if (!editor.isActive("character")) return false;
        // Open character sheet picker popup
        // On selection: update node attrs with sheet_id
        // Set node content to sheet name (non-editable)
        return true;
      },
    };
  },
});
```

**For inline mentions (# in dialogue/action):** Already handled by the existing MentionExtension.

### 3.4 Read Mode

Toggle between editable and read-only:

```javascript
// Toggle read mode
editor.setEditable(!readMode);

// Hide interactive blocks in read mode via CSS
// .screenplay-read-mode [data-node-type="conditional"],
// .screenplay-read-mode [data-node-type="instruction"], ... { display: none }
```

### 3.5 CONT'D Auto-Computation

The CONT'D label for repeated character names is currently computed server-side by `ElementGrouping.compute_continuations/2`. In the unified editor, this becomes:

- Computed client-side as a TipTap decoration (non-editable visual overlay)
- Recalculated on every document change
- Uses a ProseMirror plugin with `DecorationSet`

```javascript
import { Plugin, PluginKey } from "@tiptap/pm/state";
import { Decoration, DecorationSet } from "@tiptap/pm/view";

const contdPlugin = new Plugin({
  key: new PluginKey("contd"),
  state: {
    init(_, state) { return computeContdDecorations(state.doc); },
    apply(tr, oldSet) {
      if (tr.docChanged) return computeContdDecorations(tr.doc);
      return oldSet;
    },
  },
  props: {
    decorations(state) { return this.getState(state); },
  },
});
```

### 3.6 Transition Left-Align Detection

Currently `left_transition?/1` checks if content ends with `IN:` (e.g. "FADE IN:"). In TipTap, this becomes a CSS check via a decoration or by adding a computed attribute in the Transition node's `renderHTML`.

---

## Phase 4 — Migration & Cleanup

### 4.1 Data Migration

Existing `screenplay_elements` records store content as HTML strings (from TipTap) or plain text (from contenteditable). The new editor expects a TipTap JSON document built from these records.

**No database migration needed.** The `elements_to_doc/1` function in `TiptapSerialization` converts existing records to TipTap JSON at render time. The HTML content of each element is parsed by TipTap's `parseHTML` rules.

On the first save after the refactor, the `sync_editor_content` handler writes back all elements in the new normalized format.

### 4.2 Flow Sync Compatibility

`FlowSync.sync_to_flow/1` and `sync_from_flow/1` operate on `ScreenplayElement` records, not TipTap JSON. Since the server continues to store individual `ScreenplayElement` rows, flow sync is unaffected. The only change: after `sync_from_flow` updates the elements, the server pushes a `set_editor_content` event to reload the TipTap editor.

### 4.3 Test Updates

- Update LiveView tests to verify `data-content` JSON instead of per-element HTML
- Update test helpers to build TipTap doc fixtures
- Verify round-trip: create elements → render → edit → sync → verify DB

### 4.4 Delete Dead Code

After Phase 3 is stable:
- Remove `element_renderer.ex`
- Remove `slash_command_menu.ex`
- Remove per-element hooks (`screenplay_element.js`, `screenplay_tiptap_element.js`, `screenplay_editor_page.js`, `slash_command.js`)
- Remove `assets/js/screenplay/constants.js`
- Remove `assets/js/screenplay/character_sheet_picker.js` (rebuilt as TipTap extension)
- Clean up `show.ex` (remove all deleted event handlers)

---

## File Map

### New Files

```
assets/js/
├── hooks/
│   └── screenplay_editor.js                  # Single hook (replaces 4 hooks)
├── screenplay/
│   ├── nodes/
│   │   ├── screenplay_doc.js                 # Custom doc node
│   │   ├── scene_heading.js                  # Text block
│   │   ├── action.js                         # Text block
│   │   ├── character.js                      # Text block (+ sheet ref attrs)
│   │   ├── dialogue.js                       # Text block
│   │   ├── parenthetical.js                  # Text block
│   │   ├── transition.js                     # Text block
│   │   ├── note.js                           # Text block
│   │   ├── section.js                        # Text block
│   │   ├── page_break.js                     # Atom
│   │   ├── conditional.js                    # Atom + NodeView (Phase 2)
│   │   ├── instruction.js                    # Atom + NodeView (Phase 2)
│   │   ├── response.js                       # Atom + NodeView (Phase 2)
│   │   ├── dual_dialogue.js                  # Atom + NodeView (Phase 2)
│   │   ├── hub_marker.js                     # Atom + NodeView (Phase 2)
│   │   └── jump_marker.js                    # Atom + NodeView (Phase 2)
│   ├── extensions/
│   │   ├── screenplay_keymap.js              # Enter/Tab/Backspace logic
│   │   ├── slash_commands.js                 # / command menu (Suggestion API)
│   │   ├── slash_menu_renderer.js            # Floating menu DOM (vanilla JS)
│   │   ├── liveview_bridge.js                # Bidirectional sync
│   │   ├── auto_detect_rules.js              # InputRules (Phase 3)
│   │   └── contd_plugin.js                   # CONT'D decorations (Phase 3)
│   └── serialization.js                      # docToElements / elementsToDoc

lib/storyarn/screenplays/
│   └── tiptap_serialization.ex               # Elixir-side serialization

test/storyarn/screenplays/
│   └── tiptap_serialization_test.exs         # Serialization tests
```

### Deleted Files (after Phase 4)

```
assets/js/hooks/screenplay_element.js
assets/js/hooks/screenplay_tiptap_element.js
assets/js/hooks/screenplay_editor_page.js
assets/js/hooks/slash_command.js
assets/js/screenplay/constants.js
assets/js/screenplay/character_sheet_picker.js
lib/storyarn_web/components/screenplay/element_renderer.ex
lib/storyarn_web/components/screenplay/slash_command_menu.ex
```

### Modified Files

```
assets/js/app.js                              # Hook registration
assets/css/screenplay.css                     # CSS adaptation
lib/storyarn_web/live/screenplay_live/show.ex  # Major rewrite
test/storyarn_web/live/screenplay_live/show_test.exs
```

---

## New npm Dependencies

```bash
cd assets
npm install @tiptap/extension-placeholder
```

All other TipTap packages are already installed (`@tiptap/core`, `@tiptap/starter-kit`, `@tiptap/extension-mention`, `@tiptap/suggestion`, `@tiptap/pm`).

---

## Implementation Order

| Step   | Phase   | Description                                        | Depends on  |
|--------|---------|----------------------------------------------------|-------------|
| 1      | 1.1     | Define all text block node extensions              | —           |
| 2      | 1.1     | Define PageBreak atom node                         | —           |
| 3      | 1.1     | Define ScreenplayDoc node                          | —           |
| 4      | 1.2     | Create ScreenplayKeymap extension                  | Step 1      |
| 5      | 1.8     | Create TiptapSerialization (Elixir)                | —           |
| 6      | 1.5     | Create LiveViewBridge extension + serialization.js | Step 5      |
| 7      | 1.4     | Adapt MentionExtension to accept hook via options  | —           |
| 8      | 1.3     | Create SlashCommands extension + renderer          | Step 1      |
| 9      | 1.9     | Install Placeholder extension, update CSS          | Step 1      |
| 10     | 1.6     | Create ScreenplayEditor hook                       | Steps 1-9   |
| 11     | 1.7     | Rewrite show.ex render + events                    | Steps 5, 10 |
| 12     | 1.11    | Update tests                                       | Step 11     |
| 13     | 1.10    | Remove old hooks + components                      | Step 12     |
| 14     | 2.2-2.6 | Interactive block NodeViews                        | Step 13     |
| 15     | 3.1     | Rich text serialization                            | Step 13     |
| 16     | 3.2     | AutoDetect InputRules                              | Step 13     |
| 17     | 3.3     | Character sheet picker in TipTap                   | Step 13     |
| 18     | 3.4     | Read mode toggle                                   | Step 13     |
| 19     | 3.5     | CONT'D decorations                                 | Step 13     |
| 20     | 3.6     | Transition left-align                              | Step 13     |
| 21     | 4.4     | Final cleanup                                      | Steps 14-20 |

---

## Risks and Mitigations

| Risk                                                                           | Impact        | Mitigation                                                                                                                            |
|--------------------------------------------------------------------------------|---------------|---------------------------------------------------------------------------------------------------------------------------------------|
| ProseMirror schema rejects mixed content on paste                              | Medium        | Define `clipboardTextParser` and `clipboardSerializer` to normalize pasted content into valid screenplay blocks                       |
| NodeViews for interactive blocks don't integrate well with LiveView components | High          | Phase 2 Option B (server-rendered islands) avoids rebuilding builders in JS. If that doesn't work, fall back to Option A (JS rebuild) |
| Performance with very large screenplays (1000+ elements)                       | Medium        | TipTap/ProseMirror handles large documents well. If needed, add virtualization at the ProseMirror level                               |
| Undo/redo breaks across NodeView boundaries                                    | Low           | ProseMirror's transaction system handles this natively for atom nodes                                                                 |
| Collaborative editing conflicts with debounced sync                            | High (future) | Current system is single-user per screenplay. When adding collaboration later, switch from debounced full-sync to OT or CRDT          |

---

## Success Criteria

After all phases:

1. **Continuous document flow** — Cursor moves between all elements with arrow keys, no dead zones
2. **Keyboard-native editing** — Enter creates next logical type, Backspace deletes empty blocks, Tab cycles types — all without visible latency
3. **No "Add element" buttons** — Document grows organically by typing and pressing Enter
4. **Consistent styling** — All elements rendered by TipTap with identical CSS, no visual jumps between rendering strategies
5. **Page break deletable** — Select with arrow keys, press Backspace/Delete
6. **Interactive blocks deletable** — Select, Backspace removes them
7. **Slash commands in-editor** — Type `/` to insert any block type, no server round-trip for menu
8. **Rich text preserved** — Bold, italic, mentions in dialogue/action survive round-trips
9. **All existing features work** — Sheet references, conditions, instructions, responses, linked pages, flow sync, read mode, CONT'D
