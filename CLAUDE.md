# CLAUDE.md

## Project Overview

**Storyarn** is a narrative design platform for game development and interactive storytelling. Built with collaborative, real-time editing.

**Stack:** Elixir 1.15+ / Phoenix 1.8 / LiveView 1.1 / LiveVue 1.2 / PostgreSQL / Redis / Tailwind v4 / shadcn-vue + reka-ui / TypeScript / Vue 3

## Debugging & Research Policy

- **When a fix doesn't work:** ALWAYS instrument before and after. Add `Logger.debug`/`IO.inspect`/`console.log` to verify your hypothesis. Never assume a fix works without measurement.
- **When the problem involves framework internals** (LiveView diffing, Ecto query planning, browser reflow, JS bundling): Search the web for documented behavior before writing code. Do not rely solely on reasoning from source code.
- **Never submit a "fix" without a verification step.** If you can't run the app interactively, add temporary debug output that proves the fix works, and tell the user what to look for.

## Convention References

**Read these before writing code. Duplicating existing utilities is a bug.**

| File                                    | Purpose                                                             |
| --------------------------------------- | ------------------------------------------------------------------- |
| `AGENTS.md`                             | Phoenix/LiveView/Ecto patterns (**MUST READ**)                      |
| @docs/conventions/shared-utilities.md   | **Shared utility registry — search here BEFORE writing any helper** |
| @docs/conventions/domain-patterns.md    | Context facades, CRUD templates, auth patterns                      |
| @docs/conventions/component-registry.md | HEEx components, layouts, and the Vue UI primitives                 |

## Frontend Architecture (Vue / TypeScript)

All frontend code lives in `assets/app/` and is fully TypeScript (`lang="ts"` in all Vue SFCs).
`assets/js/` holds only the LiveSocket bootstrap (`app.js`), two plain-JS hooks
(`PublicMobileNavigation`, `SeoMetadata`) and the PostHog init.

```
assets/app/
├── index.ts          — LiveVue entry: component resolution, i18n sync, Konva plugin
├── i18n.ts           — vue-i18n setup (globs locales/**/*.json)
├── live/             — LiveVue page components; mirrors lib/storyarn_web/live/
│                       and is addressed as v-component="live/{domain}/{page}/{Name}"
├── shell/            — App chrome: sidebars, project navbar, dashboard frame
├── components/       — Shared UI. ui/ = shadcn-vue/reka-ui primitives; also ai/,
│                       builders/, collab/, command-palette/, dashboard/, forms/,
│                       health/, invitations/, language/, navigation/, onboarding/,
│                       toolbar/, versioning/
├── shared/           — Cross-domain code
│   ├── utils/          — Pure utilities (utils.ts, date-utils.ts)
│   ├── composables/    — Shared composables (useLive, usePresence, etc.)
│   ├── domain/         — Shared business logic (variables, operators)
│   ├── components/, navigation/, command-palette/, types/
├── modules/          — Heavy domain editors
│   ├── flows/          — Flow editor (rete.js canvas) + player
│   ├── sheets/         — Sheet editor (blocks, tables)
│   ├── scenes/         — Scene editor (konva canvas, exploration)
│   ├── localization/   — Localization UI
│   ├── projects/       — Project settings (export/import)
│   └── public/         — Landing page
├── plugins/          — Third-party extensions (tiptap/, expression-editor/)
├── locales/          — i18n translations (en/, es/)
└── test/             — Vitest suites, mirroring the source tree
```

**Path aliases** (`vite.config.mjs` + `tsconfig.json`): `@app`, `@components`, `@shared`, `@modules`, `@shell`, `@plugins`. There is no `@live` — reach it via `@app/live`.

**TypeScript rules:**

- All `.vue` files use `<script setup lang="ts">`
- NO `any` — define proper interfaces
- NO `withDefaults()` — use destructured defaults: `const { prop = default } = defineProps<{...}>()`
- NO `Record<string, unknown>` for typed data — define interfaces based on actual field usage
- `useLive().pushEvent` payload is the only acceptable `Record<string, unknown>` (generic bridge to Phoenix)

## Language Policy

**Everything MUST be in English.** All user-facing text uses Gettext:

```elixir
put_flash(socket, :info, gettext("Project saved"))  # ✅
put_flash(socket, :info, "Project saved")            # ❌
```

Locales: `en` (default), `es`

## Reuse Existing Code

**NEVER duplicate existing utilities.** Before writing ANY helper:

1. **Check `lib/storyarn/shared/`** — CanonicalJSON, ColorUtils, EncryptedBinary, FormulaEngine, FormulaRuntime, HierarchicalSchema, HtmlSanitizer, HtmlUtils, ImportHelpers, InvitationNotifier, InvitationOperations, InvitationSchema, MapUtils, MembershipOperations, NameNormalizer, SearchHelpers, ShortcutHelpers, SoftDelete, TimeHelpers, TokenGenerator, Trashable, TreeOperations, Validations, WordCount
2. **Check `lib/storyarn_web/helpers/`** — Authorize, AutoSnapshot, EntitySearch, SaveStatusTimer, UndoRedoStack, VersionEventHelpers, VersionHistoryHelpers
3. **Check `lib/storyarn_web/live/shared/`** — CollaborationHelpers, DashboardHandlers, DashboardHelpers, InvitationHelpers, OnboardingHelpers, PickerSearch, ProjectChromeHelpers, RestorationHandlers
4. **Read `docs/conventions/shared-utilities.md`** for the full registry with examples

## Commands

