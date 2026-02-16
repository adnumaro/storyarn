# Assets System Implementation Plan

> **Objective**: Create a flexible asset management system where users can upload and link assets from multiple places (Assets tool, Page, Flow editor) with full bidirectional visibility.

## Current State

### What exists:
- `Storyarn.Assets` context with full CRUD operations
- `Storyarn.Assets.Asset` schema (filename, content_type, size, key, url, metadata, project_id, uploaded_by_id)
- Storage abstraction (local dev, R2 production)
- Upload helpers for avatar/banner in Pages
- Flow editor selects from existing audio assets (no upload capability)

### What's missing:
- Assets tool/page (no UI to manage assets)
- Audio tab in Pages
- Upload capability in Flow editor
- Bidirectional linking (asset ↔ dialogue nodes, asset ↔ pages)

---

## Architecture Design

### Data Model Changes

```
┌─────────────────────────────────────────────────────────────────┐
│                         Asset                                    │
├─────────────────────────────────────────────────────────────────┤
│ id, filename, content_type, size, key, url, metadata            │
│ project_id, uploaded_by_id                                       │
│                                                                  │
│ NEW: Computed "usages" from reverse lookups:                    │
│   - flow_nodes where data->>'audio_asset_id' = asset.id         │
│   - pages where avatar_asset_id = asset.id                      │
│   - pages where banner_asset_id = asset.id                      │
└─────────────────────────────────────────────────────────────────┘
```

No schema changes needed - we query usages dynamically.

### Component Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Shared Components                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  AudioPicker (LiveComponent)                                     │
│  ├─ Used in: Flow Editor, Page Audio Tab                        │
│  ├─ Features:                                                    │
│  │   - Select from existing audio assets                        │
│  │   - Upload new audio (creates asset + links)                 │
│  │   - Audio preview player                                      │
│  │   - Remove link (unlink, not delete)                         │
│  └─ Props: project_id, selected_asset_id, on_select, on_upload  │
│                                                                  │
│  AssetUploader (LiveComponent)                                   │
│  ├─ Used in: Assets Tool (standalone upload)                    │
│  ├─ Features:                                                    │
│  │   - Drag & drop upload                                        │
│  │   - Multiple file support                                     │
│  │   - Progress indicator                                        │
│  └─ Props: project_id, allowed_types, on_upload                 │
│                                                                  │
│  AssetGrid (Function Component)                                  │
│  ├─ Used in: Assets Tool, Page Audio Tab                        │
│  ├─ Features:                                                    │
│  │   - Grid/list view of assets                                  │
│  │   - Filtering by type                                         │
│  │   - Search                                                    │
│  └─ Props: assets, on_select, on_delete, selected_id            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Implementation Phases

### Phase 1: Shared Audio Picker Component
**Priority: High | Effort: Medium**

Create a reusable LiveComponent for selecting/uploading audio.

#### 1.1 AudioPicker LiveComponent

```elixir
# lib/storyarn_web/components/audio_picker.ex
defmodule StoryarnWeb.Components.AudioPicker do
  use StoryarnWeb, :live_component

  # Props:
  # - project: Project struct
  # - selected_asset_id: current selection (or nil)
  # - current_user: for upload attribution
  # - on_select: callback when asset selected (atom for parent event)
  # - on_upload: callback when new asset uploaded (atom for parent event)
  # - context: :flow | :page (affects display)
end
```

**UI Layout:**
```
┌─────────────────────────────────────────────────────┐
│ Audio                                            ▼  │
├─────────────────────────────────────────────────────┤
│                                                     │
│  ┌─────────────────────────────────────────────┐   │
│  │ [Select audio...              ▼]             │   │
│  │ ──────────── OR ────────────                 │   │
│  │ [📁 Upload new audio file]                   │   │
│  └─────────────────────────────────────────────┘   │
│                                                     │
│  ┌─────────────────────────────────────────────┐   │
│  │ 🎵 merchant_greeting.mp3                     │   │
│  │ ▶ ━━━━━━━━━━○━━━━━━━ 0:12 / 0:45            │   │
│  │                                   [✕ Remove] │   │
│  └─────────────────────────────────────────────┘   │
│                                                     │
└─────────────────────────────────────────────────────┘
```

