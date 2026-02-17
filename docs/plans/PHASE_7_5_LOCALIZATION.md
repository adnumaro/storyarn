# Phase 7.5: Localization System

> **Goal:** Provide professional-grade localization tools for game narrative content
>
> **Priority:** High - Critical differentiator for game development teams
>
> **Status:** Implemented (core complete, polish items pending)
>
> **Last Updated:** February 17, 2026

## Overview

This phase adds a comprehensive localization system that enables:
- Multiple language support per project
- Localization state tracking (pending, draft, in progress, review, final)
- Voice-over (VO) tracking and assignment
- Export/Import workflows for external translation teams
- Machine translation integration (DeepL)
- Localization reports and analytics

**Design Philosophy:** Localization is not an afterthought. All localizable content should be trackable, exportable, and manageable from day one.

---

## Architecture

### Domain Model (as implemented)

```
project_languages
├── id (integer, PK)
├── project_id (FK → projects, on_delete: delete_all)
├── locale_code (string, size: 10, not null)
├── name (string, not null)
├── is_source (boolean, default: false, not null)
├── position (integer, default: 0)
└── timestamps

localized_texts
├── id (integer, PK)
├── project_id (FK → projects, on_delete: delete_all)
├── source_type (string, not null)       # "flow_node" | "block" | "sheet" | "flow"
├── source_id (integer, not null)
├── source_field (string, not null)      # "text" | "value.content" | "name" | "response.{id}.text", etc.
├── source_text (text)
├── source_text_hash (string, size: 64)  # SHA-256 for change detection
├── locale_code (string, size: 10, not null)
├── translated_text (text)
├── status (string, default: "pending")  # pending | draft | in_progress | review | final
├── vo_status (string, default: "none")  # none | needed | recorded | approved
├── vo_asset_id (FK → assets, on_delete: nilify_all)
├── translator_notes (text)
├── reviewer_notes (text)
├── speaker_sheet_id (FK → sheets, on_delete: nilify_all)  # for dialogue lines
├── word_count (integer)
├── machine_translated (boolean, default: false)
├── last_translated_at (utc_datetime)
├── last_reviewed_at (utc_datetime)
├── translated_by_id (FK → users, on_delete: nilify_all)
├── reviewed_by_id (FK → users, on_delete: nilify_all)
└── timestamps

localization_glossary_entries
├── id (integer, PK)
├── project_id (FK → projects, on_delete: delete_all)
├── source_term (string, not null)
├── source_locale (string, size: 10, not null)
├── target_term (string)
├── target_locale (string, size: 10, not null)
├── context (text)
├── do_not_translate (boolean, default: false)
└── timestamps

translation_provider_configs
├── id (integer, PK)
├── project_id (FK → projects, on_delete: delete_all)
├── provider (string, not null, default: "deepl")
├── api_key_encrypted (binary)           # Cloak-encrypted
├── api_endpoint (string)
├── settings (map, default: %{})
├── is_active (boolean, default: true)
├── deepl_glossary_ids (map, default: %{})
└── timestamps
```

### Integration Points (as implemented)

```
Localizable Content Sources:
├── Flow Nodes (source_type: "flow_node")
│   ├── dialogue → text, stage_directions, menu_text
│   ├── dialogue → response.{id}.text (per response)
│   ├── scene → description
│   └── exit → label
│
├── Blocks (source_type: "block")
│   ├── text → config.label, value.content
│   ├── select → config.label, config.options.{key}
│   └── other → config.label
│
├── Sheets (source_type: "sheet")
│   └── name, description
│
└── Flows (source_type: "flow")
    └── name, description
```

### Module Structure

