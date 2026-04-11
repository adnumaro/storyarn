# Migration: DocsLive.Show

## Status: partial
## Complexity: medium

## Files

- `lib/storyarn_web/live/docs_live/show.ex` -- Main LiveView (140 lines)
- `lib/storyarn_web/live/docs_live/components/docs_sidebar.ex` -- HEEx sidebar component (111 lines)
- `lib/storyarn_web/components/layouts.ex` -- `Layouts.docs` function (lines 628+, ~130 lines of HEEx)

## Current State

The LiveView renders a Vue component for the documentation body content (`docs/DocsShow`), but the entire page chrome is HEEx:

### In `Layouts.docs` (shared layout):
- **Header** with logo, docs link, theme toggle, login/dashboard link
- **Mobile sidebar toggle** with overlay
- **Left sidebar** (`<.docs_sidebar>`) with category tree, search, expandable sections
- **Prev/Next navigation** at bottom of content area
- **Right-rail TOC** placeholder

### In `DocsSidebar` (HEEx function component):
- Search input with icon
- Search results list
- Expandable category sections with chevron icons
- Guide links with active state styling

The LiveView itself handles events: `search`, `clear_search`, `toggle_sidebar`, `toggle_category`.

## What Needs to Change

Two approaches:

### Option A: Migrate sidebar and chrome to Vue (full V2)
1. Create `DocsLayout.vue` or expand `DocsShow.vue` to include sidebar, header, and nav
2. Pass categories, guides, search state, expanded state as props
3. Handle search/toggle events via `pushEvent`
4. Modify `Layouts.docs` to be a thin wrapper with a single `<.vue>` component

### Option B: Accept docs layout as HEEx (pragmatic)
The docs section is a public-facing, read-only page with simple interactivity (search, expand categories). The layout is shared infrastructure. Other layouts (`Layouts.app`, `Layouts.settings`) are also HEEx and are considered acceptable as "layout chrome" rather than "page UI".

**Recommendation:** Option B. The `Layouts.docs` HEEx is structural layout chrome, equivalent to `Layouts.app` and `Layouts.settings` which are also HEEx. The actual page content (guide body) is already Vue. Migrating the layout shell provides minimal value and is a lower priority than domain features.

If Option A is chosen:
- Create `modules/docs/DocsSidebar.vue` (category tree, search)
- Create `modules/docs/DocsNav.vue` (prev/next links)
- Modify `Layouts.docs` to render `<.vue>` components instead of HEEx

## Dependencies

- If Option A: new Vue components for sidebar and navigation
- Guide data serialization (categories, guides, search results) is already available as assigns
- `HtmlSanitizer.sanitize_html` for guide body is already handled server-side and passed as prop
