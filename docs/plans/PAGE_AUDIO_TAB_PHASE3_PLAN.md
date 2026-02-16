# Phase 3: Page Audio Tab — Implementation Plan

> **Objective**: Add an "Audio" tab to Sheet pages that shows all dialogue nodes where this sheet is the speaker, their associated audio assets, and lets users upload/link voice assets directly.

---

## Current State

- **AudioPicker** LiveComponent exists (Phase 1) with select, upload, preview, unlink.
- **Flow Editor** already uses AudioPicker (Phase 2) — dialogue nodes store `speaker_sheet_id` and `audio_asset_id` in JSONB `data`.
- **Sheet `show.ex`** has 3 tabs: Content, References, History. Tabs are LiveComponents rendered with `:if` guards and switched via `"switch_tab"` event (guard: `when tab in ["content", "references", "history"]`).
- **No existing query** to find dialogue nodes by speaker or audio usage.

---

## Task 1: Add `list_dialogue_nodes_by_speaker/2` query

**Goal**: Add a Flows context function that returns all dialogue nodes where `data->>'speaker_sheet_id'` matches a given sheet, joined with flow info.

**What it does**:
- Query `flow_nodes` WHERE `type = "dialogue"`, `deleted_at IS NULL`, `data->>'speaker_sheet_id' = sheet_id`, scoped to project via `flows.project_id`.
- Returns nodes preloaded with their flow (for navigation links and display).

**Files**:

| File                              | Action                                 |
|-----------------------------------|----------------------------------------|
| `lib/storyarn/flows/node_crud.ex` | Add `list_dialogue_nodes_by_speaker/2` |
| `lib/storyarn/flows.ex`           | Add `defdelegate`                      |
| `test/storyarn/flows_test.exs`    | Add tests                              |

**Tests**:
- Returns dialogue nodes with matching `speaker_sheet_id`
- Excludes soft-deleted nodes (`deleted_at` set)
- Excludes nodes from other projects
- Excludes non-dialogue node types even if they have the field
- Returns empty list when no matches
- Preloads flow association (flow.name, flow.id accessible)

---

## Task 2: Create AudioTab LiveComponent

**Goal**: Build the "Audio" tab component showing a speaker's dialogue appearances with audio status.

**What it renders**:
- Section header: "Voice Lines" with count
- For each dialogue node where this sheet is speaker:
  - Flow name (as link to flow editor)
  - Node text preview (truncated)
  - Audio status: attached audio filename or "No audio" badge
  - Audio player when audio is attached
- Empty state when sheet is not used as speaker anywhere

**Data flow**:
- Receives `project`, `workspace`, `sheet` from parent
- Calls `Flows.list_dialogue_nodes_by_speaker(project.id, sheet.id)` on mount/update
- For nodes with `audio_asset_id`, fetches the asset via `Assets.get_asset/2`

**Files**:

| File                                                       | Action |
|------------------------------------------------------------|--------|
| `lib/storyarn_web/live/sheet_live/components/audio_tab.ex` | CREATE |
| `test/storyarn_web/live/sheet_live/audio_tab_test.exs`     | CREATE |

**Tests**:
- Renders empty state when no dialogue nodes reference this sheet as speaker
- Lists dialogue nodes grouped by flow
- Shows flow name for each node
- Shows node text preview (truncated)
- Shows "No audio" badge when `audio_asset_id` is nil
- Shows audio filename and player when `audio_asset_id` is set
- Flow name links to the correct flow editor URL

---

## Task 3: Wire AudioTab into Sheet show.ex

**Goal**: Add the "Audio" tab button and mount the AudioTab component.

**Changes**:
- Add "audio" to the `switch_tab` guard: `when tab in ["content", "references", "history", "audio"]`
- Add tab button with `volume-2` icon
- Render `<.live_component module={AudioTab}>` when `@current_tab == "audio"`
- Pass `project`, `workspace`, `sheet`, `can_edit` to AudioTab

**Files**:

| File                                              | Action                                   |
|---------------------------------------------------|------------------------------------------|
| `lib/storyarn_web/live/sheet_live/show.ex`        | MODIFY                                   |
| `test/storyarn_web/live/sheet_live/show_test.exs` | ADD tests (if exists) or verify manually |

**Tests**:
- Audio tab button renders in the tab bar
- Clicking Audio tab switches to it
- AudioTab component renders when tab is active
- Tab button shows correct icon

---

## File Summary

| # | File                                                       | Action | Task   |
|---|------------------------------------------------------------|--------|--------|
| 1 | `lib/storyarn/flows/node_crud.ex`                          | MODIFY | 1      |
| 2 | `lib/storyarn/flows.ex`                                    | MODIFY | 1      |
| 3 | `test/storyarn/flows_test.exs`                             | MODIFY | 1      |
| 4 | `lib/storyarn_web/live/sheet_live/components/audio_tab.ex` | CREATE | 2      |
| 5 | `test/storyarn_web/live/sheet_live/audio_tab_test.exs`     | CREATE | 2      |
| 6 | `lib/storyarn_web/live/sheet_live/show.ex`                 | MODIFY | 3      |

---

## Verification per Task

1. **Task 1**: `mix test test/storyarn/flows_test.exs` + `mix credo --strict`
2. **Task 2**: `mix test test/storyarn_web/live/sheet_live/audio_tab_test.exs` + `mix credo --strict`
3. **Task 3**: `mix test` (full suite) + `mix credo --strict`
