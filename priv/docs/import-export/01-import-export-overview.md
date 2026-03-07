%{
  title: "Import & Export",
  category_label: "Import & Export",
  order: 1,
  description: "Get your content in and out of Storyarn in various formats."
}
---

Storyarn supports several import and export formats to integrate with your existing tools and pipelines.

## Export formats

| Format | Content | Use case |
|--------|---------|----------|
| **Fountain** (.fountain) | Screenplays | Professional screenwriting tools (Final Draft, Highland) |
| **Excel** (.xlsx) | Localization texts | Professional translators, spreadsheet review |
| **CSV** | Localization texts | Lightweight translation exchange |
| **JSON** | Project data | Game engine integration, custom pipelines |

## Screenplay export

Export any screenplay to Fountain format:

1. Open the screenplay
2. Click **Export → Fountain**
3. Download the `.fountain` file

The exported file follows the Fountain specification and opens in any compatible editor.

## Screenplay import

Import existing Fountain files into Storyarn:

1. Navigate to Screenplays
2. Click **Import → Fountain**
3. Select your `.fountain` file
4. Storyarn parses and creates the screenplay with proper element types

## Localization export

Export translations for external review or professional translators:

1. Go to **Localization**
2. Click **Export**
3. Choose format (Excel or CSV) and locale
4. Download the file

The export includes localization IDs, source text, and current translations — ready for translators to fill in.

## Localization import

Import translated files back:

1. Go to **Localization**
2. Click **Import**
3. Upload the translated Excel/CSV file
4. Storyarn matches by localization ID and updates translations

## Project export

Export your entire project data as JSON for game engine integration or backup purposes.