#### 1.2 Files Created/Modified

| File | Action | Description |
|------|--------|-------------|
| `lib/storyarn_web/components/audio_picker.ex` | CREATED | LiveComponent for audio selection/upload |
| `assets/js/hooks/audio_upload.js` | CREATED | JS hook for file selection |

> Note: `audio_helpers.ex` was not created as a separate file. Upload logic lives inline in AudioPicker and each consumer component.

#### 1.3 Tasks

- [x] Create AudioPicker LiveComponent with select dropdown
- [x] Add upload button with file input (hidden, triggered by button)
- [x] Implement upload logic (reuse pattern from AssetHelpers)
- [x] Add audio preview player when asset selected
- [x] Add "Remove" button to unlink (not delete) asset
- [x] Add loading state during upload

---

### Phase 2: Update Flow Editor
**Priority: High | Effort: Low**

Replace current audio select with AudioPicker component.

#### 2.1 Changes to Flow Editor

```elixir
# In properties_panels.ex, replace the Audio section with:
<.live_component
  module={AudioPicker}
  id={"audio-picker-#{@node.id}"}
  project={@project}
  selected_asset_id={@form[:audio_asset_id].value}
  current_user={@current_user}
  context={:flow}
/>
```

#### 2.2 Files Modified

| File | Action | Description |
|------|--------|-------------|
| `lib/storyarn_web/live/flow_live/components/properties_panels.ex` | MODIFIED | Replaced audio section with AudioPicker |
| `lib/storyarn_web/live/flow_live/show.ex` | MODIFIED | Added handlers for audio_selected, audio_uploaded |

#### 2.3 Tasks

- [x] Pass project to properties_panels component
- [x] Replace audio `<details>` section with AudioPicker
- [x] Add `handle_info` for audio selection/upload events
- [x] Update node data when audio changes
- [x] Test upload + select workflows

---

### Phase 3: Page Audio Tab
**Priority: High | Effort: Medium**

Add "Audio" tab to Pages showing character voice assets.

#### 3.1 Audio Tab Design

```
┌─────────────────────────────────────────────────────────────────┐
│  [Content]  [References]  [Audio]                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Voice Assets for "Old Merchant"                                 │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ 🎵 merchant_greeting.mp3                                     ││
│  │    Used in: intro_flow → node "merchant_intro_1"            ││
│  │    ▶ ━━━━━━━━━━○━━━━━━━ 0:12 / 0:45                         ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ 🎵 merchant_farewell.mp3                                     ││
│  │    Used in: ending_flow → node "merchant_goodbye_1"          ││
│  │    ▶ ━━━━━━━━━━○━━━━━━━ 0:08 / 0:30                         ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
│  ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐│
│  │ [+ Add voice asset]                                         ││
│  └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘│
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

#### 3.2 Query: Assets used by a Page (as speaker)

```elixir
# In Assets context, add:
def list_assets_for_speaker(project_id, sheet_id) do
  # Find all audio assets used in dialogue nodes where speaker_sheet_id = sheet_id
  from(a in Asset,
    join: n in "flow_nodes",
    on: fragment("(?->>'audio_asset_id')::integer = ?", n.data, a.id),
    join: f in "flows",
    on: n.flow_id == f.id,
    where: a.project_id == ^project_id,
    where: fragment("(?->>'speaker_sheet_id')::integer = ?", n.data, ^sheet_id),
    where: ilike(a.content_type, "audio/%"),
    select: %{
      asset: a,
      flow_id: f.id,
      flow_name: f.name,
      flow_shortcut: f.shortcut,
      node_id: n.id,
      technical_id: fragment("?->>'technical_id'", n.data)
    }
  )
  |> Repo.all()