```
lib/storyarn/localization/
├── localization.ex              # Facade (defdelegate to submodules)
├── project_language.ex          # Schema + changesets
├── localized_text.ex            # Schema + changesets (create, update, source_update)
├── glossary_entry.ex            # Schema + changesets
├── provider_config.ex           # Schema + changeset (Cloak encryption)
├── language_crud.ex             # Language CRUD + ensure_source_language
├── text_crud.ex                 # Text CRUD with filters, pagination, upsert
├── glossary_crud.ex             # Glossary CRUD with language-pair queries
├── text_extractor.ex            # Auto-extraction hooks + bulk extract_all
├── batch_translator.ex          # Batch/single translation orchestrator
├── export_import.ex             # XLSX/CSV export + CSV import
├── reports.ex                   # Analytics queries
├── languages.ex                 # Static language list (44 languages)
├── html_handler.ex              # Rich text preprocessing for DeepL
├── translation_provider.ex      # Behaviour definition
└── providers/
    └── deepl.ex                 # DeepL API implementation
```

---

## Implementation Tasks

### 7.5.L.1 Project Languages

#### Database & Schema
- [x] Create `project_languages` table (migration `20260216120000`)
- [x] Add unique index on `(project_id, locale_code)`
- [x] Add partial unique index on `(project_id)` where `is_source = true`
- [x] Static language list (44 languages) in `Languages` module

#### Context Functions
- [x] `Localization.list_languages/1` - List project languages
- [x] `Localization.add_language/2` - Add language to project
- [x] `Localization.remove_language/1` - Remove language
- [x] `Localization.set_source_language/1` - Change source language
- [x] `Localization.reorder_languages/2` - Change display order
- [x] `Localization.ensure_source_language/1` - Auto-create from workspace source_locale
- [x] `Localization.get_source_language/1`, `get_target_languages/1`, `get_language_by_locale/2`

#### UI: Localization Page (inline management)
- [x] Source language badge (read-only, inherited from workspace)
- [x] Target language chips with remove button
- [x] "Add Language" dropdown with predefined `<select>` (no free text)
- [x] Remove language with confirmation modal
- [x] Workspace Settings: source locale `<select>` (field `source_locale` on workspaces table)

**Design change:** Language management moved from Project Settings to the Localization page itself. Source language is inherited from workspace, not configurable per-project.

---

### 7.5.L.2 Localized Texts Table

#### Database & Schema
- [x] Create `localized_texts` table (migration `20260216120000`)
- [x] Indexes: `(project_id, locale_code, status)`, `(source_type, source_id)`, `(speaker_sheet_id, locale_code)`
- [x] Partial index: `(project_id, locale_code)` where `status != 'final'`
- [x] Unique constraint on `(source_type, source_id, source_field, locale_code)`

#### Automatic Text Extraction
- [x] Hook into flow node save → `TextExtractor.extract_flow_node/1` (in `NodeCrud`)
- [x] Hook into block save → `TextExtractor.extract_block/1` (in `BlockCrud`)
- [x] Hook into sheet save → `TextExtractor.extract_sheet/1` (in `SheetCrud`)
- [x] Hook into flow save → `TextExtractor.extract_flow/1` (in `FlowCrud`)
- [x] Sync source_text via hash comparison (`source_text_hash`)
- [x] Downgrade `final` → `review` when source text changes
- [x] Delete localized_texts when source is deleted
- [x] Cleanup removed fields (e.g., deleted responses)
- [x] Bulk `extract_all/1` for syncing all existing project content
- [x] Auto-extract on adding a target language

#### Status Workflow
```
┌─────────┐    ┌───────┐    ┌─────────────┐    ┌────────┐    ┌───────┐
│ pending │ →  │ draft │ →  │ in_progress │ →  │ review │ →  │ final │
└─────────┘    └───────┘    └─────────────┘    └────────┘    └───────┘
     ↑                                              │
     └──────────────── (source changed) ────────────┘
```

| Status | Description |
|--------|-------------|
| pending | No translation exists yet |
| draft | Initial translation (possibly machine-translated) |
| in_progress | Translator is working on it |
| review | Translation complete, awaiting review |
| final | Approved and ready for export |

---

### 7.5.L.3 Localization View

