# Phase 7.5: Localization System

> **Goal:** Provide professional-grade localization tools for game narrative content
>
> **Priority:** High - Critical differentiator for game development teams
>
> **Last Updated:** February 2, 2026

## Overview

This phase adds a comprehensive localization system that enables:
- Multiple language support per project
- Localization state tracking (draft, in progress, final, needs review)
- Voice-over (VO) tracking and assignment
- Export/Import workflows for external translation teams
- Machine translation integration (DeepL)
- Localization reports and analytics

**Design Philosophy:** Localization is not an afterthought. All localizable content should be trackable, exportable, and manageable from day one.

---

## Architecture

### Domain Model

```
project_languages            # NEW TABLE
├── id
├── project_id (FK)
├── locale_code              # "en", "es", "de", "ja", etc.
├── name                     # "English", "Spanish", etc.
├── is_source                # boolean - the source/reference language
├── position                 # ordering in UI
└── timestamps

localized_texts              # NEW TABLE
├── id
├── project_id (FK)
├── source_type              # "flow_node" | "page_block" | "page_name"
├── source_id                # UUID of the source entity
├── source_field             # "text" | "content" | "name" | "option_0", etc.
├── source_text              # Original text (from source language)
├── locale_code              # Target language
├── translated_text          # The translation
├── status                   # "pending" | "draft" | "in_progress" | "review" | "final"
├── vo_status                # "none" | "needed" | "recorded" | "approved"
├── vo_asset_id (FK)         # Link to recorded audio file
├── translator_notes         # Notes for translators
├── reviewer_notes           # Notes from review process
├── character_id (FK)        # For dialogue - who speaks this line (for reports)
├── word_count               # Cached word count
├── last_translated_at
├── last_reviewed_at
├── translated_by_id (FK)
├── reviewed_by_id (FK)
└── timestamps

localization_glossary        # NEW TABLE (optional, for consistency)
├── id
├── project_id (FK)
├── term                     # "Eldoria", "mana", "the Void"
├── locale_code
├── translation              # How this term should be translated
├── context                  # Usage notes
├── do_not_translate         # boolean - for proper nouns
└── timestamps
```

### Integration Points

```
Localizable Content Sources:
├── Flow Nodes
│   ├── dialogue.data.text           # Main dialogue line
│   ├── dialogue.data.speaker_name   # If custom (not from page)
│   ├── choice.data.options[].text   # Choice option texts
│   └── choice.data.prompt           # Choice prompt text
│
├── Page Blocks
│   ├── text.value.content
│   ├── rich_text.value.content
│   └── select.config.options[].label
│
└── Page Metadata
    └── page.name                     # Page titles can be localized
```

---

## Implementation Tasks

### 7.5.L.1 Project Languages

#### Database & Schema
- [ ] Create `project_languages` table (migration)
- [ ] Add unique index on `(project_id, locale_code)`
- [ ] Add index on `(project_id, is_source)`
- [ ] Ensure exactly one `is_source = true` per project

#### Context Functions
- [ ] `Localization.list_languages/1` - List project languages
- [ ] `Localization.add_language/2` - Add language to project
- [ ] `Localization.remove_language/2` - Remove language (cascade translations)
- [ ] `Localization.set_source_language/2` - Change source language
- [ ] `Localization.reorder_languages/2` - Change display order

#### UI: Project Settings > Languages
- [ ] Language list with drag-to-reorder
- [ ] "Add Language" button with locale picker
- [ ] Source language indicator (star/badge)
- [ ] Remove language (with confirmation - deletes translations)
- [ ] Common locales: EN, ES, DE, FR, IT, PT, JA, KO, ZH-CN, ZH-TW, RU, PL