end
```

#### 3.3 Files Created/Modified

| File | Action | Description |
|------|--------|-------------|
| `lib/storyarn_web/live/sheet_live/components/audio_tab.ex` | CREATED | New tab component |
| `lib/storyarn_web/live/sheet_live/show.ex` | MODIFIED | Added Audio tab |
| `lib/storyarn/flows.ex` | MODIFIED | Added `list_dialogue_nodes_by_speaker/2` |

> Note: `list_assets_for_speaker/2` was not added to Assets context. Instead, AudioTab queries dialogue nodes directly via `Flows.list_dialogue_nodes_by_speaker/2` and resolves audio assets inline.

#### 3.4 Tasks

- [x] Query dialogue nodes by speaker via Flows context
- [x] Create AudioTab LiveComponent
- [x] Display voice lines with text preview and audio status
- [x] Add inline audio upload and select per voice line
- [x] Add deep-linking to flow editor nodes
- [x] Add "Audio" tab button in Sheet show.ex
- [x] Wire up tab switching

---

### Phase 4: Assets Tool
**Priority: Medium | Effort: High**

Create dedicated Assets management page.

#### 4.1 Assets Tool Design

```
┌─────────────────────────────────────────────────────────────────┐
│  Assets                                              [+ Upload]  │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  [All] [Images] [Audio] [Documents]     🔍 Search...            │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────────┤
│  │                                                               │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐         │
│  │  │  🖼️     │  │  🖼️     │  │  🎵     │  │  🎵     │         │
│  │  │         │  │         │  │         │  │         │         │
│  │  │ img.png │  │hero.jpg │  │ vo_01   │  │ vo_02   │         │
│  │  │ 1.2 MB  │  │ 800 KB  │  │ 120 KB  │  │ 95 KB   │         │
│  │  └─────────┘  └─────────┘  └─────────┘  └─────────┘         │
│  │                                                               │
│  └──────────────────────────────────────────────────────────────┤
│                                                                  │
│  ─────────────────── Asset Details ─────────────────────────────│
│                                                                  │
│  🎵 merchant_greeting.mp3                                        │
│  Type: audio/mpeg | Size: 120 KB | Uploaded: 2 days ago         │
│                                                                  │
│  ▶ ━━━━━━━━━━━━━━━━━━━━○━━━━━━━━━━━━ 0:12 / 0:45               │
│                                                                  │
│  Used in:                                                        │
│  • intro_flow → Old Merchant (merchant_intro_1)                  │
│  • main_quest → Old Merchant (merchant_quest_3)                  │
│                                                                  │
│  [🗑️ Delete]                                                     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

#### 4.2 Route Structure

```elixir
# In router.ex, add under project scope:
live "/assets", AssetsLive.Index, :index
```

#### 4.3 Query: Asset usages

```elixir
# In Assets context, add:
def get_asset_usages(asset_id) do
  %{
    dialogue_nodes: list_dialogue_nodes_using_asset(asset_id),
    page_avatars: list_pages_using_as_avatar(asset_id),
    page_banners: list_pages_using_as_banner(asset_id)
  }
end

defp list_dialogue_nodes_using_asset(asset_id) do
  from(n in "flow_nodes",
    join: f in "flows",
    on: n.flow_id == f.id,
    join: s in "sheets",
    on: fragment("(?->>'speaker_sheet_id')::integer = ?", n.data, s.id),
    where: fragment("(?->>'audio_asset_id')::integer = ?", n.data, ^asset_id),
    select: %{
      flow_id: f.id,
      flow_name: f.name,
      node_id: n.id,
      speaker_name: s.name,
      technical_id: fragment("?->>'technical_id'", n.data)
    }
  )
  |> Repo.all()
end
```

#### 4.4 Files Created

| File | Action | Description |
|------|--------|-------------|
| `lib/storyarn_web/live/asset_live/index.ex` | CREATED | Main assets page (grid, detail panel, upload, delete — all in one LiveView) |
| `assets/js/hooks/asset_upload.js` | CREATED | JS hook for asset file selection |

