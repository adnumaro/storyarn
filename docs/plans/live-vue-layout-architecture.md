# LiveVue layout architecture

**Status:** active rollout
**Date drafted:** 2026-05-11
**Branch:** `feat/live-vue-sheets`
**Scope:** layout architecture across public, auth, docs, workspace/settings, project tools, and immersive/compare routes.

## Current Snapshot

The authenticated app navigation now shares one `live_session :authenticated_app`.
Workspace dashboards, workspace settings, project settings, project dashboard, and
project tools can navigate without a full document reload.

Implemented LiveVue layout boundaries:

- `assets/app/live/layouts/auth/Layout.vue`
- `assets/app/live/layouts/docs/Layout.vue`
- `assets/app/live/layouts/settings/Layout.vue`
- `assets/app/live/layouts/workspace/Layout.vue`
- `assets/app/live/layouts/project/Layout.vue`

Implemented architecture checks:

- `npm run arch:live-vue` validates canonical public LiveVue component names.
- `npm run arch:links` validates internal Vue links use LiveView navigation semantics.
- `npm run arch:sessions` validates the unified authenticated LiveView session boundary.

Known remaining work:

- `SceneLive.Show` still uses `StoryarnWeb.Components.ProjectShell.project_shell`.
- `ProjectShell` should be removed or blocked once scenes move to `ProjectLayout`.
- `Layouts.app` still has two LiveView consumers:
  - `WorkspaceLive.New`
  - `ProjectLive.Trash`
- `Layouts.public`, `Layouts.compare`, flow player, and scene exploration still contain visual HEEx composition.
- `ProjectLayout` should normalize the project navbar height to one canonical value.
- Generic flash visibility for `ProjectLayout` needs an explicit decision because project tools still call `put_flash/3`.

Current verification state:

- `npm run arch` passes.
- Remaining dependency-cruiser warnings are the known `assets/app/components/ui/**` circular barrel warnings.

## Objective

Create a cohesive layout system for the Phoenix + LiveVue application where:

- Elixir owns data loading, authorization, route context, persistence boundaries, and LiveView events.
- Vue owns visual layout composition, local UI state, and interaction chrome.
- LiveViews render only public Vue boundaries, never internal domain components.
- Layouts follow one shared mental model across route families, even when the visual treatment differs.
- Persistent UI state survives LiveView navigation where it provides real product value.
- Tool-specific implementations remain different only where the domain requires it.

The target is not a minor cleanup of the current `Layouts.*` functions. The target is a route-layout architecture that can replace the current mixed conventions.

## Source Patterns

LiveVue documents three persistent layout patterns:

1. Root layout component with `v-inject`
2. Sticky LiveView layout with `v-inject`
3. Headless sticky layout state

For Storyarn, the most relevant pattern is **root LiveVue layout component with `v-inject`**, while keeping server-backed chrome state in sticky child LiveViews where needed.

Phoenix LiveView also separates:

- root layout: static document shell, rendered on initial HTTP request
- app/layout component: dynamic LiveView-rendered application UI

So the architecture should keep Phoenix root layout minimal and move application chrome into explicit LiveVue layout boundaries.

## Architectural Decision

Use **route-family LiveVue layouts** as public boundaries under `assets/app/live/layouts`.

Use `v-inject` when a page should render into a public layout boundary owned by the same LiveView render tree.

Use sticky LiveViews for persistent server-backed children such as presence, sidebars, and tool-specific state holders.

Do not use a single global Vue root layout for everything. Storyarn has multiple product modes with different chrome requirements, and forcing them into one shell would make the project-tool layout dominate unrelated pages.

The current agreed convention is:

- Elixir renders route-family layouts and public page boundaries only.
- Elixir does not render small internal chrome such as docks, toolbars, block lists, canvas layers, or domain panel internals.
- Route pages inject coarse public boundaries into layout slots:
  - `Header`
  - `HeaderActions` when needed
  - `Surface`
  - `Panels`
  - `Dashboard`
  - `Sidebar`