```
┌─────────────────────────────────────────────────────────────────┐
│ PROJECT SETTINGS > Languages                                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ Source Language                                                 │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ ⭐ English (en)                              [Change]       │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│ Translation Languages                          [+ Add Language] │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ [≡] Spanish (es)           Progress: 45%           [🗑️]    │ │
│ │ [≡] German (de)            Progress: 12%           [🗑️]    │ │
│ │ [≡] Japanese (ja)          Progress: 0%            [🗑️]    │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

### 7.5.L.2 Localized Texts Table

#### Database & Schema
- [ ] Create `localized_texts` table (migration)
- [ ] Add indexes for common queries:
  - `(project_id, locale_code, status)`
  - `(source_type, source_id)`
  - `(character_id, locale_code)`
- [ ] Add unique constraint on `(source_type, source_id, source_field, locale_code)`

#### Automatic Text Extraction
- [ ] Hook into flow node save → extract localizable texts
- [ ] Hook into page block save → extract localizable texts
- [ ] Sync source_text when source content changes
- [ ] Mark translations as "needs_review" when source changes
- [ ] Delete localized_texts when source is deleted

#### Status Workflow
```
┌─────────┐    ┌───────┐    ┌─────────────┐    ┌────────┐    ┌───────┐
│ pending │ →  │ draft │ →  │ in_progress │ →  │ review │ →  │ final │
└─────────┘    └───────┘    └─────────────┘    └────────┘    └───────┘
     ↑                                              │
     └──────────────── (source changed) ────────────┘
```

**Status Definitions:**
| Status | Description |
|--------|-------------|
| pending | No translation exists yet |
| draft | Initial translation (possibly machine-translated) |
| in_progress | Translator is working on it |
| review | Translation complete, awaiting review |
| final | Approved and ready for export |

---

### 7.5.L.3 Localization View

A dedicated view to manage all localizable content.

#### UI: Main Localization Interface

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ LOCALIZATION                                          [Export ▼] [Import]   │
├─────────────────────────────────────────────────────────────────────────────┤
│ Language: [Spanish (es) ▼]    Filter: [All Status ▼] [All Sources ▼]       │
│ Character: [All ▼]            Search: [🔍                              ]    │
├─────────────────────────────────────────────────────────────────────────────┤
│ Progress: ████████░░░░░░░░░░░░ 234/520 (45%)                               │
│ Final: 180 │ Review: 24 │ In Progress: 30 │ Pending: 286                   │
├───────────────────────────────┬─────────────────────────────────────────────┤
│ Source (English)              │ Translation (Spanish)          │ Status    │
├───────────────────────────────┼─────────────────────────────────┼───────────┤
│ 💬 "Hello, traveler!"         │ "¡Hola, viajero!"              │ ✅ Final  │
│    Jaime @ Act1/TavernEntry   │                                │ 🎤 VO ✓   │
├───────────────────────────────┼─────────────────────────────────┼───────────┤
│ 💬 "I've been waiting for     │ "Te he estado esperando. Los   │ 🟡 Review │
│    you. The dark times are    │ tiempos oscuros se acercan."   │ 🎤 Needed │
│    coming."                   │                                │           │
│    Elena @ Act1/Prophecy      │ [Translator note: Check tone]  │           │
├───────────────────────────────┼─────────────────────────────────┼───────────┤
│ ❓ "Accept the quest"         │                                │ ⬜ Pending│
│    Choice @ Act1/QuestOffer   │ [Click to translate...]        │           │
├───────────────────────────────┼─────────────────────────────────┼───────────┤
│ 📄 "Jaime the Brave"          │ "Jaime el Valiente"            │ ✅ Final  │
│    Page name                  │                                │           │
└───────────────────────────────┴─────────────────────────────────┴───────────┘
```

#### Implementation Tasks
- [ ] LiveView: `LocalizationLive.Index`
- [ ] Filters: status, source type, character, search
- [ ] Inline editing of translations
- [ ] Status change dropdown
- [ ] VO status indicators
- [ ] Link to source (click to open flow/page)
- [ ] Keyboard navigation (arrow keys, Enter to edit)
- [ ] Pagination/virtual scroll for large projects

---

### 7.5.L.4 Translation Editor

