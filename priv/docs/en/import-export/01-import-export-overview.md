%{
  title: "Import & Export",
  category_label: "Import & Export",
  order: 1,
  description: "Get your content in and out of Storyarn in formats that work with every major game engine."
}
---

Storyarn can export your narrative content to {accent}7 formats{/accent} covering every major game engine and dialogue system. Whether you are building with Unity, Unreal, Godot, or using Ink or Yarn Spinner as your runtime, Storyarn has a serializer ready for your pipeline.

## Export formats

| Format | Extension | Engine / Tool | Content supported |
|--------|-----------|---------------|-------------------|
| **Storyarn JSON** | `.json` | Storyarn (full backup) | Sheets, Flows, Scenes, Screenplays, Localization, Assets |
| **Ink** | `.ink` | Inkle's Ink runtime | Flows, Sheets |
| **Yarn Spinner** | `.yarn` | Yarn Spinner (Unity, Godot) | Flows, Sheets |
| **Unity Dialogue System** | `.json` | Unity (Pixel Crushers, etc.) | Flows, Sheets |
| **Godot Dialogic** | `.dtl` | Godot 4 Dialogic plugin | Flows, Sheets |
| **Unreal Engine** | `.csv` | Unreal Engine (Data Tables) | Flows, Sheets |
| **articy:draft** | `.xml` | articy:draft XML import | Flows, Sheets |

The {accent}Storyarn JSON{/accent} format is the only one that supports the full project -- all entity types including scenes, screenplays, and localization data. The engine-specific formats focus on flows and sheets, which is what game runtimes need for dialogue and variable state.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  The export page showing the format selector with all 7 formats, content section checkboxes, and asset mode options
</div>

## How to export

1. Navigate to **Export & Import** from your project sidebar.
2. **Choose a format** -- Select from the 7 available formats. The content checkboxes update to show which sections that format supports.
3. **Select content sections** -- Check or uncheck Sheets, Flows, Scenes, Screenplays, and Localization. Sections not supported by the selected format are disabled.
4. **Choose asset mode** -- Control how asset files (images, audio) are handled:

| Asset mode | Behavior |
|-----------|----------|
| **References only** | Asset URLs are included in the output (default, smallest file) |
| **Embedded** | Assets are Base64-encoded inline (larger file, fully self-contained) |
| **Bundled** | Output is a ZIP file with an assets folder alongside the data file |

5. **Set options** -- Toggle "Validate before export" and "Pretty print output" as needed.
6. **Download** -- Click the download button to get your file.

## Pre-export validation

Before downloading, you can run validation to catch issues that would cause problems in your game. Click **Validate** to check your project. The validator runs 9 checks and reports findings at three severity levels:

**Errors** (will likely break your game):
- Flows missing an Entry node
- Broken references: jump nodes pointing to non-existent hubs, subflow nodes referencing deleted flows, slug lines linked to missing scenes

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

## Import

Storyarn can import project data from {accent}.storyarn.json{/accent} files -- the same format produced by the Storyarn JSON export. This is useful for migrating projects between workspaces, restoring backups, or merging content from different team members.

### Import workflow

1. **Upload** -- Select a `.json` file (maximum 50 MB). Click "Upload & Preview" to parse it.

2. **Preview** -- Storyarn shows you what the file contains: counts of sheets, flows, nodes, scenes, screenplays, and assets. If any entity shortcuts conflict with existing content in your project, they are listed here.

3. **Resolve conflicts** -- When shortcut conflicts are detected, choose a strategy:

| Strategy | Behavior |
|----------|----------|
| **Skip** | Keep existing entities, ignore conflicting imports |
| **Overwrite** | Replace existing entities with imported data |
| **Rename** | Import with a new shortcut to avoid collision |

4. **Execute** -- Click Import to apply. The import runs inside a {accent}database transaction{/accent}, so it is all-or-nothing. If any step fails, everything is rolled back and you get an error message explaining what went wrong.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  The import preview step showing entity counts, detected shortcut conflicts, and the conflict resolution strategy selector
</div>

### Import safeguards

- **50 MB file size limit** -- Enforced at upload time.
- **JSON structure validation** -- The file must be a valid JSON object with the expected top-level keys.
- **Entity count limits** -- Prevents importing excessively large datasets that could impact performance.
- **Transactional execution** -- All-or-nothing. No partial imports.
- **Edit permissions required** -- Only project owners and editors can import. Viewers see a locked state.

## Other export paths

Beyond the main Export & Import page, Storyarn offers specialized export features in other areas:

**Localization export** -- From the Localization page, export translations as Excel (.xlsx) or CSV filtered by language. Import translated CSV files back with ID-based matching. See the [Localization Overview](/docs/localization/01-localization-overview) for details.

**Screenplay export** -- Export individual screenplays to Fountain format (.fountain) for use in screenwriting tools like Final Draft, Highland, or WriterSolo. Import existing Fountain files to create new screenplays in Storyarn.
