%{
title: "Export",
category_label: "Export",
order: 1,
description: "Get your Storyarn content into formats that work with every major game engine."
}

---

Storyarn can export your narrative content to {accent}6 formats{/accent} covering the major game engines and dialogue systems. Whether you are building with Unity, Unreal, Godot, or using Ink or Yarn Spinner as your runtime, Storyarn has a serializer ready for your pipeline.

## Export formats

| Format                    | Extension | Engine / Tool                | Content supported                                        |
| ------------------------- | --------- | ---------------------------- | -------------------------------------------------------- |
| **Ink**                   | `.ink`    | Inkle's Ink runtime          | Flows, Sheets                                            |
| **Yarn Spinner**          | `.yarn`   | Yarn Spinner (Unity, Godot)  | Flows, Sheets                                            |
| **Unity Dialogue System** | `.json`   | Unity (Pixel Crushers, etc.) | Flows, Sheets                                            |
| **Godot Dialogic**        | `.dtl`    | Godot 4 Dialogic plugin      | Flows, Sheets                                            |
| **Unreal Engine**         | `.csv`    | Unreal Engine (Data Tables)  | Flows, Sheets                                            |
| **articy:draft**          | `.xml`    | articy:draft XML import      | Flows, Sheets                                            |

Engine-specific formats focus on flows and sheets, which is what game runtimes need for dialogue, branching, and variable state. Scenes and localization have their own tools inside their work areas when you need to prepare spatial content or translations.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  The export page showing the format selector, content section checkboxes, and asset mode options
</div>

## How to export

1. Navigate to **Export** from your project sidebar.
2. **Choose a format** -- Select from the available formats. The content checkboxes update to show which sections that format supports.
3. **Select content sections** -- Check or uncheck Sheets, Flows, Scenes, and Localization. Sections not supported by the selected format are disabled.
4. **Choose asset mode** -- Control how asset files (images, audio) are handled:

| Asset mode          | Behavior                                                             |
| ------------------- | -------------------------------------------------------------------- |
| **References only** | Asset URLs are included in the output (default, smallest file)       |
| **Embedded**        | Assets are Base64-encoded inline (larger file, fully self-contained) |
| **Bundled**         | Output is a ZIP file with an assets folder alongside the data file   |

5. **Set options** -- Toggle "Validate before export" and "Pretty print output" as needed.
6. **Download** -- Click the download button to get your file.

## Pre-export validation

Before downloading, you can run validation to catch issues that would cause problems in your game. Click **Validate** to check your project. The validator runs 9 checks and reports findings at three severity levels:

**Errors** (will likely break your game):

- Flows missing an Entry node
- Broken references: jump nodes pointing to non-existent hubs and subflow nodes referencing deleted flows

**Warnings** (potential issues):

- Orphan nodes with no connections
- Unreachable nodes (not reachable from Entry via BFS traversal)
- Empty dialogue nodes (no text content)
- Dialogue nodes with no speaker assigned
- Circular subflow reference chains (A references B references A)
- Missing translations for configured languages

**Info** (worth knowing):

- Orphan sheets with no references from any flow or scene

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Validation results showing a mix of errors (broken references), warnings (orphan nodes, empty dialogue), and info (unreferenced sheets)
</div>

## Other export paths

Beyond the main Export page, Storyarn offers specialized export features in other areas:

**Localization export** -- From the Localization page, export translations as Excel (.xlsx) or CSV filtered by language. Import translated CSV files back with ID-based matching. See the [Localization Overview](/docs/localization/localization-overview) for details.
