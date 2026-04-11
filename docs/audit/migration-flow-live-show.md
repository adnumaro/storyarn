# Migration: FlowLive.Show

## Status: partial
## Complexity: low

## Files

- `lib/storyarn_web/live/flow_live/show.ex` -- Main LiveView (~250 lines render section)
- `lib/storyarn_web/components/collaboration_components.ex` -- Contains `collab_toast/1` HEEx component (used at line 188)

## Current State

The LiveView is almost fully migrated to Vue. It renders 8+ Vue components (FlowHeader, FlowEditor, FlowDock, FlowVersionHistoryPanel, FlowDebugPanel, FlowBuilderPanel, FlowScreenplayEditor, FlowPreview) inside `Layouts.app`.

The single remaining V1 pattern is:

```elixir
<.collab_toast
  :if={@collab_toast}
  action={@collab_toast.action}
  user_email={@collab_toast.user_email}
  user_color={@collab_toast.user_color}
/>
```

This is a HEEx function component from `CollaborationComponents` that renders a small toast notification when collaborators perform actions. It uses `<.icon>` and Tailwind classes.

Note: `SheetLive.Show` already has a Vue version of this -- `modules/sheets/components/CollabToast` -- used via `<.vue v-component="modules/sheets/components/CollabToast">`. This is a shared component at `assets/app/components/collab/CollabToast.vue` or `assets/app/modules/sheets/components/CollabToast.vue`.

## What Needs to Change

1. Replace the HEEx `<.collab_toast>` with the Vue CollabToast component that already exists (used by sheets)
2. Serialize `@collab_toast` data as props for the Vue component
3. Remove the `import StoryarnWeb.Components.CollaborationComponents` if no longer needed

This is a ~5 line change in the render function.

## Dependencies

- Vue `CollabToast` component already exists (used by `SheetLive.Show`)
- May need to verify the shared component path is reusable or extract to `components/collab/`