Detailed editor for individual translations.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ TRANSLATION EDITOR                                              [← Back]    │
├─────────────────────────────────────────────────────────────────────────────┤
│ Source: Flow Node > Act 1 > Tavern Entry > Dialogue                        │
│ Character: Jaime                                         [Open in Flow →]   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│ SOURCE (English)                                                            │
│ ┌─────────────────────────────────────────────────────────────────────────┐ │
│ │ Hello, traveler! I've been expecting you. The prophecy spoke of        │ │
│ │ someone like you arriving on this very day.                            │ │
│ └─────────────────────────────────────────────────────────────────────────┘ │
│ Words: 23 │ Characters: 142                                                 │
│                                                                             │
│ TRANSLATION (Spanish)                              Status: [Review ▼]       │
│ ┌─────────────────────────────────────────────────────────────────────────┐ │
│ │ ¡Hola, viajero! Te estaba esperando. La profecía hablaba de alguien   │ │
│ │ como tú llegando precisamente hoy.                                     │ │
│ └─────────────────────────────────────────────────────────────────────────┘ │
│ Words: 21 │ Characters: 138 │ Ratio: 97%                                    │
│                                                                             │
│ [🤖 Translate with DeepL]  [📋 Copy Source]  [↩️ Revert]                    │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ VOICE OVER                                                                  │
│ Status: [Needed ▼]                                                          │
│ Actor: [                    ]                                               │
│ Audio: [No file uploaded]                              [Upload Audio]       │
│ Notes for actor: [                                                    ]     │
├─────────────────────────────────────────────────────────────────────────────┤
│ NOTES                                                                       │
│ Translator: [Keep the enthusiastic tone                              ]      │
│ Reviewer:   [Approved - matches character voice                      ]      │
├─────────────────────────────────────────────────────────────────────────────┤
│ GLOSSARY MATCHES                                                            │
│ • "prophecy" → "profecía" (consistent with project glossary)               │
│ • "traveler" → "viajero" (do not use "viajante")                           │
├─────────────────────────────────────────────────────────────────────────────┤
│ HISTORY                                                                     │
│ • Feb 2, 10:30 - Status changed to Review (by Maria)                       │
│ • Feb 2, 09:15 - Translation edited (by Juan)                              │
│ • Feb 1, 18:00 - Auto-translated with DeepL                                │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### Implementation Tasks
- [ ] LiveView: `LocalizationLive.Edit`
- [ ] Side-by-side source/translation view
- [ ] Character/word count display
- [ ] Length ratio indicator (for UI fitting)
- [ ] Status dropdown with workflow enforcement
- [ ] VO section with audio upload
- [ ] Notes fields (translator, reviewer)
- [ ] Glossary term highlighting
- [ ] History log

---

### 7.5.L.5 Export/Import

Standard workflow for external translation teams.

#### Export Format (Excel/CSV)

```csv
id,source_type,source_id,source_field,character,location,source_text,translation,status,vo_status,translator_notes,max_length
abc123,flow_node,uuid-1,text,Jaime,Act1/Tavern,"Hello, traveler!","¡Hola, viajero!",final,recorded,,50
def456,flow_node,uuid-2,text,Elena,Act1/Prophecy,"The dark times...","",pending,needed,"Keep serious tone",100
```

#### Export Options
- [ ] Format: Excel (.xlsx) or CSV
- [ ] Languages: Select which to export
- [ ] Filter: By status, source type, character
- [ ] Include: VO columns, notes, context
- [ ] Context columns: character name, location path

