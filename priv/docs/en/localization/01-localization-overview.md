%{
  title: "Localization Overview",
  category_label: "Localization",
  order: 1,
  description: "Translate your project into multiple languages with extraction, DeepL, and glossaries."
}
---

Storyarn's localization system lets you manage translations for your entire project — from dialogue in flows to screenplay text — with tools for extraction, machine translation, glossary management, and progress tracking.

## Workflow

### 1. Add languages

Go to **Localization** in your project and add the languages you need. One language is set as the **default** (source language).

### 2. Extract texts

Click **Extract** to scan your project and pull all translatable texts:

- Dialogue node text and response text from flows
- Screenplay element text
- Menu text, stage directions

Each text gets a unique **localization ID** for tracking.

### 3. Translate

Three options for translation:

| Method | Best for |
|--------|---------|
| **Manual** | Final polish, creative adaptation |
| **DeepL integration** | Fast first drafts for all texts |
| **Export → External** | Professional translators using their own tools |

### 4. Review and export

- Use **localization reports** to track progress per language
- Export to **Excel** or **CSV** for external review
- Import translations back from external files

## DeepL integration

Connect your DeepL API key in project settings to enable machine translation:

- Translate individual texts or entire languages in batch
- DeepL respects your glossary entries for consistent terminology
- Use as a starting point, then refine manually

## Glossary

Maintain a **glossary** of terms that should be translated consistently:

| Source term | Target (Spanish) | Notes |
|-------------|-----------------|-------|
| Health Points | Puntos de Vida | Always abbreviated as PV |
| The Tavern | La Taberna | Proper noun — capitalize |
| Quest | Misión | Not "búsqueda" |

The glossary is applied automatically during DeepL translation and serves as a reference for manual translators.

## Reports

The localization report gives you a bird's-eye view:

- **Per-language progress** — percentage of texts translated
- **Missing translations** — texts that still need work
- **Stale translations** — source text changed since last translation
