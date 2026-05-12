# V1 to V2 Migration Audit Summary

Generated: 2026-04-10

## Legend

| Status    | Description                                                                                                                                                                                                         |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| V2        | Fully migrated. LiveView renders Vue component(s) via `<.vue v-component>`. No HEEx UI.                                                                                                                             |
| V2-layout | LiveView content is Vue, but wrapped in a HEEx layout (`Layouts.app`, `Layouts.settings`, etc.) which itself renders HEEx chrome (header, sidebar). This is the expected pattern -- layouts are shared HEEx shells. |
| Partial   | Mix of Vue components and HEEx UI elements in the LiveView's own render.                                                                                                                                            |
| V1        | Fully HEEx/DaisyUI. No Vue components.                                                                                                                                                                              |
| N/A       | Backend-only (redirects on mount, no meaningful render).                                                                                                                                                            |

---

## LiveView Migration Status

### Auth (`user_live/`)

| LiveView                 | Status | Notes                                                    |
| ------------------------ | ------ | -------------------------------------------------------- |
| `UserLive.Login`         | V2     | Single `<.vue v-component="modules/auth/SignIn">`        |
| `UserLive.Registration`  | V2     | Single `<.vue v-component="modules/auth/SignUp">`        |
| `UserLive.ConfirmAccess` | V2     | Single `<.vue v-component="modules/auth/ConfirmAccess">` |

### Landing (`landing_live/`)

| LiveView            | Status | Notes                                                     |
| ------------------- | ------ | --------------------------------------------------------- |
| `LandingLive.Index` | V2     | Single `<.vue v-component="modules/landing/LandingPage">` |

### Workspaces (`workspace_live/`)

| LiveView                   | Status    | Notes                                    |
| -------------------------- | --------- | ---------------------------------------- |
| `WorkspaceLive.Index`      | V2        | Redirect + loading Vue component         |
| `WorkspaceLive.Show`       | V2-layout | Vue dashboard inside `Layouts.app`       |
| `WorkspaceLive.New`        | V2        | Single Vue component                     |
| `WorkspaceLive.Invitation` | V2        | Single Vue component in `Layouts.public` |

### Projects (`project_live/`)

| LiveView                 | Status    | Notes                                                               |
| ------------------------ | --------- | ------------------------------------------------------------------- |
| `ProjectLive.Show`       | V2-layout | Vue dashboard inside `Layouts.app`                                  |
| `ProjectLive.Form`       | V2        | Single Vue component (uses `:live_component` macro but renders Vue) |
| `ProjectLive.Invitation` | V2        | Vue in `Layouts.public`, redirects on accept                        |
| `ProjectLive.Trash`      | V2        | Single Vue component                                                |

### Sheets (`sheet_live/`)

| LiveView          | Status    | Notes                                                                                                                                  |
| ----------------- | --------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `SheetLive.Index` | V2-layout | Vue dashboard inside `Layouts.app`                                                                                                     |
| `SheetLive.Show`  | V2-layout | Multiple Vue components (header, tabs, blocks, etc.) inside `Layouts.app`. Minimal HEEx scaffolding (container divs, loading spinner). |

### Flows (`flow_live/`)

| LiveView              | Status      | Notes                                                                                                                                                                                    |
| --------------------- | ----------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `FlowLive.Index`      | V2-layout   | Vue dashboard inside `Layouts.app`                                                                                                                                                       |
| `FlowLive.Show`       | **Partial** | Multiple Vue components but uses HEEx `<.collab_toast>` from `CollaborationComponents`. See [migration task](migration-flow-live-show.md).                                               |
| `FlowLive.Form`       | V2          | Single Vue component (LiveComponent wrapper)                                                                                                                                             |
| `FlowLive.PlayerLive` | **V1**      | Full HEEx render with HEEx function components (`player_slide`, `player_toolbar`, `player_choices`, `player_outcome`). No Vue. See [migration task](migration-flow-live-player-live.md). |

### Scenes (`scene_live/`)

| LiveView                    | Status      | Notes                                                                                                                                                                                                              |
| --------------------------- | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `SceneLive.Index`           | V2-layout   | Vue dashboard inside `Layouts.app`                                                                                                                                                                                 |
| `SceneLive.Show`            | **Partial** | Multiple Vue components but has HEEx for: file upload form, empty canvas upload prompt, drag overlay, upload progress indicator, `<.icon>` components in HEEx. See [migration task](migration-scene-live-show.md). |
| `SceneLive.ExplorationLive` | V2          | Single Vue component                                                                                                                                                                                               |

### Localization (`localization_live/`)

| LiveView                  | Status    | Notes                               |
| ------------------------- | --------- | ----------------------------------- |
| `LocalizationLive.Index`  | V2-layout | Vue components inside `Layouts.app` |
| `LocalizationLive.Edit`   | V2-layout | Vue component inside `Layouts.app`  |
| `LocalizationLive.Report` | V2-layout | Vue component inside `Layouts.app`  |

### Assets (`asset_live/`)

