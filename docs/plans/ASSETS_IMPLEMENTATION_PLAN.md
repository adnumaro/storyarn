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

#### 1.2 Files to Create/Modify

| File | Action | Description |
|------|--------|-------------|
| `lib/storyarn_web/components/audio_picker.ex` | CREATE | LiveComponent for audio selection/upload |
| `lib/storyarn_web/components/audio_helpers.ex` | CREATE | Shared audio upload logic |
| `assets/js/hooks/audio_upload.js` | CREATE | JS hook for file selection |

#### 1.3 Tasks

- [ ] Create AudioPicker LiveComponent with select dropdown
- [ ] Add upload button with file input (hidden, triggered by button)
- [ ] Implement upload logic (reuse pattern from AssetHelpers)
- [ ] Add audio preview player when asset selected
- [ ] Add "Remove" button to unlink (not delete) asset
- [ ] Add loading state during upload

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

#### 2.2 Files to Modify

| File | Action | Description |
|------|--------|-------------|
| `lib/storyarn_web/live/flow_live/components/properties_panels.ex` | MODIFY | Replace audio section with AudioPicker |
| `lib/storyarn_web/live/flow_live/show.ex` | MODIFY | Add handlers for audio_selected, audio_uploaded |

#### 2.3 Tasks

- [ ] Pass project to properties_panels component
- [ ] Replace audio `<details>` section with AudioPicker
- [ ] Add `handle_info` for audio selection/upload events
- [ ] Update node data when audio changes
- [ ] Test upload + select workflows

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
def list_assets_for_speaker(project_id, page_id) do
  # Find all audio assets used in dialogue nodes where speaker_page_id = page_id
  from(a in Asset,
    join: n in "flow_nodes",
    on: fragment("(?->>'audio_asset_id')::integer = ?", n.data, a.id),
    join: f in "flows",
    on: n.flow_id == f.id,
    where: a.project_id == ^project_id,
    where: fragment("(?->>'speaker_page_id')::integer = ?", n.data, ^page_id),
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

#### 3.3 Files to Create/Modify

| File | Action | Description |
|------|--------|-------------|
| `lib/storyarn_web/live/page_live/components/audio_tab.ex` | CREATE | New tab component |
| `lib/storyarn_web/live/page_live/show.ex` | MODIFY | Add Audio tab |
| `lib/storyarn/assets.ex` | MODIFY | Add list_assets_for_speaker/2 |

#### 3.4 Tasks

- [ ] Add `list_assets_for_speaker/2` to Assets context
- [ ] Create AudioTab LiveComponent
- [ ] Display assets with usage info (which flow, which node)
- [ ] Add AudioPicker for uploading new voice assets
- [ ] Add "Audio" tab button in Page show.ex
- [ ] Wire up tab switching

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
    join: p in "pages",
    on: fragment("(?->>'speaker_page_id')::integer = ?", n.data, p.id),
    where: fragment("(?->>'audio_asset_id')::integer = ?", n.data, ^asset_id),
    select: %{
      flow_id: f.id,
      flow_name: f.name,
      node_id: n.id,
      speaker_name: p.name,
      technical_id: fragment("?->>'technical_id'", n.data)
    }
  )
  |> Repo.all()
end
```

#### 4.4 Files to Create

| File | Action | Description |
|------|--------|-------------|
| `lib/storyarn_web/live/assets_live/index.ex` | CREATE | Main assets page |
| `lib/storyarn_web/live/assets_live/components/asset_grid.ex` | CREATE | Grid/list view component |
| `lib/storyarn_web/live/assets_live/components/asset_details.ex` | CREATE | Detail panel component |
| `lib/storyarn_web/live/assets_live/components/asset_uploader.ex` | CREATE | Upload component (no linking) |

#### 4.5 Tasks

- [ ] Create route for assets page
- [ ] Create AssetsLive.Index with grid layout
- [ ] Implement type filtering (All, Images, Audio, Documents)
- [ ] Implement search
- [ ] Create detail panel showing usages
- [ ] Create standalone uploader (upload only, no linking)
- [ ] Add delete with confirmation (warn if asset is in use)
- [ ] Add sidebar entry in project navigation

---

## File Summary

### New Files (10)

```
lib/storyarn_web/components/
├── audio_picker.ex              # Shared audio select + upload
└── audio_helpers.ex             # Upload logic

lib/storyarn_web/live/page_live/components/
└── audio_tab.ex                 # Page audio tab

lib/storyarn_web/live/assets_live/
├── index.ex                     # Assets tool main page
└── components/
    ├── asset_grid.ex            # Grid/list view
    ├── asset_details.ex         # Detail panel
    └── asset_uploader.ex        # Standalone uploader

assets/js/hooks/
└── audio_upload.js              # File selection hook
```

### Modified Files (5)

```
lib/storyarn/assets.ex                                    # Add usage queries
lib/storyarn_web/live/flow_live/components/properties_panels.ex  # Use AudioPicker
lib/storyarn_web/live/flow_live/show.ex                   # Handle audio events
lib/storyarn_web/live/page_live/show.ex                   # Add Audio tab
lib/storyarn_web/router.ex                                # Add assets route
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
- [ ] Can select existing audio from dropdown
- [ ] Can upload new audio file
- [ ] Upload creates asset in database
- [ ] Upload stores file in storage (local/R2)
- [ ] Preview player shows for selected audio
- [ ] Remove button unlinks asset (doesn't delete)
- [ ] Loading state shows during upload

### Phase 2: Flow Editor
- [ ] AudioPicker renders in properties panel
- [ ] Selecting audio updates node data
- [ ] Uploading audio creates asset + updates node
- [ ] Audio indicator shows on canvas node
- [ ] Existing dialogues with audio still work

### Phase 3: Page Audio Tab
- [ ] Tab appears in page view
- [ ] Shows all audio assets where page is speaker
- [ ] Shows which flow/node each asset is used in
- [ ] Can upload new voice asset from tab
- [ ] Clicking flow name navigates to flow

### Phase 4: Assets Tool
- [ ] Page loads and shows all project assets
- [ ] Type filters work (All, Images, Audio, Documents)
- [ ] Search filters by filename
- [ ] Selecting asset shows detail panel
- [ ] Detail panel shows all usages
- [ ] Can upload new asset
- [ ] Can delete asset (with warning if in use)
- [ ] Deleting removes from storage

---

## Future Enhancements (Out of Scope)

- Bulk upload
- Drag & drop reordering
- Asset folders/organization
- Asset versioning
- Waveform visualization for audio
- Duration metadata extraction
- Automatic transcription