#### Implementation
- [x] LiveView: `LocalizationLive.Index`
- [x] Filters: status, source type, search
- [x] Pagination (50 per page)
- [x] Progress bar per language
- [x] Batch translate button
- [x] Single-text translate button (per row)
- [x] Export buttons (XLSX, CSV)
- [x] Sync button (re-extract all content)
- [x] Source language badge + target language chips (inline management)
- [ ] Inline editing of translations (currently navigates to Edit page)
- [ ] Keyboard navigation (arrow keys, Enter to edit)

---

### 7.5.L.4 Translation Editor

#### Implementation
- [x] LiveView: `LocalizationLive.Edit`
- [x] Side-by-side source/translation view
- [x] Word count display
- [x] Status dropdown
- [x] "Translate with DeepL" button
- [x] Translator notes field
- [x] Machine-translated indicator
- [ ] VO section with audio upload/playback
- [ ] Glossary term highlighting
- [ ] History/audit log
- [ ] Length ratio indicator

---

### 7.5.L.5 Export/Import

#### Export (implemented)
- [x] Export endpoint: `GET /workspaces/:ws/projects/:proj/localization/export/:format/:locale`
- [x] Excel (.xlsx) generation via `Elixlsx`
- [x] CSV generation
- [x] Filter by status, source_type (query params)

#### Import (backend only)
- [x] CSV parsing and validation (`ExportImport.import_csv/1`)
- [x] Match by composite key (source_type, source_id, source_field, locale_code)
- [ ] Import LiveView with file upload UI
- [ ] Preview changes before applying
- [ ] Conflict handling options (skip, overwrite, mark for review)

---

### 7.5.L.6 Machine Translation (DeepL)

#### Integration
- [x] DeepL API client module (`Providers.DeepL`)
- [x] Project-level API key configuration (encrypted via Cloak)
- [x] Translate single text (`BatchTranslator.translate_single/2`)
- [x] Batch translate with chunking (50 texts/request) (`BatchTranslator.translate_batch/3`)
- [x] Preserve `{placeholders}` via `translate="no"` spans (`HtmlHandler`)
- [x] HTML tag handling for rich text

#### UI Integration
- [x] "Translate with DeepL" button in editor
- [x] "Translate all" batch button in localization view
- [x] Set status to "draft" after machine translation
- [x] `machine_translated` flag tracked

#### Configuration (Project Settings)
- [x] API key input (password field, shows masked if exists)
- [x] Tier selection (Free vs Pro endpoint)
- [x] "Test Connection" button with usage display
- [x] Save provider config

---

### 7.5.L.7 Localization Report

#### Implementation
- [x] LiveView: `LocalizationLive.Report`
- [x] Progress by language (progress bars, percentages, status breakdown)
- [x] Word counts by speaker (table with line counts + word counts)
- [x] VO progress stats (none, needed, recorded, approved)
- [x] Content breakdown by source type (badges)
- [ ] Export to PDF
- [ ] Recent activity / estimated completion

---

### 7.5.L.8 Glossary

#### Implementation
- [x] Create `localization_glossary_entries` table (migration `20260216120000`)
- [x] CRUD for glossary entries (per source/target language pair)
- [x] "Do not translate" flag for proper nouns
- [x] Context/notes field
- [x] DeepL glossary sync (`deepl_glossary_ids` on provider config)
- [ ] Highlight glossary terms in translation editor
- [ ] Export glossary for external teams

---

## Routes

```
# LiveView routes
GET /workspaces/:ws/projects/:proj/localization           → LocalizationLive.Index
GET /workspaces/:ws/projects/:proj/localization/report     → LocalizationLive.Report
GET /workspaces/:ws/projects/:proj/localization/:id        → LocalizationLive.Edit

# Controller route
GET /workspaces/:ws/projects/:proj/localization/export/:format/:locale → LocalizationExportController
```

---

## Testing

