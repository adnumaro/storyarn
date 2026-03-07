%{
  title: "Localization Overview",
  category_label: "Localization",
  order: 1,
  description: "Translate your project into multiple languages with extraction, DeepL, and glossaries."
}
---

Storyarn's localization system gives you full control over translating your narrative content -- from dialogue lines and response options to sheet names and block labels. It handles {accent}automatic text extraction{/accent}, machine translation via DeepL, glossary enforcement, voice-over tracking, and detailed progress reports.

## How it works

The localization workflow has four stages, each designed to minimize manual effort while keeping translators in control.

### 1. Set up your languages

Open **Localization** in your project sidebar. Your project's source language is detected automatically from your workspace settings and shown as a primary badge. Add target languages from a curated list of {accent}45 supported languages{/accent} covering all major game localization markets -- from English, Spanish, and Japanese to Arabic, Thai, and Chinese (Simplified/Traditional).

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  The localization index page showing the source language badge, target language chips with remove buttons, and the Add Language dropdown
</div>

### 2. Extract translatable content

Click **Sync** to scan your entire project and extract every piece of translatable text. The extractor pulls content from four source types:

| Source | What gets extracted |
|--------|-------------------|
| **Flow nodes** | Dialogue text, stage directions, menu text, individual response texts, slug line descriptions, exit labels |
| **Sheets** | Sheet name, sheet description |
| **Blocks** | Block labels, text content values, select option labels |
| **Flows** | Flow name, flow description |

Each extracted text gets a SHA-256 hash of its source content. When you re-sync, Storyarn detects changes -- if the source text has been modified since the last translation, the system can flag it for re-translation. Extraction is idempotent: running it multiple times never creates duplicates thanks to upsert logic.

Dialogue nodes also track the **speaker sheet ID**, so reports can break down word counts by character.

### 3. Translate

You have three paths to get translations done:

**Manual editing** -- Open any text entry to edit the translation directly. Best for creative adaptation, cultural nuances, and final polish.

**DeepL integration** -- Connect your DeepL API key in project settings to unlock machine translation. You can translate a single entry (click the sparkle icon) or batch-translate all pending texts for a language with one click.

Under the hood, DeepL translation is {accent}HTML-aware{/accent}: rich text from dialogue nodes is sent with `tag_handling: "html"` so formatting is preserved. Variable placeholders like `{character_name}` are wrapped in `<span translate="no">` before sending, then unwrapped after -- so they come back untouched. Batch requests are chunked into groups of 50 texts (DeepL's per-request limit). Your glossary entries are automatically applied during translation.

**Export for external translators** -- Download an Excel (.xlsx) or CSV file filtered by language, status, or source type. Send it to your translation team, then import the completed file back. The import matches rows by ID and updates translations and statuses.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  The translation table showing source text, translation, status badges, word counts, and action buttons (edit, translate with DeepL)
</div>

### 4. Review and finalize

Every text entry follows a {accent}five-stage workflow{/accent}:

| Status | Meaning |
|--------|---------|
| **Pending** | Extracted but not yet translated |
| **Draft** | Machine-translated or first pass complete |
| **In Progress** | Translator is actively working on it |
| **Review** | Translation complete, awaiting review |
| **Final** | Approved and ready for export |

Machine translations are automatically set to **Draft** status. If the source text changes after translation, the system can detect the hash mismatch for re-review.

## Translation workflow table

Filter the translation table by language, status, and source type. Search across both source and translated text. The table is paginated (50 entries per page) and shows:

- Source type icon (flow node, block, sheet, flow)
- Source text (HTML-stripped for preview)
- Current translation with a "MT" badge if machine-translated
- Status badge
- Word count

## Glossary

The glossary ensures {accent}consistent terminology{/accent} across all translations. Each entry maps a source term to a target term for a specific language pair.

| Field | Purpose |
|-------|---------|
| **Source term** | The term in your source language |
| **Target term** | The required translation |
| **Source locale / Target locale** | The language pair this entry applies to |
| **Context** | Usage notes for translators |
| **Do not translate** | When enabled, the term is kept as-is (proper nouns, brand names) |

Glossary entries are automatically applied during DeepL translation via the DeepL Glossary API. When translating manually, the glossary serves as a reference.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  The glossary management interface showing a list of term pairs with context notes
</div>

## Reports

The localization report gives you a bird's-eye view of your translation progress. It provides four types of data:

**Progress by language** -- For each target language, see the total number of text entries, how many have reached "final" status, and the completion percentage.

**Word counts by speaker** -- For any given language, see how many words and lines each character (speaker sheet) has. Useful for estimating voice-over recording time and cost.

**Voice-over progress** -- Track VO status across four stages: none, needed, recorded, and approved. Each text entry from dialogue nodes has its own VO status independent of the translation status.

**Content breakdown** -- See how many text entries come from each source type (flow nodes, blocks, sheets, flows) for a given language.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  The localization report page showing progress bars per language, word count table by speaker, and VO status breakdown
</div>

## Export and import

**Export** -- Download translations as Excel (.xlsx) or CSV, filtered by language. The export includes: ID, source type, source ID, source field, locale, source text (HTML-stripped), translation, status, word count, machine-translated flag, and translator/reviewer notes (Excel only).

**Import** -- Upload a CSV file with at minimum an ID column. The importer matches each row to an existing text entry by ID, then updates the translation and/or status. Valid statuses for import: `pending`, `draft`, `in_progress`, `review`, `final`. Rows with empty translations or unrecognized statuses are skipped. The import reports how many entries were updated, skipped, and any errors encountered.
