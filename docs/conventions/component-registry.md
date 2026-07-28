# Component Registry

The UI is Vue. HEEx is reduced to layout shells, the SEO head, and a handful of
public-page partials; every interactive surface is a `<.vue>` boundary rendering
a component from `assets/app/`.

## Auto-imported HEEx Components

These are the only components available in ALL HEEx templates without an explicit
import (see `html_helpers/0` in `lib/storyarn_web.ex`):

### CoreComponents (`core_components.ex`)

No components — two `Phoenix.LiveView.JS` helpers only:

| Function             | Purpose               |
| -------------------- | --------------------- |
| `show(js, selector)` | Fade/slide in, 300ms  |
| `hide(js, selector)` | Fade/slide out, 200ms |

There is no `<.button>`, `<.input>`, `<.modal>`, `<.table>`, `<.list>`, `<.flash>`,
`<.back>` or `<.block_label>` — use the Vue equivalents in `assets/app/components/ui/`.
Flash is rendered by `<Layouts.flash_group>`, which mounts `live/layouts/flash/FlashGroup`.

### IconComponents (`icon_components.ex`)

| Component | Purpose     | Key Attributes                                                  |
| --------- | ----------- | --------------------------------------------------------------- |
| `<.icon>` | Lucide icon | `name` (required), `class` (default `"size-4"`), `:rest` global |

`name` is looked up in a hardcoded `@icons` path map with `Map.fetch!/2` — **an
unlisted name raises at render time.** Currently: `arrow-left`, `arrow-right`,
`book-open`, `check`, `chevron-down`, `mail`, `menu`, `newspaper`,
`panels-top-left`, `sparkles`, `x`. Add the Lucide path data to that map before
using a new icon in HEEx.

---

## Layouts (7 independent, NOT nested)

Each is its own module under `lib/storyarn_web/components/`, invoked by full path
(no import or alias at the call site):

```elixir
<StoryarnWeb.Components.ProjectLayout.project socket={@socket} flash={@flash}
  project={@project} workspace={@workspace} current_scope={@current_scope}
  current_user={@current_user} membership={@membership} urls={@urls}>
  # Project tools shell with navbar and optional sticky sidebar
</StoryarnWeb.Components.ProjectLayout.project>
```

| Module            | Function      | Required attrs                                                                          | Optional attrs / slots                                                                                             |
| ----------------- | ------------- | --------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `AuthLayout`      | `auth/1`      | `flash`, `socket`, `seo_metadata`                                                       | `current_scope`                                                                                                    |
| `PublicLayout`    | `public/1`    | `flash`, `socket`, `seo_metadata`                                                       | `current_scope`, `theme`, `landing`, `language_links`                                                              |
| `DocsLayout`      | `docs/1`      | `flash`, `socket`, `seo_metadata`, `categories`, `guides`, `locale`                     | `guide`, `expanded_categories`, `search_query`, `search_results`, `prev`, `next`, `sidebar_open`, `language_links` |
| `SettingsLayout`  | `settings/1`  | `flash`, `socket`, `current_scope`, `current_path`                                      | `workspaces`, `workspace`, `project`, `sudo_grant`, `onboarding*`, slots `:title`, `:subtitle`                     |
| `ProjectLayout`   | `project/1`   | `socket`, `project`, `workspace`, `current_scope`, `current_user`, `membership`, `urls` | `id`, `flash`, `active_tool`, `online_users`, `sidebar_module`, `sidebar_session`, `canvas_mode`, `onboarding*`    |
| `WorkspaceLayout` | `workspace/1` | `flash`, `socket`                                                                       | `current_scope`, `current_workspace`, `workspaces`, `onboarding*`                                                  |
| `CompareLayout`   | `compare/1`   | `flash`, `socket`                                                                       | `id`, `panel_title`, `panel_open`, `content_class`                                                                 |

All but `PublicLayout` mount a LiveVue shell (`v-component="live/layouts/{name}/Layout"`).
`PublicLayout` is HEEx-native and composes `PublicHeader.header` / `PublicFooter.footer`.