#### Import Process
- [ ] Upload Excel/CSV file
- [ ] Preview changes before applying
- [ ] Match by ID (required column)
- [ ] Update only: translated_text, status, notes
- [ ] Conflict handling: skip, overwrite, mark for review
- [ ] Import report: success/error counts

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ IMPORT TRANSLATIONS                                                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│ File: translations_spanish_v2.xlsx                     [Choose File]        │
│                                                                             │
│ Preview (first 10 rows):                                                    │
│ ┌─────────────────────────┬─────────────────────────┬──────────────────────┐│
│ │ Source                  │ New Translation         │ Status               ││
│ ├─────────────────────────┼─────────────────────────┼──────────────────────┤│
│ │ "Hello, traveler!"      │ "¡Hola, viajero!"       │ ✅ Updated           ││
│ │ "The dark times..."     │ "Los tiempos oscuros.." │ ✅ New               ││
│ │ "Accept quest"          │ "Acepta misión"         │ ⚠️ Source changed   ││
│ └─────────────────────────┴─────────────────────────┴──────────────────────┘│
│                                                                             │
│ On conflict: ○ Skip  ● Overwrite  ○ Mark for review                        │
│                                                                             │
│ Summary: 234 updates, 12 new, 3 conflicts, 1 error                         │
│                                                                             │
│                                        [Cancel] [Import 249 translations]   │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### Implementation Tasks
- [ ] Export endpoint: `GET /projects/:id/localization/export`
- [ ] Excel generation with proper formatting (use `Elixlsx` or similar)
- [ ] CSV generation
- [ ] Import LiveView with preview
- [ ] File parsing and validation
- [ ] Batch update with conflict detection
- [ ] Import history/audit log

---

### 7.5.L.6 Machine Translation (DeepL)

#### Integration
- [ ] DeepL API client module
- [ ] Project-level API key configuration (or workspace-level)
- [ ] Translate single text
- [ ] Batch translate (with rate limiting)
- [ ] Preserve formatting/variables in text

#### UI Integration
- [ ] "Translate with DeepL" button in editor
- [ ] "Auto-translate all pending" in localization view
- [ ] Set status to "draft" after machine translation
- [ ] Show "Machine translated" indicator

#### Configuration
```
┌─────────────────────────────────────────────────────────────────┐
│ PROJECT SETTINGS > Localization                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ DeepL Integration                                               │
│ API Key: [••••••••••••••••••••••••]              [Test] [Save]  │
│ Status: ✅ Connected (Free tier, 450,000/500,000 chars used)    │
│                                                                 │
│ Auto-translate Settings                                         │
│ ☐ Auto-translate new content to all languages                   │
│ ☑ Mark auto-translated content as "draft"                       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

### 7.5.L.7 Localization Report

Analytics for project managers and producers.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ LOCALIZATION REPORT                              [Export PDF] [Export CSV]  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│ OVERVIEW                                                                    │
│ ┌─────────────────────────────────────────────────────────────────────────┐ │
│ │ Total strings: 520  │  Total words: 12,450  │  Total characters: 68,200│ │
│ └─────────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│ PROGRESS BY LANGUAGE                                                        │
│ ┌──────────────┬──────────┬──────────┬──────────┬──────────┬─────────────┐ │
│ │ Language     │ Pending  │ Draft    │ Progress │ Review   │ Final       │ │
│ ├──────────────┼──────────┼──────────┼──────────┼──────────┼─────────────┤ │
│ │ Spanish (es) │ 50       │ 80       │ 40       │ 100      │ 250 (48%)   │ │
│ │ German (de)  │ 300      │ 100      │ 20       │ 50       │ 50 (10%)    │ │
│ │ Japanese(ja) │ 500      │ 10       │ 5        │ 5        │ 0 (0%)      │ │
│ └──────────────┴──────────┴──────────┴──────────┴──────────┴─────────────┘ │
│                                                                             │
│ WORD COUNT BY CHARACTER (for VO budgeting)                                  │
│ ┌──────────────┬──────────┬──────────┬──────────┬──────────┬─────────────┐ │
│ │ Character    │ Lines    │ Words EN │ Words ES │ Words DE │ VO Status   │ │
│ ├──────────────┼──────────┼──────────┼──────────┼──────────┼─────────────┤ │
│ │ Jaime        │ 145      │ 2,340    │ 2,450    │ 2,100    │ 80% done    │ │
│ │ Elena        │ 89       │ 1,560    │ 1,620    │ 1,480    │ 45% done    │ │
│ │ Narrator     │ 234      │ 5,200    │ 5,400    │ 4,900    │ 0% done     │ │
│ │ (NPCs)       │ 52       │ 850      │ 890      │ 820      │ 100% done   │ │
│ └──────────────┴──────────┴──────────┴──────────┴──────────┴─────────────┘ │
│                                                                             │
│ RECENT ACTIVITY                                                             │
│ • Today: 45 translations added, 12 moved to final                          │
│ • This week: 234 translations, 89 finalizations                            │
│ • Estimated completion (at current pace): 3 weeks                          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### Implementation Tasks
- [ ] LiveView: `LocalizationLive.Report`
- [ ] Progress calculations per language
- [ ] Word/line counts per character
- [ ] VO progress tracking
- [ ] Export to PDF (summary report)
- [ ] Export to CSV (detailed data)

---

### 7.5.L.8 Glossary (Optional)

Maintain consistent terminology across translations.

#### Implementation Tasks
- [ ] Create `localization_glossary` table
- [ ] CRUD for glossary terms
- [ ] "Do not translate" flag for proper nouns
- [ ] Highlight glossary terms in translation editor
- [ ] Suggest translations based on glossary
- [ ] Export glossary for external teams

---

## Database Migrations

### Migration 1: Project Languages

```elixir
create table(:project_languages) do
  add :project_id, references(:projects, on_delete: :delete_all), null: false
  add :locale_code, :string, null: false
  add :name, :string, null: false
  add :is_source, :boolean, default: false
  add :position, :integer, default: 0

  timestamps()