- Domain internals remain under `assets/app/modules/**`.
- Public boundaries rendered by Elixir live under `assets/app/live/**`.

For project tools the canonical render shape is:

```elixir
<ProjectLayout.project_layout ...>
  <.vue
    v-component="live/<tool>/show/Header"
    v-inject:top-left="project-layout"
    ...
  />

  <.vue
    v-component="live/<tool>/show/HeaderActions"
    v-inject:top-right="project-layout"
    ...
  />

  <.vue
    v-component="live/<tool>/show/Surface"
    v-inject="project-layout"
    ...
  />

  <.vue
    v-component="live/<tool>/show/Panels"
    v-inject:panels="project-layout"
    ...
  />
</ProjectLayout.project_layout>
```

If a route needs multiple controls in the same slot, it should expose one public
boundary that composes those controls in Vue. It should not make Elixir render
multiple small internal controls directly.

## Target Directory Shape

```txt
assets/app/live/
  layouts/
    public/
      Layout.vue
    auth/
      Layout.vue
    docs/
      Layout.vue
    app/
      Layout.vue
      WorkspaceSidebar.vue
      SettingsSidebar.vue
    project/
      Layout.vue
      LeftToolbar.vue
      RightToolbar.vue
      SidebarHost.vue
      PresenceHost.vue
    compare/
      Layout.vue
    immersive/
      Layout.vue

  flow/
    dashboard/Dashboard.vue
    show/Header.vue
    show/Surface.vue
    show/Panels.vue
    show/Canvas.vue
    player/Player.vue

  sheet/
    dashboard/Dashboard.vue
    show/Header.vue
    show/Surface.vue
    show/Panels.vue

  scene/
    dashboard/Dashboard.vue
    show/Header.vue
    show/HeaderActions.vue
    show/Surface.vue
    show/Panels.vue
    show/CompactSurface.vue
    exploration/Player.vue
```

`assets/app/modules/**` remains the internal domain implementation. Elixir should not render from `modules`.

## Layout Families

### Public Layout

Routes:

- landing
- contact
- public invitations

Recommended pattern:

- LiveVue layout boundary, not sticky by default.
- Page boundary rendered or injected into `live/layouts/public/Layout`.
- Public navigation, footer, theme handling, and public chrome live in Vue.

Reason:

Public pages have limited server-backed chrome. Persisting the layout across LiveView navigation is optional and not a first-order need.

### Auth Layout

Routes:

- login
- registration
- confirm access

Recommended pattern:

- LiveVue layout boundary, not sticky.
- Auth forms remain page boundaries.

Reason:

Auth flows are short and do not benefit from persistent layout state. They still benefit from having the same public boundary convention as the rest of the app.

### Docs Layout

Routes:

- `/docs`
- `/docs/:category/:slug`

Recommended pattern:

- Candidate for sticky LiveView layout with `v-inject`.
- Start non-sticky if we want lower implementation risk.
- Promote to sticky if preserving sidebar expansion/search/scroll across docs navigation matters.

Reason:

Docs has persistent chrome: header, sidebar, search state, expanded categories, and table of contents. It is cohesive enough to become its own layout family.

### App Layout: Workspaces And Settings

Routes:

- `/workspaces`
- `/workspaces/:slug`
- `/workspaces/new`
- `/users/settings`
- `/users/settings/security`
- `/users/settings/connections`
- `/users/settings/workspaces/:slug/*`
- project settings pages

Recommended pattern:

- `AppShellLive` sticky candidate.
- `live/layouts/app/Layout.vue` owns app-level authenticated chrome.
- The layout supports modes rather than separate unrelated layout systems:
  - `workspace`
  - `settings`
  - `form`
  - possibly `project-settings`

Reason:

These routes share authenticated context, current user, workspace list, account actions, and settings navigation. They should feel like the same app area even when their sidebars differ.

Open decision:

