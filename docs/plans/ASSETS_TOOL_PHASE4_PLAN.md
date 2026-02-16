# Phase 4: Assets Tool — Implementation Plan

> **Objective**: Create a dedicated Assets management page within each project for browsing, uploading, filtering, searching, inspecting usage, and deleting assets.

---

## Current State

- **Assets context** (`assets.ex`) has full CRUD, `list_assets/2` with content_type/search/pagination, `count_assets_by_type/1`, `total_storage_size/1`.
- **Storage module** handles upload/delete with local (dev) and R2 (prod) backends.
- **Asset schema** has `filename`, `content_type`, `size`, `key`, `url`, `metadata`. Helper methods: `Asset.image?/1`, `Asset.audio?/1`.
- **AudioPicker** and **AudioUpload** hook exist for audio uploads.
- **No asset usage query** — nothing queries where an asset is referenced (flow nodes JSONB, sheet avatar/banner FKs).
- **No Assets route or sidebar entry** in the project.

---

## Task 1: Route, sidebar entry, and empty Assets page

**Goal**: Create the minimal Assets LiveView with route and sidebar navigation so the page is accessible.

**Changes**:
- Add route: `live "/assets", AssetLive.Index, :index` in the project scope
- Add sidebar entry: `<.tree_link label="Assets" icon="image" ...>` + `assets_page?/3` helper
- Create `AssetLive.Index` with `Layouts.project` wrapper, header, and empty state
- Mount loads project/workspace/membership (follows `flow_live/index.ex` pattern)

**Files**:
| File | Action |
|------|--------|
| `lib/storyarn_web/router.ex` | Add route |
| `lib/storyarn_web/components/project_sidebar.ex` | Add link + helper |
| `lib/storyarn_web/live/asset_live/index.ex` | CREATE — empty page |
| `test/storyarn_web/live/asset_live/index_test.exs` | CREATE — mount + access tests |

**Tests**:
- Page renders with "Assets" header
- Shows empty state when no assets exist
- Sidebar has "Assets" link
- Unauthorized user gets redirect

---

## Task 2: Asset grid with type filtering

**Goal**: Display assets in a grid/list with type filter tabs (All, Images, Audio).

**Changes**:
- Add `@filter` assign (default `"all"`, options: `"all"`, `"image"`, `"audio"`)
- Render filter tabs at the top
- `handle_event("filter_assets", %{"type" => type})` reloads assets with content_type filter
- Asset card shows: thumbnail/icon, filename, size, content type badge
- Different visual for images (thumbnail via `asset.url`) vs audio (icon + filename)

**Files**:
| File | Action |
|------|--------|
| `lib/storyarn_web/live/asset_live/index.ex` | Add grid + filters |
| `test/storyarn_web/live/asset_live/index_test.exs` | Add filter tests |

**Tests**:
- Lists all assets with filename and size
- Filter "image" shows only images
- Filter "audio" shows only audio
- Filter "all" shows everything
- Shows type badge per asset
- Shows asset count per filter tab

---

## Task 3: Search

**Goal**: Add a search input that filters assets by filename.

**Changes**:
- Add `@search` assign (default `""`)
- Add search input with `phx-change="search_assets"` and debounce
- Handler updates `@search` and reloads assets with `search:` option
- Search works in combination with type filter

**Files**:
| File | Action |
|------|--------|
| `lib/storyarn_web/live/asset_live/index.ex` | Add search |
| `test/storyarn_web/live/asset_live/index_test.exs` | Add search tests |

**Tests**:
- Search filters assets by filename substring
- Empty search shows all assets
- Search combines with type filter
- Search is case-insensitive

---

## Task 4: Asset detail panel with usage info

**Goal**: Click an asset to see its details and where it's used (flow nodes, sheets).

**Changes**:
- Add `@selected_asset` assign (default `nil`)
- Click asset card → `handle_event("select_asset", %{"id" => id})`
- Detail panel shows: filename, type, size, upload date, audio player (if audio), image preview (if image)
- Add `Assets.get_asset_usages/2` query that checks:
  - `flow_nodes.data->>'audio_asset_id'` (JSONB)
  - `sheets.avatar_asset_id` (FK)
  - `sheets.banner_asset_id` (FK)