**`Layouts` (`layouts.ex`) is not a layout.** It provides the pieces the layouts
embed: `<Layouts.flash_group>`, `<Layouts.command_palette>`, `<Layouts.live_seo>`
and the `seo_*` head components, plus `absolute_url/1`.

---

## Other HEEx Components

| Module                   | Components                                                                               | Notes                                            |
| ------------------------ | ---------------------------------------------------------------------------------------- | ------------------------------------------------ |
| `PublicHeader`           | `<.header>` — `dark`, `landing`, `signed_in`, `urls`, `current_locale`, `language_links` | Used by `PublicLayout`                           |
| `PublicFooter`           | `<.footer>` — `landing`, `urls`                                                          | Used by `PublicLayout`                           |
| `PublicNavigation`       | `<.section_link>` — `landing`, `home_url`, `section`, `class`                            | Anchor links on marketing pages                  |
| `PublicMobileNavigation` | `<.navigation>` — same attrs as `PublicHeader`                                           | Paired with the `PublicMobileNavigation` JS hook |
| `PublicLanguageSwitcher` | `<.switcher>` — `id`, `current_locale`, `links`, `compact`, `on_navigate`                | Locale picker for public pages                   |

**Unused — do not build on these:** `SheetComponents` (`<.sheet_avatar>`,
`<.sheet_breadcrumb>`), `CollaborationComponents` (`<.collab_toast>`),
`TextComponents` (`widont/1`) and `Sidebar.TreeHelpers` have no call sites.
Collab toasts are pushed with `push_event("collab_toast", …)` and rendered by
`assets/app/components/collab/CollabToast.vue`.

---

## Vue UI Primitives (`assets/app/components/ui/`)

shadcn-vue components over reka-ui. Import via the `@components` alias, always from
the directory barrel: `import { Button } from "@components/ui/button"`.

`avatar` `badge` `button` `checkbox` `collapsible` `command` `context-menu` `dialog`
`dropdown-menu` `input` `label` `popover` `progress` `radio-group` `scroll-area`
`select` `separator` `sheet` `slider` `switch` `table` `tabs` `textarea` `toggle`
`toggle-group` `tooltip`

These are vendored — **treat them as generated**. Restyle via Tailwind classes at
the call site, not by editing the primitive.

---

## Shared Vue Components (`assets/app/components/`)

