# Migration: AssetLive.Index

## Status: partial
## Complexity: low

## Files

- `lib/storyarn_web/live/asset_live/index.ex` -- Main LiveView (407 lines)

## Current State

The LiveView is mostly V2. The main asset list, filters, search, detail panel, and delete flow are all handled by the Vue component `assets/AssetIndex`.

The single remaining V1 pattern is the upload button in the top bar (lines 26-45):

```heex
<:top_bar_extra_right :if={@can_edit}>
  <div class="flex items-center px-1.5 py-1 surface-panel">
    <label class={[...]}>
      <.icon name="upload" class="size-4" />
      <span class="hidden xl:inline">Upload / Uploading...</span>
      <input type="file" accept="image/*,audio/*" class="hidden" id="asset-upload-input" />
    </label>
  </div>
</:top_bar_extra_right>
```

This renders a styled file input label with a Lucide icon. The actual upload processing happens via a JS event that reads the file and sends it as base64 to the LiveView.

## What Needs to Change

1. Move the upload button into a Vue component rendered in the top bar slot
2. Options:
   - Add upload button to the existing `AssetIndex.vue` component (if it has access to a toolbar slot)
   - Create a small `AssetUploadButton.vue` component rendered via `<.vue>` in the `top_bar_extra_right` slot
3. The file input, icon, and uploading state label are trivial to port to Vue

This is a ~15 line change.

## Dependencies

- None. The upload logic (base64 via pushEvent) is already Vue-compatible.
- Lucide icon available via `lucide-vue-next`