end

create unique_index(:project_languages, [:project_id, :locale_code])
create index(:project_languages, [:project_id, :is_source])
```

### Migration 2: Localized Texts

```elixir
create table(:localized_texts) do
  add :project_id, references(:projects, on_delete: :delete_all), null: false
  add :source_type, :string, null: false
  add :source_id, :binary_id, null: false
  add :source_field, :string, null: false
  add :source_text, :text
  add :locale_code, :string, null: false
  add :translated_text, :text
  add :status, :string, default: "pending"
  add :vo_status, :string, default: "none"
  add :vo_asset_id, references(:assets, on_delete: :nilify_all)
  add :translator_notes, :text
  add :reviewer_notes, :text
  add :character_id, references(:pages, on_delete: :nilify_all)
  add :word_count, :integer
  add :last_translated_at, :utc_datetime
  add :last_reviewed_at, :utc_datetime
  add :translated_by_id, references(:users, on_delete: :nilify_all)
  add :reviewed_by_id, references(:users, on_delete: :nilify_all)

  timestamps()
end

create unique_index(:localized_texts,
  [:source_type, :source_id, :source_field, :locale_code],
  name: :localized_texts_source_locale_unique)
create index(:localized_texts, [:project_id, :locale_code, :status])
create index(:localized_texts, [:character_id, :locale_code])
```

### Migration 3: Glossary (Optional)

```elixir
create table(:localization_glossary) do
  add :project_id, references(:projects, on_delete: :delete_all), null: false
  add :term, :string, null: false
  add :locale_code, :string, null: false
  add :translation, :string
  add :context, :text
  add :do_not_translate, :boolean, default: false

  timestamps()
end