| Path                  | Components                                                                                                                                                                                                                         |
| --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ConfirmDialog.vue`   | The confirmation dialog. See Dialog Policy below                                                                                                                                                                                   |
| `SaveIndicator.vue`   | `status` (`"idle" \| "saving" \| "saved"`, default `"idle"`)                                                                                                                                                                       |
| `UserAvatar.vue`      | `email`, `displayName`, `size` (`xs\|sm\|md\|lg`), `color` — initials fallback                                                                                                                                                     |
| `ThemeSelector.vue`   | Theme switcher                                                                                                                                                                                                                     |
| `ai/`                 | `ContextDisclosure.vue`                                                                                                                                                                                                            |
| `builders/`           | `ConditionBuilder.vue`, `InstructionBuilder.vue` (+ `condition/`, `instruction/` internals, `types.ts`)                                                                                                                            |
| `collab/`             | `CollabToast.vue` — `actionLabels`; toast data arrives via `live.handleEvent("collab_toast")`, not props                                                                                                                           |
| `command-palette/`    | `CommandPalette.vue`, `PaletteEmpty.vue`                                                                                                                                                                                           |
| `dashboard/`          | Shared dashboard filters, issue section/list, sortable data table, and pagination (`DashboardFilterPopover`, `DashboardIssueFilters`, `DashboardIssuesSection`, `DashboardIssueList`, `DashboardDataTable`, `DashboardPagination`) |
| `forms/`              | `EditableText.vue`, `ColorPicker.vue`, `ColorPickerPopover.vue`, `ExpressionEditor.vue`, `VariableCombobox.vue`, `BooleanToggle.vue`, `PasswordInput.vue`                                                                          |
| `forms/fields/`       | `TextField`, `NumberField`, `SelectField`, `ToggleField`, `SliderField`, `ButtonGroupField`, `EntityCombobox` (barrel `index.ts`)                                                                                                  |
| `forms/assets/`       | `AssetPicker`, `AssetUploadButton`, `AudioAsset`, `ImageAsset`, `ImageFit`, `ImagePosition`                                                                                                                                        |
| `health/`             | `HealthStatusPopover.vue`                                                                                                                                                                                                          |
| `invitations/`        | `InvitationResponse.vue`                                                                                                                                                                                                           |
| `language/`           | `LanguageFlag.vue`, `LanguagePicker.vue`                                                                                                                                                                                           |
| `navigation/`         | `LiveLink.vue` — `to`, `mode` (`navigate\|patch\|external`), `state` (`push\|replace`). Use instead of a raw `<a>` so scroll position survives navigation                                                                          |
| `onboarding/`         | `OnboardingDialog.vue`, `onboardingGuides.ts`                                                                                                                                                                                      |
| `toolbar/`            | `ToolbarBase`, `ToolbarButton`, `ToolbarSeparator`, `ToolbarSizePicker`, `ToolbarColorPicker`, `ToolbarTooltip` (barrel `index.ts`)                                                                                                |
| `versioning/history/` | `VersionHistory.vue`, `CreateVersionDialog`, `DeleteVersionDialog`, `PromoteVersionDialog`, `RestorePreviewDialog`, `UnsavedChangesDialog`, `useVersionHistory.ts`                                                                 |

`assets/app/shell/` holds app chrome, not reusable widgets: `Sidebar.vue`,
`SidebarFrame.vue`, `MainSidebar.vue`, `WorkspaceSidebar.vue`, `DashboardContent.vue`,
`ProjectNavbarContext.vue`, `ProjectNavbarAccount.vue`.

`assets/app/shared/components/assets/AssetUploadDecisionDialog.vue` is the one
shared component living outside `components/`.

---

## Dialog Policy

`ConfirmDialog.vue` (`assets/app/components/ConfirmDialog.vue`):

| Prop / event  | Type                                      |
| ------------- | ----------------------------------------- |
| `open`        | `v-model`, `boolean`, **required**        |
| `title`       | `string`, **required**                    |
| `description` | `string?`                                 |
| `confirmText` | `string?` (default `"Confirm"`)           |
| `cancelText`  | `string?` (default `"Cancel"`)            |
| `variant`     | `"default" \| "destructive" \| "warning"` |
| `icon`        | `Component?` (a `lucide-vue-next` icon)   |
| `@confirm`    | emitted, then `open` is set to `false`    |
| `@cancel`     | emitted                                   |

NEVER use `window.confirm/alert/prompt` or `data-confirm`.

---

## Shared Live Helpers

| Module              | Import                                            | Purpose                                                                         |
| ------------------- | ------------------------------------------------- | ------------------------------------------------------------------------------- |
| `DashboardHelpers`  | `import StoryarnWeb.Live.Shared.DashboardHelpers` | Sorting, pagination, issue filtering, and load-state helpers for Vue dashboards |
| `DashboardHandlers` | `use StoryarnWeb.Live.Shared.DashboardHandlers`   | Injects debounced dashboard-invalidation `handle_info` clauses                  |

The rest of `lib/storyarn_web/live/shared/` (`CollaborationHelpers`,
`InvitationHelpers`, `OnboardingHelpers`, `PickerSearch`, `ProjectChromeHelpers`,
`RestorationHandlers`) is listed in @docs/conventions/shared-utilities.md.

---

## Changeset Helpers (Scenes domain)

**File:** `lib/storyarn/scenes/changeset_helpers.ex`

| Function                          | Purpose                                                                                    |
| --------------------------------- | ------------------------------------------------------------------------------------------ |
| `validate_target_pair(cs, types)` | Ensures target_type/target_id are both set or both nil, and that target_type is in `types` |
| `validate_color(cs, field)`       | Validates hex color format (#RGB, #RRGGBB, #RRGGBBAA) on `field`                           |

These are Scenes-specific but could be promoted to `Storyarn.Shared` if needed elsewhere.
