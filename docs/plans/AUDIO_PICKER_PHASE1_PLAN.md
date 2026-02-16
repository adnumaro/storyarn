# Phase 1: Audio Picker Component + Flow Editor Integration

> **Source:** `docs/plans/ASSETS_IMPLEMENTATION_PLAN.md` — Phases 1 & 2
> **Scope:** Create reusable AudioPicker LiveComponent and integrate into Flow Editor dialogue sidebar

---

## Task 1: AudioPicker LiveComponent — Select, Preview & Unlink

**New file:** `lib/storyarn_web/components/audio_picker.ex`

### What it does

- LiveComponent that loads audio assets via `Assets.list_assets(project_id, content_type: "audio/")`
- Dropdown to select from existing audio assets
- Native `<audio controls>` preview player when an asset is selected
- "Remove" button to unlink (clears selection, does NOT delete asset)
- Sends `{:audio_picker, :selected, asset_id_or_nil}` to parent via `send(self(), ...)`

### Props

| Prop | Type | Required | Description |
|------|------|----------|-------------|
| `id` | string | yes | Component DOM id |
| `project` | Project | yes | Project struct (for loading assets) |
| `selected_asset_id` | integer/nil | no | Currently selected audio asset id |
| `can_edit` | boolean | no | Enables/disables controls (default: false) |

### UI

```
┌─────────────────────────────────────────────────┐
│ 🔊 Audio                                        │
├─────────────────────────────────────────────────┤
│                                                  │
│  [Select audio...                          ▼]   │
│                                                  │
│  ┌─────────────────────────────────────────────┐ │
│  │ 🎵 merchant_greeting.mp3                    │ │
│  │ ▶ ━━━━━━━━━━○━━━━━━━ 0:12 / 0:45           │ │
│  │                                  [✕ Remove] │ │
│  └─────────────────────────────────────────────┘ │
│                                                  │
└─────────────────────────────────────────────────┘
```

### Tests

- Renders with no selection (shows dropdown + help text)
- Renders with pre-selected audio (shows player + filename)
- Lists only audio assets (not images/pdfs)
- Selection sends event to parent
- Unlink sends event with `nil`
- Read-only mode disables controls

### Value

Reusable component ready to be plugged into any LiveView that needs audio selection.

---

## Task 2: Add Upload to AudioPicker

**Modifies:** `lib/storyarn_web/components/audio_picker.ex`
**New file:** `assets/js/hooks/audio_upload.js`

### What it does

- Adds "Upload audio" button + hidden file input inside AudioPicker
- JS hook (`AudioUpload`) validates type (`audio/*`) and size (max 20MB), reads as base64
- Server-side handler decodes base64, calls `Storage.upload/3` + `Assets.create_asset/3`
- Auto-selects the newly uploaded asset
- Loading spinner during upload

### Why base64 (like avatar/banner) instead of LiveView uploads?

- Simpler: no `allow_upload` coordination with parent LiveView
- Consistent with existing upload hooks in codebase (avatar_upload.js, banner_upload.js)
- Audio files for dialogue are typically small (voice-over < 5MB)
- 20MB limit is generous for dialogue audio

### Tests

- Upload creates asset in DB with correct attributes
- Upload stores file via Storage adapter
- Newly uploaded asset auto-selects
- Validation: rejects non-audio files (server-side)
- Audio assets list refreshes after upload

### Value

Component now supports both selecting existing and uploading new audio.

---

## Task 3: Integrate AudioPicker into Flow Editor Dialogue Sidebar

**Modifies:**
- `lib/storyarn_web/live/flow_live/nodes/dialogue/config_sidebar.ex`
- `lib/storyarn_web/live/flow_live/components/properties_panels.ex`
- `lib/storyarn_web/live/flow_live/show.ex`

### What it does

- Replace the current `<details>` audio section (lines 113–152 in `config_sidebar.ex`) with `<.live_component module={AudioPicker} .../>`
- `properties_panels.ex`: pass `project` and `current_user` down to dialogue sidebar
- `show.ex`: handle `{:audio_picker, :selected, asset_id}` → update node data (`audio_asset_id`)
- Remove `audio_assets` assign from show.ex (AudioPicker loads its own data internally)
- Clean up `audio_assets` attr from all config_sidebar modules that receive but never use it

### Tests

- AudioPicker renders inside dialogue sidebar
- Selecting audio updates node's `audio_asset_id` in DB
- Uploading audio creates asset + updates node data
- Unlinking audio clears `audio_asset_id`
- Audio indicator icon still shows on canvas node
- Existing dialogue nodes with audio still display correctly

### Value

End-to-end: users can select, upload, preview, and unlink audio directly from the dialogue node sidebar.

---

## Execution Protocol (per task)

1. Implement code
2. Write tests
3. Run `mix credo` — fix all issues
4. Run `mix test` — all tests pass
5. Ask user before proceeding to next task

## Files Summary

### New Files (2)

| File | Task | Description |
|------|------|-------------|
| `lib/storyarn_web/components/audio_picker.ex` | 1 | AudioPicker LiveComponent |
| `assets/js/hooks/audio_upload.js` | 2 | JS hook for audio file selection |

### Modified Files

| File | Task | Description |
|------|------|-------------|
| `lib/storyarn_web/live/flow_live/nodes/dialogue/config_sidebar.ex` | 3 | Replace audio `<details>` with AudioPicker |
| `lib/storyarn_web/live/flow_live/components/properties_panels.ex` | 3 | Pass project + current_user to sidebar |
| `lib/storyarn_web/live/flow_live/show.ex` | 3 | Handle audio_picker events, remove audio_assets assign |
| `assets/js/app.js` | 2 | Register AudioUpload hook |

### Cleanup (Task 3)

Remove unused `audio_assets` attr from config_sidebar modules that don't use it:
- `nodes/hub/config_sidebar.ex`
- `nodes/scene/config_sidebar.ex`
- `nodes/subflow/config_sidebar.ex`
- `nodes/exit/config_sidebar.ex`
- `nodes/jump/config_sidebar.ex`
- `nodes/instruction/config_sidebar.ex`
- `nodes/entry/config_sidebar.ex`
- `nodes/condition/config_sidebar.ex`
