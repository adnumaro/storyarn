# Sheet Block Toolbars — Split Plans

> Replaces the config sidebar with inline hover toolbars + floating popovers.
>
> Parent document: [`../SHEET_BLOCK_TOOLBARS.md`](../SHEET_BLOCK_TOOLBARS.md)

## Plan Index

| # | Plan | Scope | Complexity | Status |
|---|------|-------|-----------|--------|
| 0 | [Universal Toolbar](00-UNIVERSAL-TOOLBAR.md) | Hover toolbar (duplicate, constant toggle, config gear, [⋮] menu), block selection, keyboard shortcuts | High | Pending |
| 1 | [Text / Rich Text](01-TEXT-RICH-TEXT.md) | Config popover: placeholder, max length | Low | Pending |
| 2 | [Number](02-NUMBER.md) | Config popover: min/max/step, placeholder | Low | Pending |
| 3 | [Boolean](03-BOOLEAN.md) | Config popover: mode (2/3-state), custom labels | Medium | Pending |
| 4 | [Select / Multi-Select](04-SELECT-MULTI-SELECT.md) | Config popover: options list, placeholder, max selections | Medium-High | Pending |
| 5 | [Date](05-DATE.md) | Config popover: min/max date | Low | Pending |
| 6 | [Reference](06-REFERENCE.md) | Config popover: allowed types checkboxes | Low | Pending |
| 7 | [Table](07-TABLE.md) | Toolbar variants (no config popover) | Low | Pending |
| 8 | [Cleanup](08-CLEANUP.md) | Remove old config sidebar + dead code | Low | Pending |

## Dependency Graph

```
Plan 0 (Universal Toolbar) ─── foundation for all
  ├── Plan 1 (Text/Rich Text) ─── establishes save_block_config event pattern
  │     ├── Plan 2 (Number)
  │     ├── Plan 3 (Boolean)
  │     ├── Plan 4 (Select/Multi-Select) ─── most complex popover
  │     ├── Plan 5 (Date)
  │     └── Plan 6 (Reference)
  └──────── Plan 8 (Cleanup) ─── after all plans complete
```

## Reusable Components

| Component | Source | Used By |
|-----------|--------|---------|
| `ToolbarPopover` JS hook | `assets/js/hooks/toolbar_popover.js` | Config gear on all types |
| `createFloatingPopover` | `assets/js/utils/floating_popover.js` | Via ToolbarPopover |
| `<.block_advanced_config>` | **NEW** (Plan 0) | All config popovers (Plans 1-6) |
| `<.block_toolbar>` | **NEW** (Plan 0) | Hover toolbar: duplicate, constant toggle, config gear, [⋮] menu |

## Decisions

1. **No coexistence** — Toolbar replaces sidebar immediately in Plan 0. Sidebar code removed in Plan 8.
2. **Shared advanced section** — `<.block_advanced_config>` renders scope/required/variable in all popovers.
3. **Block-ID based events** — All toolbar handlers take `block_id` as param (not `configuring_block` assign).
4. **ToolbarPopover reuse** — Existing JS hook in `assets/js/hooks/` (global, NOT flow-specific).
5. **Toolbar is minimal** — Only non-inline actions. Move/delete via keyboard shortcuts.
6. **Block selection enables keyboard shortcuts** — Toolbar uses hover visibility, selection uses click/focus.

## Boundary Compliance

All reused assets live in shared locations — **no cross-context Elixir imports**:

| Asset | Location | Status |
|-------|----------|--------|
| `ToolbarPopover` hook | `assets/js/hooks/toolbar_popover.js` | Global (registered in `app.js`) |
| `createFloatingPopover` | `assets/js/utils/floating_popover.js` | Shared utility |
| `data-event`/`data-params` | HTML convention | No module dependency |
| New Elixir components | `lib/storyarn_web/components/block_components/` | Web layer (shared) |
| New handlers | `lib/storyarn_web/live/sheet_live/handlers/` | Sheet-specific |

**Rule:** Nothing from `flow_live/` or `scene_live/` is imported into sheet code. If scene `ToolbarWidgets` are needed later, extract to `lib/storyarn_web/components/` first.

## Estimated Test Count

| Plan | Unit Tests | Integration Tests | Total |
|------|-----------|-------------------|-------|
| 0 | ~29 | ~8 | ~37 |
| 1 | ~6 | ~7 | ~13 |
| 2 | ~5 | ~6 | ~11 |
| 3 | ~6 | ~6 | ~12 |
| 4 | ~9 | ~8 | ~17 |
| 5 | ~4 | ~4 | ~8 |
| 6 | ~4 | ~4 | ~8 |
| 7 | ~11 | ~8 | ~19 |
| 8 | — | ~5 (regression) | ~5 |
| **Total** | **~70** | **~56** | **~126** |