Project settings can either belong to `app/settings` mode or to `project` layout mode. The better product answer depends on whether project settings should keep project tool chrome or use a full settings workspace. Current behavior leans settings-style.

### Project Tools Layout

Routes:

- project dashboard
- sheets dashboard/show
- flows dashboard/show
- scenes dashboard/show
- assets
- localization

Recommended pattern:

- Public LiveVue layout boundary with `v-inject`.
- Sticky child LiveViews for presence and the active tool sidebar.
- This is the highest-value target for persistent layout work.
- Replace `ProjectShell.project_shell` with an explicit project layout component plus a public Vue layout boundary.

Reason:

Project tools have the most stateful shared chrome:

- tool switcher
- current workspace/project
- current user
- online users / presence
- restoration banner
- tool-specific sidebars
- toolbar extras
- active entity selection
- canvas vs document main area

This is where consistent layout composition matters most. Sticky child LiveViews can keep server-backed state alive where it has product value.

Target Elixir shape:

```elixir
<ProjectLayout.project_layout ...>

<.vue
  v-component="live/flow/show/Header"
  v-inject:top-left="project-layout"
  ...
/>

<.vue
  v-component="live/flow/show/Surface"
  v-inject="project-layout"
  ...
/>

<.vue
  v-component="live/flow/show/Panels"
  v-inject:panels="project-layout"
  ...
/>
</ProjectLayout.project_layout>
```

Target Vue slots:

```txt
project layout slots:
  top-left
  top-right
  sidebar
  default / main
  panels
  overlay
```

The exact slot names should be shared by all project tools.

### Compare Layout

Routes:

- sheet compare
- flow compare
- scene compare
- version viewers

Recommended pattern:

- Dedicated `live/layouts/compare/Layout.vue`.
- Not part of project tool chrome.
- No persistent project toolbar.

Reason:

Compare is an immersive inspection surface. It needs consistency across entity types, not with the normal editor chrome.

### Immersive Layout

Routes:

- flow player
- scene exploration
- other future fullscreen experiences

Recommended pattern:

- Dedicated `live/layouts/immersive/Layout.vue`.
- Usually not sticky.
- Minimal or no shell chrome.

Reason:

Players and exploration modes are product modes, not ordinary project tool pages.

## Public Boundary Rules

Elixir may render only:

- `assets/app/live/layouts/**`
- `assets/app/live/<domain>/<route-or-mode>/**` public page boundaries
- `assets/app/shell/**` only during transition, until moved into `live/layouts/**`
- explicit shared exceptions such as `components/LucideIcon`

Elixir must not render:

- `assets/app/modules/**`
- `assets/app/components/**`, except explicitly approved global primitives
- domain internals such as docks, individual toolbars, tree nodes, block components, canvas layers, or panels nested inside module internals

Naming convention:

- Layout boundaries: `live/layouts/<family>/Layout`
- Route/page boundaries: `live/<domain>/<route-or-mode>/<Boundary>`
- Tool editors:
  - `Header`
  - `Surface`
  - `Panels`
  - `Dashboard`
  - `Sidebar`
  - `CompactSurface` only for compare/viewer mode

Avoid generic component names under `live/**` unless the path makes the route family unambiguous.

## Elixir Responsibilities

Elixir should:

- choose the route layout family
- load current scope, workspace, project, membership, permissions
- provide route-safe URLs via `~p`
- serialize props for public Vue boundaries
- own LiveView events and PubSub subscriptions
- mount sticky layout LiveViews where persistent server-backed state is required
- inject page boundaries into layout slots

Elixir should not:

- hand-build visual layout chrome repeatedly in HEEx
- render internal Vue components
- duplicate header/sidebar implementations per feature
- pass large unshaped structs when a smaller serialized prop contract is enough

## Vue Responsibilities

Vue should:

- own visual layout composition
- preserve client-side layout state where the layout stays mounted
- compose domain internals from `assets/app/modules/**`
- expose only route/page boundaries under `assets/app/live/**`
- provide consistent chrome primitives for route families

