# Dashboard Data Investigation Summary (RESOLVED)

## Overview

Parallel investigation of all project dashboard metrics. Each stat was verified against actual database data.

---

## Stats That Are CORRECT

| Stat | Value | Verified |
|------|-------|----------|
| sheet_count | 19 | Counts all sheets including groups (correct) |
| variable_count | 83 | Uses `list_project_variables/1` — includes block + table variables |
| flow_count | 6 | Properly scoped and soft-delete filtered |
| dialogue_count | 1 | Filters deleted nodes AND deleted flows |
| scene_count | 1 | Properly scoped |
| node_distribution | entry:6, exit:6, dialogue:1 | Matches raw query |
| speakers | Seven: 1 line | Correct (minor: left_join doesn't exclude deleted sheets) |
| recent_activity | 10 items | Correct (note: doesn't include screenplays in union) |

**All project_id scoping is correct — no cross-project data leakage.**

---

## Stats That Are WRONG or MISLEADING

### 1. Empty Sheets Detection — CORRECT but MISLEADING

**What it reports:** "9 sheet(s) have no blocks defined"

**Reality:** The detection logic IS correct — it already excludes group/folder sheets (sheets with children). All 9 flagged sheets are genuine leaf sheets with zero blocks:
- Syneidisi children: Logica, Instinto, Social, Memoria, Recelo
- Location children: Cryobay, Garden
- NPC children: ARIA, Techdroid

**Issue:** This is a design question, not a bug. These sheets exist as placeholders the user hasn't filled yet. The count (9) may feel noisy. Consider making this info-severity (already is) and perhaps collapsing to show only the count, not flagging it as a "warning."

### 2. Disconnected Nodes — CORRECT but reveals a BIGGER BUG

**What it reports:** "Flow 'Flow 1' has 1 disconnected node(s)"

**Reality:** The `flow_connections` table is **completely empty** — zero rows. Despite the user seeing connections in the UI (Entry → Dialogue → Exit), **no connections were ever persisted to the database**.

**Root cause:** Connections are only rendered client-side in the flow canvas but were never saved via `connection_created` events, OR they were lost during some operation. This is NOT a dashboard bug — it's a data persistence bug in the flow editor.

**Dashboard code quality issue:** The `connected_node_ids` subquery doesn't filter by `is_nil(sn.deleted_at)` on joined nodes. Should add node soft-delete checks for robustness (minor).

### 3. Word Count — SEVERELY UNDERCOUNTING

**What it reports:** 3 words

**What it captures:** Only `data->>'text'` from dialogue nodes → "Un texto aqui" = 3 words

**What it MISSES (game-visible text):**

| Source | Priority | Current DB Words | Status |
|--------|----------|-----------------|--------|
| Dialogue `text` (HTML) | — | 3 | Counted |
| Dialogue response `text` | HIGH | 2 ("Response 1", "Response 2") | **MISSING** |
| Dialogue `menu_text` | HIGH | 0 (empty) | **MISSING** |
| Dialogue `stage_directions` | MEDIUM | 0 (empty) | **MISSING** |
| Slug line `description` | MEDIUM | 0 (no nodes yet) | **MISSING** |
| Slug line `sub_location` | LOW | 0 (no nodes yet) | **MISSING** |
| Screenplay element `content` | MEDIUM | 0 (empty) | **MISSING** |
| Sheet names (leaf only) | DEBATABLE | ~15 words | **MISSING** |
| Table row names | DEBATABLE | ~20 words | **MISSING** |

**What should NOT be counted (system data):**
- `technical_id`, `localization_id` — auto-generated IDs
- `speaker_sheet_id`, `audio_asset_id` — integer references
- `shortcut`, `variable_name` — internal identifiers
- Condition rules, instruction assignments — logic, not player text
- `int_ext`, `exit_mode`, `outcome_color` — configuration enums
- Flow/scene names — organizational, not shown to players

---

## Recommended Fixes

### Fix 1: Word Count (HIGH priority)

Expand `count_total_words/1` to extract ALL game-visible text from dialogue nodes:
- `data->>'text'` (main dialogue line)
- `data->>'menu_text'` (abbreviated choice text)
- `data->>'stage_directions'` (directions like "[sighs]")
- `data->'responses'` array → each element's `->>'text'` (player choice text)

Add slug_line text:
- `data->>'description'` from slug_line nodes

**Decision needed from user:** Should sheet names and table row names count as words? They ARE game-visible (character names, stat names) but they're entity names, not "authored narrative text."

### Fix 2: Disconnected Nodes Query (LOW priority)

Add soft-delete filtering on joined nodes in `connected_node_ids` subquery for robustness. The current "false positive" is actually caused by missing connection data (a separate flow editor bug), not a dashboard query bug.

### Fix 3: Recent Activity (LOW priority)

Add screenplays to the union query in `recent_activity/2`.

### Fix 4: Speakers Query (LOW priority)

Add `is_nil(s.deleted_at)` filter on the sheets left_join to avoid showing deleted speakers.

---

## Flow Connections Persistence Bug (SEPARATE from dashboard)

The `flow_connections` table has **zero rows**. This is not a dashboard issue — it's a flow editor data persistence issue that needs separate investigation. The flow canvas renders connections client-side, but `connection_created` / `connection_removed` events may not be firing or persisting correctly.

This should be tracked as a separate bug, not part of the dashboard fix.
