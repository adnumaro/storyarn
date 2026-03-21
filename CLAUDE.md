# CLAUDE.md

## Project Overview

**Storyarn** is a narrative design platform for game development and interactive storytelling. Built with collaborative, real-time editing.

**Stack:** Elixir 1.15+ / Phoenix 1.8 / LiveView 1.1 / PostgreSQL / Redis / Tailwind v4 / daisyUI

## Debugging & Research Policy

- **When a fix doesn't work:** ALWAYS instrument before and after. Add `Logger.debug`/`IO.inspect`/`console.log` to verify your hypothesis. Never assume a fix works without measurement.
- **When the problem involves framework internals** (LiveView diffing, Ecto query planning, browser reflow, JS bundling): Search the web for documented behavior before writing code. Do not rely solely on reasoning from source code.
- **Never submit a "fix" without a verification step.** If you can't run the app interactively, add temporary debug output that proves the fix works, and tell the user what to look for.

## Convention References

**Read these before writing code. Duplicating existing utilities is a bug.**

| File                                    | Purpose                                                             |
|-----------------------------------------|---------------------------------------------------------------------|
| `AGENTS.md`                             | Phoenix/LiveView/Ecto patterns (**MUST READ**)                      |
| @docs/conventions/shared-utilities.md   | **Shared utility registry — search here BEFORE writing any helper** |
| @docs/conventions/domain-patterns.md    | Context facades, CRUD templates, auth patterns                      |
| @docs/conventions/component-registry.md | All reusable HEEx components                                        |

## Language Policy

**Everything MUST be in English.** All user-facing text uses Gettext:
```elixir
put_flash(socket, :info, gettext("Project saved"))  # ✅
put_flash(socket, :info, "Project saved")            # ❌
```
Locales: `en` (default), `es`

## Reuse Existing Code

**NEVER duplicate existing utilities.** Before writing ANY helper:

1. **Check `lib/storyarn/shared/`** — NameNormalizer, ShortcutHelpers, TreeOperations, SoftDelete, Validations, MapUtils, SearchHelpers, TimeHelpers, TokenGenerator, ColorUtils, FormulaEngine, FormulaRuntime, HtmlUtils, WordCount, HierarchicalSchema, ImportHelpers, InvitationOperations, MembershipOperations
2. **Check `lib/storyarn_web/helpers/`** — Authorize, SaveStatusTimer, UndoRedoStack
3. **Read `docs/conventions/shared-utilities.md`** for the full registry with examples

## Commands

```bash
mix phx.server              # Dev server (localhost:4000)
mix test                    # Run tests
mix precommit               # Before commit: format, credo, test
docker compose up -d        # Start PostgreSQL + Redis + Mailpit
just quality                # Full checks: Biome fix, Credo, tests, E2E, Vitest
just js-fix                 # Biome auto-fix JS
just js-test                # Vitest JS tests
just js-grammar             # Build Lezer grammar
```

## Domain Model

```
User → WorkspaceMembership (owner|admin|member|viewer)
         └→ Workspace → Project → ProjectMembership (owner|editor|viewer)
                                    └→ Sheets, Flows, Scenes, Screenplays, Assets
```

Contexts use facade with `defdelegate` → submodules (e.g., `sheets.ex` → `sheets/sheet_crud.ex`). See @docs/conventions/domain-patterns.md.

## Variable System

**Sheet Blocks = Variables** (unless `is_constant: true`). Reference format: `{sheet_shortcut}.{variable_name}`

Block types: `number`, `select`, `multi_select`, `boolean`, `text`, `rich_text`, `date`, `table`, `reference` (non-variable), `gallery` (non-variable)

## Flow Editor

Node types: `entry`, `exit`, `dialogue`, `condition`, `instruction`, `hub`, `jump`, `slug_line`, `subflow`, `annotation`

Per-type architecture: each `lib/storyarn_web/live/flow_live/nodes/{type}/node.ex` contains all metadata and handlers.

## Icon Convention

**NEVER use Unicode emojis or custom SVGs. Always use [Lucide](https://lucide.dev) icons.**

- HEEx: `<.icon name="box" class="size-3" />`
- Shadow DOM / innerHTML: `createIconHTML(Icon, { size })` from `node_config.js`
- Node headers: `createIconSvg(Icon)` from `node_config.js`
- Regular DOM appends: `createElement(Icon, { width, height })` from `lucide`
- Always pre-create icon constants at module level

## Dialog & Confirmation Policy

**NEVER use browser-native dialogs.** No `window.confirm()`, `window.alert()`, `window.prompt()`, or `data-confirm`.

Use `<.confirm_modal>` + `show_modal(id)` or `<.modal>` from `core_components.ex`.

## Popover & Dropdown Positioning Policy

**NEVER use raw CSS absolute/relative positioning for popovers/dropdowns.** They break inside `overflow:hidden/clip` containers.

**ALWAYS use `@floating-ui/dom`** via `createFloatingPopover` from `assets/js/utils/floating_popover.js`.

Reference implementations: `hooks/table_cell_select.js`, `hooks/color_picker.js`

## Layouts

6 independent layouts (not nested): `Layouts.app`, `Layouts.focus`, `Layouts.auth`, `Layouts.public`, `Layouts.settings`, `Layouts.docs`
