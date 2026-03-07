%{
  title: "Screenplays Overview",
  category_label: "Screenwriting",
  order: 1,
  description: "Write and format production-ready scripts with the screenplay editor."
}
---

The screenplay editor is a **block-based writing environment** for game narrative scripts. It combines industry-standard screenplay formatting with interactive elements that bridge the gap between written scripts and playable dialogue flows.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  The screenplay editor showing a formatted script with scene heading, character name, dialogue, and parenthetical elements
</div>

## When to use Screenplays

- **Cutscene scripts** -- cinematics, linear sequences, voiceover sessions
- **Flow-synced scripts** -- generate formatted scripts from flow dialogue, or push screenplay edits back into a flow
- **Branching narratives** -- use linked pages to write response-driven stories in script format
- **Design documents** -- narrative pitch documents in professional format

## Element types

Screenplay content is built from **18 element types** organized into four categories.

### Standard elements

These follow industry-standard screenplay formatting conventions:

| Element | Purpose | Example |
|---------|---------|---------|
| **Scene Heading** | Location and time of day | INT. TAVERN - NIGHT |
| **Action** | Stage directions and descriptions | *The door creaks open slowly.* |
| **Character** | Speaker identification (ALL CAPS) | JAIME |
| **Dialogue** | Spoken lines | I've been waiting for you. |
| **Parenthetical** | Performance direction | (whispering) |
| **Transition** | Scene transitions | CUT TO: |
| **Dual Dialogue** | Two characters speaking simultaneously | Side-by-side dialogue columns |

### Interactive elements

These map directly to flow nodes, bridging screenplays and flows:

| Element | Flow equivalent | Purpose |
|---------|-----------------|---------|
| **Conditional** | Condition node | Branch the script based on a variable |
| **Instruction** | Instruction node | Modify variables (set health, update flags) |
| **Response** | Dialogue responses | Player choices that branch the narrative |

### Flow markers

Preserved during round-trip sync between screenplays and flows:

| Element | Purpose |
|---------|---------|
| **Hub Marker** | Preserves hub node data during sync |
| **Jump Marker** | Preserves jump target data during sync |

### Utility elements

These exist only in the screenplay editor and are not synced to flows:

| Element | Purpose |
|---------|---------|
| **Note** | Writer's notes (excluded from exports) |
| **Section** | Outline headers for organizing long scripts |
| **Page Break** | Force a page break in the formatted output |
| **Title Page** | Script metadata: title, author, credit, source, draft date, contact |

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Element type selector showing the four categories: standard, interactive, flow markers, and utility
</div>

## Writing experience

The editor uses a unified **TipTap rich-text editor** that understands screenplay structure. Key behaviors:

- **Auto-detection** -- typing `INT.` or `EXT.` at the start of a line automatically converts it to a Scene Heading. Typing an ALL CAPS name detects it as a Character. Parenthetical text wrapped in `()` is recognized too.
- **Rich text** -- dialogue, action, scene headings, parentheticals, transitions, notes, and sections support bold, italic, and other inline formatting via TipTap.
- **Variable mentions** -- reference project variables inside dialogue and action elements using the `@` mention system.
- **Read mode** -- toggle a distraction-free reading view that hides editing controls.

## Organizing screenplays

Screenplays support a **tree structure** with folders, just like sheets and flows:

```
Act 1/
  Opening Cinematic
  Tavern Introduction
  First Quest
Act 2/
  The Betrayal
  Forest Chase
```

## {accent}Flow synchronization{/accent}

Link a screenplay to a flow for **bidirectional sync** between your script and your interactive dialogue.

### Push to flow (Screenplay -> Flow)

Converts screenplay elements into flow nodes. Dialogue groups become dialogue nodes, conditionals become condition nodes, instructions become instruction nodes, and responses become dialogue nodes with player choices. The sync creates sequential connections between nodes and auto-positions them in a tree layout.

### Pull from flow (Flow -> Screenplay)

Traverses the flow graph via depth-first search and reverse-maps nodes back to screenplay elements. Non-mappeable elements (notes, sections, page breaks) are preserved in their original positions.

### How sync works

- Each screenplay element tracks its `linked_node_id` -- the flow node it maps to.
- Hub markers and jump markers are preserved during round-trip sync so flow navigation structure is not lost.
- The sync engine diffs against existing elements/nodes, only creating, updating, or deleting what changed.
- If no flow exists yet, one is created automatically when you first sync.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  The screenplay toolbar showing the flow sync controls: link status indicator, push-to-flow and pull-from-flow buttons
</div>

## {accent}Linked pages{/accent}

Response elements contain player choices, and each choice can link to a **child screenplay page**. This creates a branching tree of screenplay pages visible in the sidebar.

- Click a response choice to create or link a child page.
- The child page continues the narrative for that branch.
- The sidebar tree reflects the branching structure.
- During flow sync, linked pages map to response branches in the flow graph, with a maximum tree depth of 20 levels.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Sidebar tree showing a screenplay with linked child pages branching from response choices
</div>

## Fountain import and export

Storyarn supports **Fountain** (`.fountain`) -- the industry-standard plain-text screenplay format used by professional screenwriting tools like Final Draft, Highland, WriterSolo, and Fade In.

### Export

Converts screenplay elements to Fountain-formatted text. Standard elements are exported with proper Fountain syntax (scene headings, character cues, dialogue indentation, transitions, dual dialogue with `^` marker, sections with `#`, notes in `[[brackets]]`, page breaks as `===`). Rich text formatting is converted to Fountain marks (`**bold**`, `*italic*`). Interactive elements (conditionals, instructions, responses, hub/jump markers) are silently stripped from the output.

Title page metadata is exported as Fountain key-value headers: Title, Credit, Author, Source, Draft date, Contact.

### Import

Parses Fountain text back into screenplay elements. Supports:

- Title page key-value headers
- Standard Fountain element detection (INT./EXT. headings, ALL CAPS characters, transitions ending in `TO:`)
- Forced prefixes (`.` for scene headings, `!` for action, `@` for characters, `>` for transitions)
- Dual dialogue (`^` marker)
- Indented document detection (automatic indent-profile analysis for pasted scripts from other tools)
- Fountain marks converted to HTML (`**bold**` to `<strong>`, `*italic*` to `<em>`)