### Unit Tests (implemented)
- [x] Text extraction from nodes/blocks/sheets/flows (`text_extractor_test.exs`)
- [x] HTML handler preprocessing (`html_handler_test.exs`)
- [x] Batch translator with mocks (`batch_translator_test.exs`)
- [x] Export/import format validation (`export_import_test.exs`)
- [x] Glossary CRUD (`glossary_crud_test.exs`)
- [x] Reports queries (`reports_test.exs`)

### Integration Tests (implemented)
- [x] Project language CRUD (79 test cases in `localization_test.exs`)
- [x] Localized text CRUD with filters/pagination (54 test cases)
- [x] Upsert logic and source-change detection
- [x] Deletion cascades

### Fixtures
- [x] `LocalizationFixtures` — `language_fixture/2`, `source_language_fixture/2`, `localized_text_fixture/2`

### Not tested
- [ ] E2E: full localization workflow (add language → translate → export → import)
- [ ] E2E: VO upload and playback
- [ ] E2E: report generation

---

## Remaining Work

| Item | Category | Effort |
|------|----------|--------|
| Import UI (upload, preview, conflict handling) | Export/Import | Medium |
| VO section in editor (upload, playback, status) | Translation Editor | Medium |
| Inline editing in list view | Localization View | Medium |
| History/audit log for translations | Translation Editor | Medium |
| Keyboard navigation (arrow keys, Enter) | Localization View | Small |
| Glossary term highlighting in editor | Translation Editor | Small |
| Glossary export for external teams | Glossary | Small |
| PDF export for reports | Report | Small |
| Recent activity in report | Report | Small |
| Length ratio indicator in editor | Translation Editor | Small |

---

## Open Questions

1. **Text key generation:** Auto-generate IDs or let users define custom keys?
   - Recommendation: Auto-generate with option to customize

2. **Plural forms:** How to handle pluralization (1 item vs 2 items)?
   - Recommendation: Defer to future - use separate strings for now

3. **Variables in text:** How to handle `{player_name}` style variables?
   - Decision: Preserved as-is; `HtmlHandler` wraps them in `translate="no"` spans for DeepL

4. **VO file naming:** Convention for audio file names?
   - Recommendation: `{locale}/{text_key}.{ext}` e.g., `es/dlg_001.wav`

---

## Success Criteria

- [x] Projects can have multiple languages configured
- [x] All dialogue and text content auto-extracted for translation
- [x] Translators can work in dedicated localization view
- [x] Status workflow tracks translation progress
- [x] Export works with Excel/CSV for external teams
- [x] DeepL integration provides initial translations
- [x] Reports show progress per language and character word counts
- [x] VO status tracked separately from text translation (schema-level)
- [ ] Import UI for external teams to upload translations back
- [ ] VO upload/playback in translation editor
- [ ] Export includes localization data for game engines (JSON export)

---

## Comparison: articy:draft vs Storyarn

| Feature | articy:draft | Storyarn |
|---------|--------------|----------|
| Language management | Built-in | Built-in (inline in Localization page) |
| Translation states | 3 states | 5 states (more granular) |
| DeepL integration | Yes | Yes (with glossary sync) |
| Excel export/import | Yes | Yes (export done, import backend only) |
| VO tracking | Basic | Schema ready (UI pending) |
| Per-character reports | Word count only | Words + lines + VO status |
| Glossary | No | Yes (CRUD + DeepL sync) |
| Inline editing | Limited | Via dedicated editor page |
| Web-based | No (desktop) | Yes (collaborative) |
| Source change detection | Manual | Automatic (hash-based, downgrades status) |
| Bulk text extraction | Manual | Automatic hooks + manual Sync button |

**Key Advantages:**
- More granular status workflow for professional pipelines
- Automatic source change detection with hash comparison
- Character-based analytics for VO budgeting
- Web-based = multiple translators can work simultaneously
- Glossary integration with DeepL API

---

*This phase was implemented independently of other enhancements. Migration: `20260216120000_create_localization_tables.exs` + `20260216130000_add_source_locale_to_workspaces.exs`*