| LiveView          | Status      | Notes                                                                                                                                |
| ----------------- | ----------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `AssetLive.Index` | **Partial** | Vue component for asset list, but top bar upload button is HEEx with `<.icon>`. See [migration task](migration-asset-live-index.md). |

### Compare (`compare_live/`)

| LiveView            | Status | Notes                                 |
| ------------------- | ------ | ------------------------------------- |
| `CompareLive.Flow`  | V2     | Single Vue component, `layout: false` |
| `CompareLive.Sheet` | V2     | Single Vue component, `layout: false` |
| `CompareLive.Scene` | V2     | Single Vue component, `layout: false` |

### Project Settings (`project_settings_live/`)

| LiveView                             | Status    | Notes                         |
| ------------------------------------ | --------- | ----------------------------- |
| `ProjectSettingsLive.General`        | V2-layout | Vue inside `Layouts.settings` |
| `ProjectSettingsLive.Members`        | V2-layout | Vue inside `Layouts.settings` |
| `ProjectSettingsLive.Snapshots`      | V2-layout | Vue inside `Layouts.settings` |
| `ProjectSettingsLive.Localization`   | V2-layout | Vue inside `Layouts.settings` |
| `ProjectSettingsLive.VersionControl` | V2-layout | Vue inside `Layouts.settings` |

### Export/Import (`export_import_live/`)

| LiveView                 | Status    | Notes                         |
| ------------------------ | --------- | ----------------------------- |
| `ExportImportLive.Index` | V2-layout | Vue inside `Layouts.settings` |

### Settings (`settings_live/`)

| LiveView                                | Status    | Notes                         |
| --------------------------------------- | --------- | ----------------------------- |
| `SettingsLive.Profile`                  | V2-layout | Vue inside `Layouts.settings` |
| `SettingsLive.Security`                 | V2-layout | Vue inside `Layouts.settings` |
| `SettingsLive.Connections`              | V2-layout | Vue inside `Layouts.settings` |
| `SettingsLive.WorkspaceGeneral`         | V2-layout | Vue inside `Layouts.settings` |
| `SettingsLive.WorkspaceMembers`         | V2-layout | Vue inside `Layouts.settings` |
| `SettingsLive.WorkspaceDeletedProjects` | V2-layout | Vue inside `Layouts.settings` |

### Docs (`docs_live/`)

| LiveView        | Status      | Notes                                                                                                                                                                   |
| --------------- | ----------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `DocsLive.Show` | **Migrated** | `DocsLayout.docs` is a thin LiveVue boundary (`live/layouts/docs/Layout`) and `DocsLive.Show` injects the sanitized guide body through `live/docs/show/Content`. |

---

## Shared HEEx Components Still In Use

These HEEx components are used by LiveViews/layouts and represent V1 patterns:

| Component                                       | Used By                                 | Type               |
| ----------------------------------------------- | --------------------------------------- | ------------------ |
| `CollaborationComponents.collab_toast/1`        | `FlowLive.Show`                         | Function component |
| `CollaborationComponents.online_users/1`        | Moduledoc only (not used in any render) | Function component |
| `CollaborationComponents.node_lock_indicator/1` | Moduledoc only (not used in any render) | Function component |
| `PlayerSlide`                                   | `FlowLive.PlayerLive`                   | Function component |
| `PlayerToolbar`                                 | `FlowLive.PlayerLive`                   | Function component |
| `PlayerChoices`                                 | `FlowLive.PlayerLive`                   | Function component |
| `PlayerOutcome`                                 | `FlowLive.PlayerLive`                   | Function component |

## Stale V1 Code (Can Be Deleted)

| File                                               | Reason                                                                                                                    |
| -------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| `lib/storyarn_web/live/components/asset_upload.ex` | Dead code. `AssetUpload` LiveComponent is not referenced by any other file. See [task](migration-stale-asset-upload.md).  |
| `CollaborationComponents.online_users/1`           | Only used in its own moduledoc example. Layouts.app passes `online_users` as a Vue prop to `layout/RightToolbar` instead. |
| `CollaborationComponents.node_lock_indicator/1`    | Only used in its own moduledoc example. Lock indicators are handled in Vue.                                               |

---

## Summary Statistics

| Category                        | Count  |
| ------------------------------- | ------ |
| Fully migrated (V2 / V2-layout) | 35     |
| Partially migrated              | 4      |
| Not migrated (V1)               | 1      |
| **Total LiveViews**             | **40** |

## Priority Order for Remaining Migration

1. **`FlowLive.PlayerLive`** (V1) -- The only fully un-migrated LiveView. Contains 4 HEEx function components (slide, toolbar, choices, outcome).
2. **`FlowLive.Show`** (Partial) -- Single HEEx `<.collab_toast>` usage. Trivial to replace.
3. **`AssetLive.Index`** (Partial) -- Upload button in top bar is HEEx. Minor.
4. **`SceneLive.Show`** (Partial) -- File upload form, empty state, upload progress in HEEx. These use LiveView upload primitives (`live_file_input`, `phx-drop-target`) which require HEEx -- may need architectural decision on how to handle.
5. **`DocsLive.Show`** (Partial) -- The docs layout itself is HEEx. Lower priority since docs is a public-facing read-only page.