> Note: Separate `asset_grid.ex`, `asset_details.ex`, and `asset_uploader.ex` components were not created. The grid, detail panel, and upload logic are implemented as private function components and helpers within `index.ex` for simplicity.

#### 4.5 Tasks

- [x] Create route for assets page
- [x] Create AssetLive.Index with grid layout
- [x] Implement type filtering (All, Images, Audio)
- [x] Implement search
- [x] Create detail panel showing usages (flow nodes, sheet avatars, sheet banners)
- [x] Implement upload via JS hook (base64)
- [x] Add delete with confirmation (warn if asset is in use)
- [x] Add sidebar entry in project navigation

---

## File Summary

### New Files (4)

```
lib/storyarn_web/components/audio_picker.ex              # Shared audio select + upload
lib/storyarn_web/live/sheet_live/components/audio_tab.ex # Sheet audio tab (voice lines)
lib/storyarn_web/live/asset_live/index.ex                # Assets tool (grid, detail, upload, delete)
assets/js/hooks/audio_upload.js                          # JS hook for audio file selection
```

### Modified Files (5)

```
lib/storyarn/assets.ex                                         # Usage queries, sanitize_filename (public)
lib/storyarn_web/live/flow_live/components/properties_panels.ex # Use AudioPicker
lib/storyarn_web/live/flow_live/show.ex                        # Handle audio events
lib/storyarn_web/live/sheet_live/show.ex                       # Add Audio tab
lib/storyarn_web/router.ex                                     # Add assets route
```

---

## Implementation Order

```
Phase 1: AudioPicker Component
    │
    ├─── 1.1 Create base component with select
    ├─── 1.2 Add upload capability
    ├─── 1.3 Add preview player
    └─── 1.4 Add remove (unlink) button
    │
    ▼
Phase 2: Flow Editor Update
    │
    ├─── 2.1 Replace audio section with AudioPicker
    └─── 2.2 Test full workflow
    │
    ▼
Phase 3: Page Audio Tab
    │
    ├─── 3.1 Add usage query to Assets context
    ├─── 3.2 Create AudioTab component
    └─── 3.3 Wire up in Page show
    │
    ▼
Phase 4: Assets Tool
    │
    ├─── 4.1 Create index page with grid
    ├─── 4.2 Add filtering and search
    ├─── 4.3 Add detail panel with usages
    └─── 4.4 Add standalone uploader
```

---

## Testing Checklist

### Phase 1: AudioPicker
- [x] Can select existing audio from dropdown
- [x] Can upload new audio file
- [x] Upload creates asset in database
- [x] Upload stores file in storage (local/R2)
- [x] Preview player shows for selected audio
- [x] Remove button unlinks asset (doesn't delete)
- [x] Loading state shows during upload

### Phase 2: Flow Editor
- [x] AudioPicker renders in properties panel
- [x] Selecting audio updates node data
- [x] Uploading audio creates asset + updates node
- [x] Audio indicator shows on canvas node
- [x] Existing dialogues with audio still work

### Phase 3: Sheet Audio Tab
- [x] Tab appears in sheet view
- [x] Shows all voice lines where sheet is speaker
- [x] Shows text preview and audio status per line
- [x] Can upload/select audio inline per voice line
- [x] Deep-links to flow editor nodes

### Phase 4: Assets Tool
- [x] Page loads and shows all project assets
- [x] Type filters work (All, Images, Audio)
- [x] Search filters by filename
- [x] Selecting asset shows detail panel
- [x] Detail panel shows all usages
- [x] Can upload new asset
- [x] Can delete asset (with warning if in use)
- [x] Deleting removes from storage

---

## Future Enhancements (Out of Scope)

- Bulk upload
- Drag & drop reordering
- Asset folders/organization
- Asset versioning
- Waveform visualization for audio
- Duration metadata extraction
- Automatic transcription