- Usage section lists references with links to flow/sheet

**Files**:
| File | Action |
|------|--------|
| `lib/storyarn/assets.ex` | Add `get_asset_usages/2` |
| `lib/storyarn_web/live/asset_live/index.ex` | Add detail panel + select |
| `test/storyarn/assets_test.exs` | Add usage query tests |
| `test/storyarn_web/live/asset_live/index_test.exs` | Add detail panel tests |

**Tests (context)**:
- Returns flow node usages for audio assets
- Returns sheet avatar/banner usages
- Returns empty map when asset is unused
- Excludes soft-deleted nodes

**Tests (LiveView)**:
- Clicking asset shows detail panel
- Detail panel shows filename, size, type
- Audio assets show player
- Usage section shows linked flows/sheets

---

## Task 5: Upload from Assets page

**Goal**: Add upload button to create new assets from the Assets page.

**Changes**:
- Add "Upload" button in the header actions
- Reuse `AudioUpload` JS hook pattern for a generic `AssetUpload` hook (accepts `audio/*` and `image/*`)
- `handle_event("upload_asset")` creates asset via `Storage.upload` + `Assets.create_asset`
- After upload, reload asset list and auto-select the new asset

**Files**:
| File | Action |
|------|--------|
| `assets/js/hooks/asset_upload.js` | CREATE — generic upload hook |
| `assets/js/app.js` | Register hook |
| `lib/storyarn_web/live/asset_live/index.ex` | Add upload handler |
| `test/storyarn_web/live/asset_live/index_test.exs` | Add upload tests |

**Tests**:
- Upload button renders for editors
- Upload creates asset and shows it in the grid
- Upload hidden for read-only users

---

## Task 6: Delete asset with usage warning

**Goal**: Add delete button with confirmation that warns if asset is in use.

**Changes**:
- Add delete button in the detail panel (only for editors)
- `set_pending_delete` + `confirm_modal` pattern (like `flow_live/index.ex`)
- Confirmation message includes usage count if asset is in use ("This asset is used in 3 places.")
- `handle_event("confirm_delete")` calls `Assets.delete_asset` + `Storage.delete` + optional thumbnail delete
- After delete, clear selection and reload assets

**Files**:
| File | Action |
|------|--------|
| `lib/storyarn_web/live/asset_live/index.ex` | Add delete with modal |
| `test/storyarn_web/live/asset_live/index_test.exs` | Add delete tests |

**Tests**:
- Delete button renders for editors
- Delete button hidden for read-only users
- Deleting removes asset from grid
- Delete modal shows usage warning when asset is in use

---

## File Summary

| # | File | Action | Task |
|---|------|--------|------|
| 1 | `lib/storyarn_web/router.ex` | MODIFY | 1 |
| 2 | `lib/storyarn_web/components/project_sidebar.ex` | MODIFY | 1 |
| 3 | `lib/storyarn_web/live/asset_live/index.ex` | CREATE | 1-6 |
| 4 | `test/storyarn_web/live/asset_live/index_test.exs` | CREATE | 1-6 |
| 5 | `lib/storyarn/assets.ex` | MODIFY | 4 |
| 6 | `test/storyarn/assets_test.exs` | MODIFY | 4 |
| 7 | `assets/js/hooks/asset_upload.js` | CREATE | 5 |
| 8 | `assets/js/app.js` | MODIFY | 5 |

---

## Verification per Task

1. **Task 1**: `mix test test/storyarn_web/live/asset_live/` + `mix credo --strict`
2. **Task 2**: Same + verify filter tabs render
3. **Task 3**: Same + verify search input
4. **Task 4**: `mix test test/storyarn/assets_test.exs` + LiveView tests + `mix credo --strict`
5. **Task 5**: Same + verify upload flow
6. **Task 6**: `mix test` (full suite) + `mix credo --strict`
