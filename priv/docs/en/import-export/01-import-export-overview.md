%{
title: "Import and Export",
category_label: "Import and Export",
order: 1,
description: "Move narrative projects between Yarn Spinner, Storyarn, and major game engines."
}

---

Storyarn can import an existing {accent}Yarn Spinner project{/accent} and export narrative content to {accent}6 formats{/accent} covering major game engines and dialogue systems.

## Import from Yarn Spinner

Open **Project settings > Import & Export** and upload either one `.yarn` source file or a `.zip` containing the project's `.yarn` sources. Storyarn validates and previews the package before it changes project content. The default conflict policy keeps both versions by renaming imported content; you can instead skip matching content or overwrite it.

The importer converts:

- Yarn nodes into Storyarn Flows.
- Dialogue and nested options into dialogue, hub, and response nodes.
- `if`, `elseif`, and `else` branches into Storyarn conditions when every expression has a safe Storyarn equivalent.
- Literal variable declarations, supported assignments, and interpolations into a generated **Yarn Variables** sheet and Storyarn expressions.
- `jump`, `detour`, `return`, and `stop` commands into the corresponding flow control nodes.
- Speaker prefixes such as `Guide: Welcome` into character sheets when they can be inferred safely.
- Yarn line IDs into Storyarn localization IDs.

Custom side-effect commands that do not have a Storyarn equivalent are retained as visible annotation nodes and listed as warnings in the preview. Logic that controls branching or state is handled more strictly: if a condition, Smart Variable, assignment, or control-flow target cannot be reproduced safely, validation rejects the import before any plan or project content is stored.

### Safe import workflow

1. Select a `.yarn` or `.zip` file. The maximum upload size is 50 MB.
2. Click **Validate and preview**. ZIP paths, entry count, expanded size, compression ratio, text encoding, and individual file sizes are checked before extraction.
3. Review entity counts, shortcut conflicts, and compatibility warnings.
4. Choose **Skip**, **Overwrite**, or **Keep both** for conflicts, then start the import.
5. The encrypted import plan runs in the background. You can leave the page and return after it completes.

Only project members with content-editing permission can prepare or execute an import. Storyarn checks that permission again in the background job. Failed imports use a database transaction, so partial project content is not retained.

### Current Yarn import boundaries

- Yarn localization string-table CSV files are not imported yet. Source line IDs are preserved so translations can be connected in a later workflow.
- Custom side-effect commands are imported as annotations for manual review. Unsupported dynamic interpolation, Yarn markup and non-line-ID tags remain visible in the imported text and are flagged for review. Custom functions used in conditions, Yarn 3 Smart Variables, assignments to undeclared variables, and other unsupported state or control-flow expressions block the import instead of being weakened or discarded.
- Yarn 3 line groups, node groups and storylet `when` clauses are not converted yet. Files that use them are rejected because flattening their selection rules would change which dialogue is shown. Stateful `once` blocks are rejected for the same reason.
- Imported speaker sheets contain the inferred name only; enrich them with your project-specific schema after import. Dynamic speaker expressions remain in the dialogue text and are flagged for review instead of being linked to a character sheet.
- Images, audio, Unity assets, Godot resources, and compiled Yarn bytecode are not imported.

## Export formats

| Format                    | Extension | Engine / Tool                | Content supported |
| ------------------------- | --------- | ---------------------------- | ----------------- |
| **Ink**                   | `.ink`    | Inkle's Ink runtime          | Flows, Sheets     |
| **Yarn Spinner**          | `.yarn`   | Yarn Spinner (Unity, Godot)  | Flows, Sheets     |
| **Unity Dialogue System** | `.json`   | Unity (Pixel Crushers, etc.) | Flows, Sheets     |
| **Godot Dialogic**        | `.dtl`    | Godot 4 Dialogic plugin      | Flows, Sheets     |
| **Unreal Engine**         | `.csv`    | Unreal Engine (Data Tables)  | Flows, Sheets     |
| **articy:draft**          | `.xml`    | articy:draft XML import      | Flows, Sheets     |

Engine-specific formats focus on flows and sheets, which is what game runtimes need for dialogue, branching, and variable state. Scenes and localization have their own tools inside their work areas when you need to prepare spatial content or translations.

<img src="/images/docs/export-panel-current.png" alt="The export page showing the format selector, content section checkboxes, and asset mode options" loading="lazy">

## How to export

1. Navigate to **Import & Export** from your project sidebar.
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

<img src="/images/docs/export-validation-current.png" alt="Validation results showing warnings for disconnected nodes, empty dialogue, missing speakers, untranslated strings, and unreferenced sheets" loading="lazy">

## Other export paths

Beyond the main Import & Export page, Storyarn offers specialized exchange features in other areas:

**Localization exchange** -- From the Localization page, export translations as Excel (.xlsx) or CSV filtered by language. For an editable round trip, choose CSV, keep the exported ID and Source Hash columns unchanged, then use **Import CSV** to apply returned Translation and Status values. Excel exports are currently export-only. Source hashes prevent stale files from overwriting translations after source content changes. See the [Localization Overview](/docs/localization/localization-overview) for details.
