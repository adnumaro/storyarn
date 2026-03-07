%{
  title: "Core Workflow",
  category_label: "Welcome",
  order: 2,
  description: "How a typical project comes together in Storyarn."
}
---

Every team uses Storyarn differently, but here's how a typical project flows from setup to shipped.

---

## Set up your space

Create a **workspace** for your team. Every workspace has its own members with role-based access — owners manage everything, admins handle invitations, members create projects, and viewers have read-only access.

Inside a workspace, create a **project**. Each project is self-contained — its own sheets, flows, scenes, screenplays, localization, and assets. Projects have their own membership too: owners configure settings, editors create content, viewers review.

Invite teammates by email. They receive a token-based link, accept, and they're in — with the role you chose.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Workspace dashboard — project cards, member avatars, and the "New project" button
</div>

---

## Define your world with Sheets

Start with **Sheets** — structured data containers for your entire game world. Create a sheet for each character, item, location, faction, or quest.

Every field on a sheet is a **block**. There are 10 block types: text, rich text, number, boolean, select, multi-select, date, table, formula, and reference. Unless you mark a block as a **constant**, it automatically becomes a **variable** — referenceable from flows, conditions, and other sheets.

Variables follow the pattern `{sheet_shortcut}.{variable_name}`. A Health block on the sheet `mc.jaime` becomes `mc.jaime.health`. Change that value once, and every flow that checks it sees the update immediately.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Sheet editor — character profile with number and select blocks, showing the variable name badge on each field
</div>

**Tables** are spreadsheet grids inside a sheet — perfect for inventories, skill trees, or relationship matrices. Each cell becomes its own variable. **Formulas** let you compute values from other variables, even across sheets.

Organize sheets in a tree hierarchy. Use **property inheritance** to cascade blocks from parent to child sheets — create a "Character Base" with health, level, and faction, and every child character inherits those fields automatically, each with their own values.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Sheet with a table block — columns for item name, quantity, and damage, with a formula column computing total DPS
</div>

---

## Build branching narratives with Flows

**Flows** are visual node graphs where your story takes shape. Nine node types cover everything:

- **Dialogue** — character speech with optional player responses, each with their own conditions and instructions
- **Condition** — branch based on variable values using a visual builder (no code)
- **Instruction** — modify variables when the flow passes through
- **Hub & Jump** — create loops and convergence points for non-linear narratives
- **Subflow** — embed reusable flows inside others, with a full call stack
- **Slug Line** — scene headings for screenplay integration
- **Entry & Exit** — define where flows start and end, with exit modes for chaining flows

Connect nodes by dragging between pins. Edit content in the side panel. Collaborate in real time — see your teammates' cursors, and automatic locking prevents conflicting edits.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Flow editor — dialogue tree with an Entry node branching through Dialogue, Condition (true/false), and Instruction nodes leading to two Exit nodes
</div>

### Test without leaving the editor

This is where Storyarn pulls ahead. Other tools make you export to a game engine just to see if your dialogue works. Storyarn has two built-in testing tools:

The **Story Player** is a full-screen cinematic playthrough. You experience your flow exactly as a player would — dialogue slides with speaker avatars, numbered response choices, scene backdrops dimming behind the text. Auto-advances through conditions and instructions, stops at choices. Switch to **Analysis mode** to see hidden responses and condition badges. Navigate back through history to try different paths.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Story Player — dialogue slide with speaker name and avatar, three numbered response choices, and a dimmed scene backdrop behind
</div>

The **Debug Mode** is your step-by-step inspector. Advance node by node, watch variables change in real time in the Variables panel, trace the full execution path, and set breakpoints. Adjust variable values on the fly and re-run to test alternate branches. Four tabs — Console, Variables, History, and Path — give you complete visibility into what your flow is doing and why.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Debug Mode — flow canvas with a highlighted active node, and the debug panel below showing the Variables tab with current values and a changed-value highlight
</div>

---

## Map your world with Scenes

**Scenes** are interactive maps where your world becomes spatial. Upload a background image, draw polygonal zones for areas, place pins for characters and points of interest, add connections between pins, and annotate with text labels.

Zones and pins aren't just visual — they're interactive. Attach **conditions** to hide or disable elements based on game state. Attach **instructions** to modify variables when clicked. Link them to flows, sheets, or other scenes.

Double-click a zone to **drill down** — Storyarn extracts the zone's area from the background image, creates a child scene, and lets you keep zooming in. Build entire world hierarchies: continent → region → city → building → room.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Scene editor — fantasy map background with colored zones for regions, character pins with labels, and the layer panel on the left
</div>

### Exploration Mode

The **Exploration Mode** is where everything comes together. Walk through your world in an immersive full-screen view. Click zones to trigger flows that overlay on the dimmed map — your art, characters, dialogue, variables, and translations all running in one place. Navigate between scenes, execute variable assignments, and see conditions update zone visibility in real time.

No other narrative design tool does this.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Exploration Mode — dimmed scene map with a flow dialogue overlay showing speaker text and response choices on top of the world
</div>

---

## Write scripts with Screenplays

**Screenplays** bring your narrative into industry-standard script format. A block-based editor with 18 element types — from scene headings and dialogue to interactive conditions, instructions, and branching responses.

Screenplays **sync bidirectionally with flows**. Push changes from screenplay to flow, or pull updates from flow to screenplay. Response choices branch into **linked pages** — child screenplays that mirror your flow's branching structure.

Export to **Fountain** format for Final Draft, Highland, or any compatible screenwriting tool. Import Fountain files to bring existing scripts into Storyarn.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Screenplay editor — formatted script with scene heading, character name, dialogue block, and a response element with branching choices
</div>

---

## Localize everything

When your content is ready, the **Localization** tools extract every translatable text automatically — dialogue lines, stage directions, menu text, sheet labels, and block values.

Set up **DeepL integration** for machine translation as a first pass. Maintain a **glossary** for consistent terminology across languages (character names, game terms, proper nouns). Track progress per language with reports that show word counts by speaker, translation status, and voice-over progress.

Export translations as **Excel** or **CSV** for professional translators. Import them back when done. The system detects source text changes and automatically flags stale translations for review.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Localization — language list with progress bars, and the translation editor showing source text alongside the translated version
</div>

---

## Export and share

When it's time to ship, export your entire project or individual parts:

- **Storyarn JSON** — full project backup, re-importable
- **Ink, Yarn, Unity JSON, Godot Dialogic, Unreal CSV, Articy XML** — engine-specific formats
- **Fountain** — screenplay export
- **Excel / CSV** — localization data

Choose how to handle assets: references only, embedded (Base64), or bundled as a ZIP with an assets folder. Optional pre-export validation catches broken references, unreachable nodes, and missing translations before they reach your engine.

---

## Collaborate in real time

Throughout all of this, your team works together. In the flow editor, see who's online with presence indicators, watch live cursors as teammates work, and let automatic node locking prevent conflicting edits. Toast notifications keep everyone informed of changes.

Roles keep things organized — editors create content, viewers review without risk of accidental changes, and owners manage the project's settings, theme, and integrations.
