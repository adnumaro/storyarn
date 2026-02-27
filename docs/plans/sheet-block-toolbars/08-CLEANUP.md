# Plan 8: Cleanup — Remove Old Config Sidebar

> **Scope:** Delete dead code from the old config sidebar and related infrastructure.
>
> **Depends on:** Plans 0-7 (all toolbars + popovers implemented)

---

## Goal

Remove all code related to the old config sidebar that was replaced by inline toolbars + popovers. This is a pure deletion/cleanup plan — no new features.

---

## Files to Delete

| File | Reason |
|------|--------|
| `lib/storyarn_web/components/block_components/config_panel.ex` | Replaced by per-type config popovers |
| `lib/storyarn_web/live/sheet_live/handlers/config_panel_handlers.ex` | Handlers moved to `block_toolbar_handlers.ex` |
| `lib/storyarn_web/live/sheet_live/helpers/config_helpers.ex` | Logic absorbed into `block_toolbar_handlers.ex` |

---

## Files to Modify

### 1. `lib/storyarn_web/components/block_components.ex`

- **Remove:** `defdelegate config_panel(assigns), to: ConfigPanel`
- **Remove:** `import ConfigPanel` (if still present)
- **Remove:** `block_context_menu/1` function (if not already removed in Plan 0)

### 2. `lib/storyarn_web/live/sheet_live/components/content_tab.ex`

Remove dead references:
- **Remove:** `alias ConfigPanelHandlers`
- **Remove:** `alias ConfigHelpers`
- **Remove:** Any remaining `configuring_block` references
- **Remove:** Old `configure_block`, `close_config_panel`, `save_block_config` (old form-based version), `toggle_constant` (old version) event handlers that referenced `configuring_block`
- **Remove:** `add_select_option`, `remove_select_option`, `update_select_option` old handlers (replaced by block_id-based versions)
- **Remove:** `configuring_block` assign references

### 3. `lib/storyarn_web/live/sheet_live/components/inherited_block_components.ex`

- Remove any references to config panel opening for inherited blocks

### 4. `lib/storyarn_web/live/sheet_live/helpers/block_helpers.ex`

- Remove `show_block_menu` references if they were part of config panel flow

---

## Test Files to Delete

| File | Reason |
|------|--------|
| `test/storyarn_web/components/config_panel_test.exs` | Tests for deleted component |
| `test/storyarn_web/live/sheet_live/handlers/config_panel_handlers_test.exs` | Tests for deleted handler |

---

## Test Files to Update

- Any integration tests that reference `configure_block` or `close_config_panel` events need to be updated or removed
- Any tests that check for "Configure Block" sidebar text need updating

---

## Verification

After cleanup:

```bash
# Ensure no references to deleted modules remain
grep -r "ConfigPanel" lib/ test/ --include="*.ex" --include="*.exs"
grep -r "config_panel" lib/ test/ --include="*.ex" --include="*.exs" --include="*.html.heex"
grep -r "configuring_block" lib/ test/ --include="*.ex" --include="*.exs"
grep -r "ConfigHelpers" lib/ test/ --include="*.ex" --include="*.exs"
grep -r "configure_block" lib/ test/ --include="*.ex" --include="*.exs"
grep -r "close_config_panel" lib/ test/ --include="*.ex" --include="*.exs"
```

All greps should return 0 results (or only references in plan docs / CLAUDE.md).

---

## Post-Implementation Audit

- [ ] `mix compile --warnings-as-errors` — no warnings (no dead code references)
- [ ] `mix test` — all pass
- [ ] `mix credo --strict` — 0 issues
- [ ] Grep verification — no leftover references
- [ ] Manual: full sheet editing workflow works end-to-end
- [ ] Manual: all block types have working toolbars + config popovers
- [ ] Manual: undo/redo works for all config changes
- [ ] Manual: inherited blocks work correctly
- [ ] Manual: viewer role sees read-only toolbars