create unique_index(:localization_glossary, [:project_id, :term, :locale_code])
```

---

## Implementation Order

| Order | Task | Dependencies | Testable Outcome |
|-------|------|--------------|------------------|
| 1 | Project languages table + CRUD | None | Can add languages to project |
| 2 | Project settings UI for languages | Task 1 | UI to manage languages |
| 3 | Localized texts table | Task 1 | Schema ready |
| 4 | Auto-extraction hooks (flow nodes) | Task 3 | Texts extracted on save |
| 5 | Auto-extraction hooks (page blocks) | Task 3 | Texts extracted on save |
| 6 | Basic localization view (list) | Tasks 3-5 | Can see all texts |
| 7 | Inline translation editing | Task 6 | Can translate in list view |
| 8 | Translation editor (detailed) | Task 6 | Full editor works |
| 9 | Status workflow | Task 7 | Status changes work |
| 10 | Export to Excel/CSV | Task 6 | Can export for external teams |
| 11 | Import from Excel/CSV | Task 10 | Can import translations |
| 12 | DeepL integration | Task 8 | Machine translation works |
| 13 | Localization report | Tasks 3-5 | Report view works |
| 14 | VO tracking | Task 8, Assets | Audio upload works |
| 15 | Glossary | Task 8 | Glossary CRUD works |

---

## Testing Strategy

### Unit Tests
- [ ] Locale code validation
- [ ] Status workflow transitions
- [ ] Word count calculation
- [ ] Text extraction from nodes/blocks
- [ ] Export/import format validation

### Integration Tests
- [ ] Add language to project
- [ ] Auto-extract texts when saving flow node
- [ ] Update translation and change status
- [ ] Export and reimport translations
- [ ] DeepL translation request

### E2E Tests
- [ ] Full localization workflow: add language → translate → export → import
- [ ] VO upload and playback
- [ ] Report generation

---

## Export Considerations

When exporting project to JSON for game engines:

```json
{
  "localization": {
    "languages": ["en", "es", "de"],
    "source_language": "en",
    "strings": {
      "dlg_001": {
        "en": "Hello, traveler!",
        "es": "¡Hola, viajero!",
        "de": "Hallo, Reisender!"
      },
      "dlg_002": {
        "en": "The dark times are coming.",
        "es": "Los tiempos oscuros se acercan.",
        "de": "Die dunklen Zeiten kommen."
      }
    },
    "voice_over": {
      "dlg_001": {
        "en": "assets/vo/en/dlg_001.wav",
        "es": "assets/vo/es/dlg_001.wav"
      }
    }
  },
  "flows": {
    "nodes": [
      {
        "type": "dialogue",
        "data": {
          "text_key": "dlg_001",
          "speaker": "#mc.jaime"
        }
      }
    ]
  }
}
```

---

## Open Questions

1. **Text key generation:** Auto-generate IDs or let users define custom keys?
   - Recommendation: Auto-generate with option to customize

2. **Plural forms:** How to handle pluralization (1 item vs 2 items)?
   - Recommendation: Defer to future - use separate strings for now

3. **Variables in text:** How to handle `{player_name}` style variables?
   - Recommendation: Preserve as-is, document for translators

4. **VO file naming:** Convention for audio file names?
   - Recommendation: `{locale}/{text_key}.{ext}` e.g., `es/dlg_001.wav`

---

## Success Criteria

- [ ] Projects can have multiple languages configured
- [ ] All dialogue and text content auto-extracted for translation
- [ ] Translators can work in dedicated localization view
- [ ] Status workflow tracks translation progress
- [ ] Export/Import works with Excel for external teams
- [ ] DeepL integration provides initial translations
- [ ] Reports show progress per language and character word counts
- [ ] VO status tracked separately from text translation
- [ ] Export includes localization data for game engines

---

## Comparison: articy:draft vs Storyarn

| Feature | articy:draft | Storyarn |
|---------|--------------|----------|
| Language management | Built-in | Built-in |
| Translation states | 3 states | 5 states (more granular) |
| DeepL integration | Yes | Yes |
| Excel export/import | Yes | Yes |
| VO tracking | Basic | Full (status + assets) |
| Per-character reports | Word count only | Words + lines + VO status |
| Glossary | No | Yes |
| Inline editing | Limited | Full (in list view) |
| Web-based | No (desktop) | Yes (collaborative) |

**Key Advantages:**
- More granular status workflow for professional pipelines
- Full VO asset management with audio upload
- Character-based analytics for budgeting
- Web-based = multiple translators can work simultaneously

---

*This phase can be implemented independently of 7.5 Pages/Flows enhancements.*
