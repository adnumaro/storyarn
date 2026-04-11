# Migration: SceneLive.Show

## Status: partial
## Complexity: medium (architectural decision needed)

## Files

- `lib/storyarn_web/live/scene_live/show.ex` -- Main LiveView (render at lines 51-348)

## Current State

The LiveView is mostly V2 with 10+ Vue components (SceneToolbar, SearchPanel, SceneActions, SceneCanvas, VersionHistoryPanel, SceneDock, Legend, ElementPropertiesPanel, SettingsPanel). All major UI is Vue.

Remaining HEEx patterns in the render function:

### 1. File upload form (lines 153-160)
```heex
<form :if={@can_edit && @uploads[:background]} id="bg-upload-form" phx-change="validate_bg_upload" class="hidden">
  <.live_file_input upload={@uploads.background} />
</form>
```
This is a hidden `<.live_file_input>` required by Phoenix LiveView's upload system. The actual drag-and-drop UX is handled via `phx-drop-target` on the canvas wrapper div.

### 2. Empty canvas upload prompt (lines 163-184)
```heex
<div :if={!background_set?(@scene) && @can_edit && @edit_mode && @uploads[:background]}
     class="absolute inset-0 flex items-center justify-center z-10 pointer-events-none">
  <label for={@uploads.background.ref} ...>
    <.icon name="image-plus" ... />
    <span>Upload background image</span>
    <span>or drag & drop</span>
  </label>
</div>
```
Upload prompt shown when no background is set. Uses `<.icon>` and inline Tailwind.

### 3. Drag & drop overlay (lines 187-199)
```heex
<div id="canvas-drop-indicator" class="hidden absolute inset-0 z-10 ...">
  <.icon name="image-plus" ... />
  <p>Drop image to set background</p>
</div>
```
Visual overlay shown during drag. Toggled by a JS hook.

### 4. Upload progress indicator (lines 205-230)
```heex
<div :for={entry <- ...} class="absolute bottom-20 left-1/2 ...">
  <.icon name="upload" ... />
  <div class="w-40">
    <div class="text-xs ...">{filename}</div>
    <div class="w-full bg-muted ...">
      <div class="bg-primary h-1.5 ..." style={"width: #{entry.progress}%"}></div>
    </div>
  </div>
</div>
```
Progress bar for background image upload.

## What Needs to Change

This is architecturally tricky because Phoenix LiveView's file upload system (`allow_upload`, `live_file_input`, `phx-drop-target`, `consume_uploaded_entries`) is deeply tied to HEEx. Options:

### Option A: Keep HEEx upload primitives (pragmatic)
The hidden `<form>` with `<.live_file_input>` is a Phoenix requirement -- it must stay in HEEx. The visual overlay/prompt/progress UI can be moved to Vue components that reference the same file input by ID.

Steps:
1. Keep the hidden `<form>` with `<.live_file_input>` in HEEx (it's invisible UI, not user-facing)
2. Move the upload prompt, drag overlay, and progress indicator into a new Vue component `SceneUploadOverlay.vue`
3. Pass upload state (has background, entries with progress) as Vue props
4. The Vue component triggers the file input via DOM (`document.getElementById`)

### Option B: Move upload to Vue entirely
Use a Vue-based file upload that sends data via `pushEvent` (base64 or chunked), similar to how `AssetLive.Index` handles uploads via `upload_asset` event with base64 data.

Steps:
1. Remove Phoenix `allow_upload` from mount
2. Handle file selection/drop in Vue
3. Send file data via `pushEvent("upload_background", {data: base64})`
4. Process server-side without Phoenix upload primitives

Option B is cleaner for V2 but loses Phoenix upload features (progress tracking, chunking, validation).

## Dependencies

- Decision on upload architecture (Option A vs B)
- If Option A: new `SceneUploadOverlay.vue` component
- If Option B: modify server-side upload handler to accept base64