```bash
mix phx.server              # Dev server (localhost:4000)
mix test                    # Run tests
mix convention.check        # Convention linter (see Convention Linter below)
mix precommit               # compile --warning-as-errors, deps.unlock --unused,
                            #   format, convention.check, credo --strict, test
docker compose up -d        # Start PostgreSQL + Redis + Mailpit
just quality                # quality-lint + mix test + mix test.e2e + Vitest
just quality-lint           # Oxfmt/Oxlint fix, tsc, arch+knip, mix format,
                            #   sobelow, convention.check, credo --strict
just js-check               # Oxfmt check + Oxlint + typecheck (no writes)
just js-fix                 # Oxfmt format + Oxlint auto-fix
just js-typecheck           # Typecheck Vue SFCs and TypeScript
just js-test                # Vitest JS tests
just js-grammar             # Build Lezer grammar
just e2e                    # Playwright E2E (mix test.e2e)
```

### Convention Linter

`mix convention.check` (`lib/mix/tasks/convention_check.ex`) enforces 8 rules:
`raw_without_sanitizer`, `datetime_utc_now`, `facade_bypass`, `string_to_atom`,
`sql_interpolation`, `put_flash_without_gettext`, `native_dialog`, `inline_slugify`.
The first, third and sixth run on `lib/storyarn_web/` only.

Suppress inline with `# storyarn:disable`, `# storyarn:disable:<rule>`, or a
`# storyarn:disable-start` / `# storyarn:disable-end` block. **It only walks Elixir
sources** — the collector globs `.ex` and `.exs` only, so Vue/TS files are never
scanned and the `native_dialog` rule does not protect the frontend. Enforce that
one by review.

## Domain Model

```
User → WorkspaceMembership (owner|admin|member|viewer)
         └→ Workspace → Project → ProjectMembership (owner|editor|viewer)
                                    └→ Sheets, Flows, Scenes, Screenplays, Assets
```

Contexts use facade with `defdelegate` → submodules (e.g., `sheets.ex` → `sheets/sheet_crud.ex`). See @docs/conventions/domain-patterns.md.

Screenplays have no editor route — the context is reachable only through export, import, trash and reference-tracking code paths.

## Variable System

**Sheet Blocks = Variables** (unless `is_constant: true`). Reference format: `{sheet_shortcut}.{variable_name}`

Block types: `number`, `select`, `multi_select`, `boolean`, `text`, `rich_text`, `date`, `table`, `reference` (non-variable), `gallery` (non-variable)

## Flow Editor

Node types (`@node_types` in `lib/storyarn/flows/flow_node.ex`): `entry`, `exit`, `dialogue`, `condition`, `instruction`, `hub`, `jump`, `subflow`, `annotation`, `sequence`

Per-type architecture: each `lib/storyarn_web/live/flow_live/nodes/{type}/node.ex` contains all metadata and handlers, dispatched through `flow_live/node_type_registry.ex`.

**`sequence` is the exception** — it is a container node persisted in `flow_nodes`, but it has no `nodes/sequence/` module and is absent from `NodeTypeRegistry`. It is handled by `lib/storyarn/flows/sequence_crud.ex` and rendered client-side by `assets/app/modules/flows/editor/services/flowSequenceScopes.ts` — a first-party implementation, **not** `rete-scopes-plugin`, which was dropped over its CC-BY-NC-SA-4.0 licence. Do not reintroduce that dependency.

Canvas-side node metadata mirrors this list in `assets/app/modules/flows/editor/lib/node-configs.ts` (`NODE_CONFIGS`).

## Icon Convention

**NEVER use Unicode emojis or custom SVGs. Always use [Lucide](https://lucide.dev) icons.**

- Vue: import the component from `lucide-vue-next` — `import { Box } from "lucide-vue-next"` then `<Box class="size-3" />`
- HEEx: `<.icon name="box" class="size-3" />` from `StoryarnWeb.Components.IconComponents` (auto-imported)
- Dynamic icon by string: declare a module-level `Record<string, Component>` map and render `<component :is="map[key]" />`. Never build the name at runtime.

`<.icon>` renders from a hardcoded `@icons` path map in `icon_components.ex` and uses `Map.fetch!/2` — **an unlisted name raises at render time.** Add the Lucide paths to that map before using a new icon in HEEx. It currently carries 12 icons, all for public/auth/docs surfaces; app surfaces are Vue and use `lucide-vue-next`.

## Dialog & Confirmation Policy

**NEVER use browser-native dialogs.** No `window.confirm()`, `window.alert()`, `window.prompt()`, or `data-confirm`.

Use `ConfirmDialog.vue` (`assets/app/components/ConfirmDialog.vue`). There is no HEEx modal — `core_components.ex` is down to two JS transition helpers, so any dialog belongs in a Vue boundary.

## Popover & Dropdown Positioning Policy

**NEVER use raw CSS absolute/relative positioning for popovers/dropdowns.** They break inside `overflow:hidden/clip` containers.

**ALWAYS use the reka-ui primitives** in `assets/app/components/ui/` — they teleport to the body and handle collision detection: `popover/`, `dropdown-menu/`, `context-menu/`, `tooltip/`, `select/`, `command/`, `dialog/`.

Reference implementations: `assets/app/components/command-palette/CommandPalette.vue`, `assets/app/shell/ProjectNavbarAccount.vue`

## Layouts

7 independent layouts (not nested), each its own module under `lib/storyarn_web/components/`:

`AuthLayout.auth`, `PublicLayout.public`, `DocsLayout.docs`, `SettingsLayout.settings`, `ProjectLayout.project`, `WorkspaceLayout.workspace`, `CompareLayout.compare`

All but `PublicLayout` mount a LiveVue shell (`v-component="live/layouts/{name}/Layout"`); `PublicLayout` is HEEx-native. `Layouts` itself (`layouts.ex`) is not a layout — it holds `<Layouts.flash_group>`, `<Layouts.command_palette>` and the SEO head components. See @docs/conventions/component-registry.md for full attrs.