Vue should not:

- import project-domain modules into global shell/layouts unless the dependency direction is intentional and documented
- require Elixir to render small internal chrome pieces directly
- hide route-level server state in global client stores without a clear contract

## Suggested Implementation Phases

### Phase 0: Deep Inventory And Contract Lock

Status: done.

Goal:

Freeze the target API before moving code.

Tasks:

- inventory every `Layouts.*`, `ProjectShell.project_shell`, and `v-component`
- classify routes into layout families
- list current per-layout state and events
- define slot names for `project`, `app/settings`, `docs`, `compare`, `immersive`
- update `arch:live-vue` rules to understand `live/layouts/**`

Output:

- accepted route-family matrix
- accepted slot contract
- no functional changes

### Phase 1: Project Tools Spike

Status: done.

Goal:

Implement the new pattern in the highest-value area without migrating every domain at once.

Recommended vertical slice:

- project tools layout
- flow show route first

Why flow first:

- flows already went through the `Header` / `Surface` / `Panels` architectural pass
- it has meaningful canvas chrome, panels, and sidebar state
- it is representative enough to reveal bottlenecks

Tasks:

- create `ProjectLayout` HEEx component
- create `live/layouts/project/Layout.vue`
- move project shell chrome from `assets/app/shell/**` into layout-owned public/private components
- inject flow `Header`, `Surface`, and `Panels` into stable slots
- preserve current behavior and event contracts
- browser-test normal flow editor, compare route, sidebar, presence, debug panel

Exit criteria:

- normal flow route works with the new persistent layout
- no duplicated chrome
- no internal `modules/**` component rendered from Elixir
- architecture checker passes

### Phase 2: Project Tools Rollout

Status: partially done.

Goal:

Move the rest of project tool pages to the same layout slot contract.

Completed:

- flows dashboard/show
- sheets dashboard/show
- scenes dashboard
- assets dashboard
- localization report/texts/edit
- project dashboard

Remaining:

1. `SceneLive.Show`
2. remove `ProjectShell`
3. normalize project layout navbar height
4. decide and implement generic project-layout flash/toast behavior

Reason:

Sheets and scenes are closest to flows and validate document/canvas variants. Assets/localization/project dashboard validate non-canvas project pages.

`SceneLive.Show` should be the next implementation target. It is the only normal
project editor route still using `ProjectShell`. The migration should:

- replace `ProjectShell.project_shell` with `ProjectLayout.project_layout`
- inject `live/scene/show/Header` into `top-left`
- inject `live/scene/show/HeaderActions` into `top-right`
- inject `live/scene/show/Surface` into the default project slot
- inject `live/scene/show/Panels` into `panels`
- move visual upload prompt, drop overlay, and progress UI into `Surface.vue`
- keep the hidden `<.live_file_input>` in HEEx if LiveView upload requires it
- pass the upload ref to Vue so `Surface.vue` can own `phx-drop-target`
- mount the scenes collab toast inside `Surface.vue`, matching flows and sheets

The risky point is LiveView upload integration through a Vue-rendered drop
target. It must be browser-tested with background upload and drag/drop.

### Phase 3: Compare And Immersive Layouts

Status: pending.

Goal:

Make non-standard fullscreen modes explicit.

Tasks:

- create `live/layouts/compare/Layout.vue`
- create `live/layouts/immersive/Layout.vue`
- migrate compare/version viewer/player/exploration routes
- keep them outside project tool chrome unless explicitly needed

### Phase 4: App / Workspace / Settings Layout

Status: partially done.

Goal:

Unify authenticated non-tool pages.

Completed:

- `live/layouts/workspace/Layout.vue`
- `live/layouts/settings/Layout.vue`
- unified authenticated app `live_session`
- workspace dashboard now uses `WorkspaceScope` assigns instead of duplicating workspace lookup

Remaining:

- replace `WorkspaceLive.New` usage of `Layouts.app`
- replace `ProjectLive.Trash` usage of `Layouts.app`; trash should live under the settings convention
- decide whether a larger `app` layout family is still needed or whether `workspace` and `settings` are sufficient

### Phase 5: Public / Auth / Docs

Status: partially done.

Goal:

Finish consistency for lower-risk families.

Completed:

- migrate auth layout
- migrate docs layout as a thin Elixir data boundary plus `live/layouts/docs/Layout`

Remaining:

- migrate public layout
- decide whether docs uses sticky `v-inject` based on sidebar/search state requirements

## Risks

### Sticky Session Is Frozen

Sticky LiveView session data is used at mount. Changes after navigation should be sent through PubSub or LiveView updates, not assumed to re-enter through `session`.

Mitigation:

- route pages broadcast active entity changes
- sticky child LiveViews own persistent server-backed shell state
- page LiveViews own page data

### Multiple Slot Owners

LiveVue allows one component per target slot. If two components inject into the same slot, the last one wins.

Mitigation:

- define a fixed slot contract
- each route renders at most one boundary per slot
- if a slot needs multiple pieces, create one boundary component that composes them

### Over-Persisting Layouts

Not every layout should be sticky. Sticky adds a LiveView process and a state ownership decision.

Mitigation:

- project tools: public Vue layout boundary, sticky child LiveViews where useful
- app/workspace/settings: likely sticky
- docs: optional
- public/auth/immersive/compare: not sticky by default

### Layouts Depending On Domains

Global layouts should not import domain internals. Project layout may know about project chrome, but it should not import sheet/flow/scene internals.

Mitigation:

- project page boundaries are injected into slots
- domain internals stay inside `modules/<domain>`
- layout components accept generic props and slots

### SSR And Hydration

Injected components compose into SSR HTML initially, then update through LiveView patches. Stable IDs are required.

Mitigation:

- every layout injection target uses an explicit stable `id`
- injected boundaries also use explicit stable IDs
- avoid duplicate IDs across compare/viewer/normal routes

## Verification Strategy

Per phase:

- `npm run arch:live-vue`
- `npm run arch`
- `npm run lint`
- `npm run fmt:check`
- targeted `mix test` for touched LiveViews
- browser smoke tests for each migrated route family

For project tools specifically:

- flow dashboard
- flow show
- sheet dashboard
- sheet show
- scene dashboard
- scene show
- assets
- localization report/texts/edit
- compare routes
- player/exploration routes

## First Implementation Recommendation

The project-tools spike has already validated the pattern.

Next implementation sequence:

1. Migrate `SceneLive.Show` from `ProjectShell` to `ProjectLayout`.
2. Browser-test scene editor:
   - normal render
   - canvas render
   - header and header actions
   - sidebars
   - panels
   - background upload
   - background drag/drop
   - route changes between scene ids
3. Remove or block `ProjectShell`.
4. Move `ProjectLive.Trash` to the settings layout convention.
5. Move `WorkspaceLive.New` out of `Layouts.app`.
6. Add an architecture check for layout usage:
   - no `ProjectShell.project_shell`
   - no `Layouts.app` in app LiveViews
   - project tool routes use `ProjectLayout`
7. Then migrate `compare`, `immersive`, `public`, and `docs` as separate route-family phases.

Do not start the next work item by migrating public/docs. The most valuable
consistency gap is still inside authenticated app routes, especially
`SceneLive.Show` and the remaining `Layouts.app` consumers.

## Implementation Readiness

The high-level architecture is clear enough to start planning implementation.

Before writing the first code change, one more focused inventory is still worth doing:

- exact current props/events used by `ProjectShell`
- exact props/events used by `LeftToolbar`, `RightToolbar`, and the tool sidebars
- which state belongs in `ProjectLayoutLive` vs each page LiveView
- current browser behavior that must be preserved for Flow show
- tests that assert current LiveVue component names

This is not open-ended research. It is a bounded pre-flight for the first vertical slice.
