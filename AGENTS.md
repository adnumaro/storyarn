This is a web application written using the Phoenix web framework.

The UI is **Vue 3 rendered through LiveVue**, not HEEx. Server-rendered HEEx is limited to the root layout, the seven layout boundary components, and public marketing/docs partials. Everything a user interacts with inside the app is a `.vue` file in `assets/app/`.

## Project-Specific Notes

**UI stack:** shadcn-vue + reka-ui over Tailwind v4. daisyUI is **gone** — no `@plugin "daisyui"`, no `btn`/`card`/`modal` classes, no themes. Theme tokens are CSS variables in `assets/css/app.css` (`:root` / `.dark`). One stale mention survives in `lib/storyarn/platform/adapters/presentation/color_utils.ex:4` (a docstring); the module itself is still used.

**Dialogs:** `assets/app/components/ConfirmDialog.vue`. **Never** `window.confirm/alert/prompt` or `data-confirm` — `mix convention.check` fails the build on those. There are no `<dialog>` elements and no `phx:show-modal` dispatch sites; the listeners in `assets/js/app.js` are vestigial.

**Convention checker:** `mix convention.check` (part of `mix precommit`) scans `lib/` for 8 rules: `raw_without_sanitizer`, `datetime_utc_now`, `facade_bypass`, `string_to_atom`, `sql_interpolation`, `put_flash_without_gettext`, `native_dialog`, `inline_slugify`. Suppress with `# storyarn:disable`, `# storyarn:disable:rule_name`, or `# storyarn:disable-start` / `-end`. Source: `lib/mix/tasks/convention_check.ex`.

**Architecture verifiers:** `pnpm arch` runs five checks — `depcruise` plus four Node scripts in `scripts/`:

| Script                           | Enforces                                                                                                                                                                                                                        |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `verify-live-vue-components.mjs` | Every `v-component=` resolves to a real `.vue`; LiveView may only mount `live/`, `shell/`, or a module's public boundary — never `components/` or a module private segment (`canvas`, `chrome`, `panels`, `services`, `lib`, …) |
| `verify-live-links.mjs`          | Every `<a>` in `components/`, `live/`, `modules/`, `shell/` is a LiveLink, external, an anchor, or carries `data-phx-link` / `data-live-link-exempt`                                                                            |
| `verify-live-sessions.mjs`       | The split `:require_authenticated_user` / `:project_scope` / `:workspace_scope` sessions stay deleted, and `live_session :authenticated_app` keeps its four `on_mount` hooks                                                    |
| `verify-live-layouts.mjs`        | `ProjectShell`, `Layouts.app` and `AppLayout` stay deleted; `Layouts.{auth,compare,docs,project,public,settings,workspace}` are rejected in favour of the concrete modules                                                      |

**E2E Tests:** `mix test.e2e` runs `test/e2e/` (`use PhoenixTest.Playwright.Case`, `@moduletag :e2e`). The alias builds assets first.

## Project guidelines

- Use `mix precommit` when you are done with all changes and fix any pending issues. It runs: `compile --warning-as-errors`, `deps.unlock --unused`, `format`, `convention.check`, `credo --strict`, `test`
- Use the already included and available `:req` (`Req`) library for HTTP requests, **avoid** `:httpoison`, `:tesla`, and `:httpc`
- The JS package manager is **pnpm**, and `package.json` lives at the **repo root**, not in `assets/`
- **Never** run `vite`, `mix assets.build`, or `mix assets.deploy` yourself

### Phoenix v1.8 guidelines

- **Always** begin a LiveView template with a concrete layout boundary module, invoked fully qualified. There is no `Layouts.app` and no nesting:

  | Surface                            | Component                                            |
  | ---------------------------------- | ---------------------------------------------------- |
  | Project tools                      | `<StoryarnWeb.Components.ProjectLayout.project>`     |
  | Workspace dashboard                | `<StoryarnWeb.Components.WorkspaceLayout.workspace>` |
  | Account/workspace/project settings | `<StoryarnWeb.Components.SettingsLayout.settings>`   |
  | Sign in / sign up / confirm        | `<StoryarnWeb.Components.AuthLayout.auth>`           |
  | Landing, blog, legal, invitations  | `<StoryarnWeb.Components.PublicLayout.public>`       |
  | Documentation                      | `<StoryarnWeb.Components.DocsLayout.docs>`           |
  | Version comparison                 | `<StoryarnWeb.Components.CompareLayout.compare>`     |

- `StoryarnWeb.Layouts` is aliased in `storyarn_web.ex`, but it now holds only `root.html.heex`, `flash_group/1`, `command_palette/1` and the SEO/PostHog helpers — no page layout functions
- `ProjectLayout.project/1` mounts sticky nested LiveViews itself: `PresenceLive` always, plus the per-tool sidebar passed as `sidebar_module` (`SheetsSidebarLive`, `FlowSidebarLive`, `SceneSidebarLive`, `LocalizationSidebarLive`, `AssetSidebarLive`, `ProjectSidebarLive`). Pass `sidebar_session` with everything that sidebar needs — it is a separate LiveView and inherits no assigns
- You are **forbidden** from calling `<.flash_group>` outside a layout boundary module. The one exception is `scene_live/exploration_live.ex:15`, a chromeless full-screen LiveView that imports it directly
- Anytime you run into errors with no `current_scope` assign: you placed the route outside `live_session :authenticated_app` or `live_session :current_user`. Fix it in the router, never by re-assigning in `mount`
- **Icons are Lucide.** In HEEx use `<.icon name="x" class="size-5" />` from `StoryarnWeb.Components.IconComponents` — but that component holds a **closed map of 12 icons** (`arrow-left`, `arrow-right`, `book-open`, `check`, `chevron-down`, `mail`, `menu`, `newspaper`, `panels-top-left`, `sparkles`, `x`). An unknown name raises at render time; add the Lucide path data to the map. In Vue use `lucide-vue-next`. **Never** Unicode emoji or hand-drawn SVGs
- **There are no form components in HEEx.** `CoreComponents` is 28 lines holding `show/2` and `hide/2` only. `<.button>`, `<.input>`, `<.modal>`, `<.table>`, `<.list>`, `<.flash>`, `<.back>`, `show_modal/1`, `hide_modal/1` and `translate_error/1` were all deleted. Build forms in Vue and push events with `useLive().pushEvent`

### JS and CSS guidelines

- **Use Tailwind CSS v4 classes** plus the shadcn-vue token variables. Tailwind v4 has no `tailwind.config.js`; `assets/css/app.css` opens with:

      @import "tailwindcss";
      @import "tw-animate-css";
      @plugin "@tailwindcss/typography";
      @source "../app";
      @source "../../lib/storyarn_web";

  Note `@source "../app"` — **not** `../js`. Vue files outside `assets/app/` will not be scanned for classes

- **Never** use `@apply` when writing raw css
- Assets are bundled by **Vite** (`phoenix_vite`), not esbuild. `assets/js/app.js` is the only entry point; it imports `assets/app/index.ts`
- LiveView hooks come from `getHooks(liveVueApp)`. There is no `assets/js/hooks/` directory — the only two hand-written hooks are `PublicMobileNavigation` and `SeoMetadata` in `assets/js/utils/`. Prefer a Vue component over a new hook
- **Never write inline `<script>` tags within templates**

### UI/UX & design guidelines

- **Produce world-class UI designs** with a focus on usability, aesthetics, and modern design principles
- Implement **subtle micro-interactions** (e.g., button hover effects, and smooth transitions)
- Ensure **clean typography, spacing, and layout balance** for a refined, premium look
- Focus on **delightful details** like hover effects, loading states, and smooth page transitions

<!-- phoenix-gen-auth-start -->

## Authentication

- **Always** handle authentication flow at the router level with proper redirects
- **Always** be mindful of where to place routes. `lib/storyarn_web/router.ex` defines:
  - A plug `:fetch_current_scope_for_user`, included in the `:browser` pipeline
  - A plug `:require_authenticated_user` that redirects to the log in page when the user is not authenticated
  - `live_session :current_user` (router.ex:368) — routes that work with or without authentication
  - `live_session :authenticated_app` (router.ex:174) — **every** authenticated LiveView: workspace dashboards, project tools, and settings share one session so navigation between them never falls back to a document reload
  - In both cases, `@current_scope` is assigned to the Plug connection and LiveView socket
- **Always let the user know in which router scope and `live_session` you are placing the route, AND SAY WHY**
- The auth layer assigns `current_scope` — it **does not assign a `current_user` assign**. Access the user as `@current_scope.user`
- Always pass `current_scope` to context modules as first argument. When performing queries, use `current_scope.user` to filter the query results
- **Never** duplicate `live_session` names, and **never** create a third one. `scripts/verify-live-sessions.mjs` fails the build if the deleted `:require_authenticated_user`, `:project_scope` or `:workspace_scope` sessions reappear

### Routes that require authentication

LiveViews that require login go inside the **existing** `live_session :authenticated_app` block. Its `on_mount` chain is ordered and load-bearing:

    live_session :authenticated_app,
      on_mount: [
        {StoryarnWeb.UserAuth, :require_authenticated},
        {StoryarnWeb.UserAuth, :load_workspaces},
        {StoryarnWeb.Live.Hooks.Onboarding, :load_onboarding},
        {StoryarnWeb.Live.Hooks.Palette, :setup_palette},
        {StoryarnWeb.Live.Hooks.ProjectScope, :load_project},
        {StoryarnWeb.Live.Hooks.WorkspaceScope, :load_workspace}
      ] do
      live "/workspaces/:workspace_slug", WorkspaceLive.Show, :show
    end

`ProjectScope` and `WorkspaceScope` are `on_mount` hooks, not live_sessions: they read `:workspace_slug` / `:project_slug` from params and assign `@project`, `@workspace`, `@membership`, `@can_edit` and `@urls`. A route naming those params gets them for free — do not re-fetch in `mount`. `StoryarnWeb.Live.Hooks.RequireFeatureFlag` is available for flag-gated routes.

Controller routes must be placed in a scope that sets the `:require_authenticated_user` plug:

    scope "/", StoryarnWeb do
      pipe_through [:browser, :require_authenticated_user]

      get "/media/assets/:id", PrivateMediaController, :asset
    end

### Routes that work with or without authentication

LiveViews that can work with or without authentication use the **existing** `:current_user` session, which also carries the public locale:

    live_session :current_user,
      session: {StoryarnWeb.PublicLocale, :session, []},
      on_mount: [
        {StoryarnWeb.UserAuth, :mount_current_scope},
        {StoryarnWeb.PublicLocale, :set_locale},
        {StoryarnWeb.UserAuth, :load_workspaces}
      ] do
      live "/", LandingLive.Index, :index, private: %{public_locale: :en}
    end

Public routes carry their locale in `private: %{public_locale: locale}`; the `en` locale is canonical and unprefixed. Sign-in and registration LiveViews live here too and redirect signed-in users with their own `on_mount` hook.

Controllers automatically have `current_scope` available if they use the `:browser` pipeline.

<!-- phoenix-gen-auth-end -->

<!-- usage-rules-start -->

<!-- phoenix:elixir-start -->

## Elixir guidelines

- Elixir lists **do not support index based access via the access syntax**

  **Never do this (invalid)**:

      i = 0
      mylist = ["blue", "green"]
      mylist[i]

  Instead, **always** use `Enum.at`, pattern matching, or `List` for index based list access, ie:

      i = 0
      mylist = ["blue", "green"]
      Enum.at(mylist, i)

- Elixir variables are immutable, but can be rebound, so for block expressions like `if`, `case`, `cond`, etc
  you _must_ bind the result of the expression to a variable if you want to use it and you CANNOT rebind the result inside the expression, ie:

      # INVALID: we are rebinding inside the `if` and the result never gets assigned
      if connected?(socket) do
        socket = assign(socket, :val, val)
      end

      # VALID: we rebind the result of the `if` to a new variable
      socket =
        if connected?(socket) do
          assign(socket, :val, val)
        end

- **Never** nest multiple modules in the same file as it can cause cyclic dependencies and compilation errors
- **Never** use map access syntax (`changeset[:field]`) on structs as they do not implement the Access behaviour by default. For regular structs, you **must** access the fields directly, such as `my_struct.field` or use higher level APIs that are available on the struct if they exist, `Ecto.Changeset.get_field/2` for changesets
- Elixir's standard library has everything necessary for date and time manipulation. Familiarize yourself with the common `Time`, `Date`, `DateTime`, and `Calendar` interfaces by accessing their documentation as necessary. **Never** install additional dependencies unless asked or for date/time parsing (which you can use the `date_time_parser` package). In this project, use `Storyarn.Platform.Shared.TimeHelpers.now/0` instead of `DateTime.utc_now()` — `convention.check` enforces it
- Don't use `String.to_atom/1` on user input (memory leak risk); `convention.check` flags every call site. Use `String.to_existing_atom/1` behind a `when field in ~w(...)` guard
- Predicate function names should not start with `is_` and should end in a question mark. Names like `is_thing` should be reserved for guards
- Elixir's builtin OTP primitives like `DynamicSupervisor` and `Registry`, require names in the child spec, such as `{DynamicSupervisor, name: MyApp.MyDynamicSup}`, then you can use `DynamicSupervisor.start_child(MyApp.MyDynamicSup, child_spec)`
- Use `Task.async_stream(collection, callback, options)` for concurrent enumeration with back-pressure. The majority of times you will want to pass `timeout: :infinity` as option

## Mix guidelines

- Read the docs and options before using tasks (by using `mix help task_name`)
- To debug test failures, run tests in a specific file with `mix test test/my_test.exs` or run all previously failed tests with `mix test --failed`
- The test port is `MIX_TEST_PORT` (default 4002), **not** `MIX_TEST_PARTITION` — that only moves the database. If 4002 is busy: `MIX_TEST_PORT=4112 MIX_TEST_PARTITION=2 mix test`. Never kill the port
- Project-specific tasks: `mix convention.check`, `mix test.e2e`, `mix storyarn.ai.diagnose`, `mix storyarn.ai.grant`, `mix storyarn.templates.export`, `mix storyarn.templates.import`
- `mix deps.clean --all` is **almost never needed**. **Avoid** using it unless you have good reason

<!-- phoenix:elixir-end -->

<!-- phoenix:phoenix-start -->

## Phoenix guidelines

- Remember Phoenix router `scope` blocks include an optional alias which is prefixed for all routes within the scope. **Always** be mindful of this when creating routes within a scope to avoid duplicate module prefixes.

- You **never** need to create your own `alias` for route definitions! The `scope` provides the alias, ie:

      scope "/admin", AppWeb.Admin do
        pipe_through :browser

        live "/users", UserLive, :index
      end

  the UserLive route would point to the `AppWeb.Admin.UserLive` module

- `Phoenix.View` no longer is needed or included with Phoenix, don't use it

<!-- phoenix:phoenix-end -->

<!-- phoenix:ecto-start -->

## Ecto Guidelines

- **Always** preload Ecto associations in queries when they'll be accessed in templates, ie a message that needs to reference the `message.user.email`
- Remember `import Ecto.Query` and other supporting modules when you write `seeds.exs`
- `Ecto.Schema` fields always use the `:string` type, even for `:text`, columns, ie: `field :name, :string`
- `Ecto.Changeset.validate_number/2` **DOES NOT SUPPORT the `:allow_nil` option**. By default, Ecto validations only run if a change for the given field exists and the change value is not nil, so such as option is never needed
- You **must** use `Ecto.Changeset.get_field(changeset, :field)` to access changeset fields
- Fields which are set programatically, such as `user_id`, must not be listed in `cast` calls or similar for security purposes. Instead they must be explicitly set when creating the struct
- **Always** filter soft-deleted rows: `where: is_nil(e.deleted_at)`
- **Never** interpolate into a query — `convention.check` flags `from x in … #{}` and `Repo.query` interpolation. Pin with `^`
- Any schema passed to Vue as a `<.vue>` prop needs `Protocol.derive(LiveVue.Encoder, …)` in `lib/storyarn_web/live_vue_encoders.ex`. Tests will not catch a missing derive

<!-- phoenix:ecto-end -->

<!-- phoenix:html-start -->

## Phoenix HTML guidelines

- Phoenix templates **always** use `~H` or .html.heex files (known as HEEx), **never** use `~E`
- Most templates in this project are Vue. Reach for HEEx only for a layout boundary or a public/docs page. If you are writing a form in HEEx, you are almost certainly in the wrong file
- When HEEx does need a form, use the imported `Phoenix.Component.form/1`, `inputs_for/1` and `to_form/2`, and write the input markup by hand — there is no `<.input>` component
- **Always** add unique DOM IDs to key elements (like forms, buttons, etc) when writing templates, these IDs can later be used in tests
- For "app wide" template imports, add them to the `html_helpers` block in `storyarn_web.ex`

- Elixir supports `if/else` but **does NOT support `if/else if` or `if/elsif`**. Never use `else if` or `elseif` in Elixir — **always** use `cond` or `case` for multiple conditionals.

  **Never do this (invalid)**:

      <%= if condition do %>
        ...
      <% else if other_condition %>
        ...
      <% end %>

  Instead **always** do this:

      <%= cond do %>
        <% condition -> %>
          ...
        <% condition2 -> %>
          ...
        <% true -> %>
          ...
      <% end %>

- HEEx require special tag annotation if you want to insert literal curly's like `{` or `}`. If you want to show a textual code snippet on the page in a `<pre>` or `<code>` block you _must_ annotate the parent tag with `phx-no-curly-interpolation`:

      <code phx-no-curly-interpolation>
        let obj = {key: "val"}
      </code>

  Within `phx-no-curly-interpolation` annotated tags, you can use `{` and `}` without escaping them, and dynamic Elixir expressions can still be used with `<%= ... %>` syntax

- HEEx class attrs support lists, but you must **always** use list `[...]` syntax. You can use the class list syntax to conditionally add classes, **always do this for multiple class values**:

      <a class={[
        "px-2 text-white",
        @some_flag && "py-5",
        if(@other_condition, do: "border-red-500", else: "border-blue-100"),
        ...
      ]}>Text</a>

  and **always** wrap `if`'s inside `{...}` expressions with parens, like done above (`if(@other_condition, do: "...", else: "...")`)

  and **never** do this, since it's invalid (note the missing `[` and `]`):

      <a class={
        "px-2 text-white",
        @some_flag && "py-5"
      }> ...
      => Raises compile syntax error on invalid HEEx attr syntax

- **Never** use `<% Enum.each %>` or non-for comprehensions for generating template content, instead **always** use `<%= for item <- @collection do %>`
- HEEx HTML comments use `<%!-- comment --%>`. **Always** use the HEEx HTML comment syntax for template comments (`<%!-- comment --%>`)
- HEEx allows interpolation via `{...}` and `<%= ... %>`, but the `<%= %>` **only** works within tag bodies. **Always** use the `{...}` syntax for interpolation within tag attributes, and for interpolation of values within tag bodies. **Always** interpolate block constructs (if, cond, case, for) within tag bodies using `<%= ... %>`.

  **Always** do this:

        <div id={@id}>
          {@my_assign}
          <%= if @some_block_condition do %>
            {@another_assign}
          <% end %>
        </div>

  and **Never** do this – the program will terminate with a syntax error:

        <%!-- THIS IS INVALID NEVER EVER DO THIS --%>
        <div id="<%= @invalid_interpolation %>">
          {if @invalid_block_construct do}
          {end}
        </div>

  <!-- phoenix:html-end -->

<!-- phoenix:liveview-start -->

## Phoenix LiveView guidelines

- **Never** use the deprecated `live_redirect` and `live_patch` functions, instead **always** use the `<.link navigate={href}>` and `<.link patch={href}>` in templates, and `push_navigate` and `push_patch` functions LiveViews
- **Avoid LiveComponents.** Only `project_live/form.ex` remains in the codebase. Render a Vue component instead
- LiveViews should be named like `AppWeb.WeatherLive`, with a `Live` suffix
- **Never** write embedded `<script>` tags in HEEx
- Every mutating `handle_event` **must** be authorized with `StoryarnWeb.Helpers.Authorize` (`with_authorization(socket, :edit_content, fn …)`). Hiding a button in Vue is not a permission check

### Rendering Vue from LiveView

- Mount with `<.vue v-component="live/…" v-socket={@socket} id="…" some-prop={…} />`. Props are kebab-case in HEEx and camelCase in the SFC's `defineProps`
- The component path must be one of `live/…`, `shell/…`, or a module's public boundary. Mounting `components/…` or a module private segment (`services`, `panels`, `chrome`, `lib`, …) fails `pnpm run arch:live-vue`
- Vue talks back through `useLive()` from `assets/app/shared/composables/useLive.ts`: `pushEvent(event, payload?, callback?, onError?)` and `handleEvent(event, cb)`. `pushEvent` **never throws** — a disconnected socket calls `onError`, so `try/catch` around it is dead code
- The `payload` argument is the only place `Record<string, unknown>` is acceptable. Everything else must be a real interface, and every SFC uses `<script setup lang="ts">`

### LiveView streams

- Streams avoid memory ballooning for long collections, but this project uses them in exactly one place (`blog_live/index.ex`) because collections are rendered by Vue. Do not introduce a stream just to render a list into a Vue component — pass a prop
- If you do use one: set `phx-update="stream"` and a DOM id on the parent, consume `@streams.name`, and use the stream id as each child's DOM id. Streams are not enumerable — to filter, refetch and re-stream with `reset: true`. Streams do not support counting or empty states; track a count in a separate assign
- **Never** use the deprecated `phx-update="append"` or `phx-update="prepend"`

### Tests

- Elixir: `Phoenix.LiveViewTest` + `LazyHTML`. Assert with `element/2` and `has_element?/2` against IDs you added, never against raw HTML
- LiveVue islands render as a placeholder div, so `has_element?` on inner Vue markup will fail. Assert the mount and its props with `LiveVue.Test.get_vue(view, name: "live/…")`
- Vue: Vitest + `@vue/test-utils` + jsdom, under `assets/app/test/` mirroring `assets/app/`. Run with `just js-test`
- Browser behaviour: `mix test.e2e`
- Run `pnpm run typecheck` (`just js-typecheck`) before claiming a frontend change compiles — Vite will happily serve type-broken code

<!-- phoenix:liveview-end -->

<!-- usage-rules-end -->

---

## Storyarn-Specific Patterns

### Quality Commands

```bash
just quality                # quality-lint, then mix test, mix test.e2e, vitest
just quality-lint           # oxfmt + oxlint --fix, typecheck, arch + knip,
                            # mix format, sobelow, convention.check, credo --strict
just js-fix                 # Oxfmt + Oxlint auto-fix
just js-typecheck           # vue-tsc --noEmit
just js-test                # Vitest
just js-grammar             # Build Lezer grammar (expression editor)
mix test --cover            # Coverage summary (threshold: 85)
```

### Current Contexts

The declared bounded contexts are listed below. The target structure gives each context a public facade at
`lib/storyarn/{context}.ex` and its business code under `lib/storyarn/{context}/`. LiveViews call the facade;
calling `Context.SubModule.fun()` from `storyarn_web` is a `facade_bypass` violation. Legacy namespaces remain
only while their owning context is being migrated.

| Bounded context | Facade                  | Owned business capabilities                                                                                                                  |
| --------------- | ----------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Accounts        | `Storyarn.Accounts`     | Users, authentication and profiles                                                                                                           |
| Workspaces      | `Storyarn.Workspaces`   | Workspaces, memberships and invitations                                                                                                      |
| Platform        | `Storyarn.Platform`     | Product metrics/event reactions, notification inbox/delivery, commercial catalog, subscriptions, entitlements and truly platform-wide policy |
| Projects        | `Storyarn.Projects`     | Project identity/lifecycle, dashboards, trash, assets, templates, project import/export, snapshots/reconstitution and AI settings            |
| Sheets          | `Storyarn.Sheets`       | Sheets, blocks, tables, galleries, formulas, variable definitions, usages and Sheet-owned AI behavior                                        |
| Flows           | `Storyarn.Flows`        | Flows, nodes, connections, sequences, evaluation, health, versioning and Flow-owned AI behavior                                              |
| Scenes          | `Storyarn.Scenes`       | Scenes, layers, zones, pins, connections, exploration, health and Scene-owned AI behavior                                                    |
| Localization    | `Storyarn.Localization` | Languages, localized texts, glossary, extraction, translation runs, reports and localization import/export                                   |
| AI              | `Storyarn.AI`           | AI policy, integrations, model/provider selection, execution, audit and future AI product behavior                                           |

AI is a bounded context, not a shared business layer. Projects remains the only writer of the current AI model,
team and configuration records until that ownership is revisited deliberately. Consuming contexts may own their
domain-specific prompts and context construction, but AI owns provider policy, execution and its growing product
behavior. Its current dependency graph is intentionally left transitional by ENG-92; that is migration state, not
permission to treat AI as a utility layer.

`Platform` is a supporting control-plane context, not an umbrella for arbitrary shared code. Mail transport remains
infrastructure, while each initiating context owns its email intent and copy. Accounts, Workspaces and Projects own
their resource-specific roles and authorization rules; Platform owns only policies that are genuinely global. The
notification inbox and delivery lifecycle belong to Platform, while producers retain the semantic decision to notify.
Platform owns catalog, subscriptions and entitlements; each consumer owns how it applies a quota to its own model.
Business contexts own the facts and payloads they emit; Platform owns the cross-cutting reaction policy. Product
analytics is best-effort. Notification and email reactions must use persisted, idempotent delivery with retries rather
than being added as synchronous callbacks to the event tracker.

### Application and infrastructure modules

Code may remain outside the nine context directories only when it is an application coordinator or a technical
adapter and owns no domain model or business rule:

- `StoryarnWeb` is the presentation adapter. It may compose public context facades but never call their internals.
- `Storyarn.Repo`, storage providers, mail delivery, PubSub/presence, telemetry, rate limiting, feature flags and
  Oban workers are infrastructure. Workers orchestrate through public facades.
- Global search, command palette and dashboard caches are application/query coordinators. They may own optimized,
  read-only projections over the shared tables, but do not own ordinary writes or domain invariants.
- `Storyarn.Shared` is restricted to small, stable technical primitives or a deliberately agreed shared kernel. It
  must never become a catch-all for business behavior.
- Historical or stable module identities such as `Storyarn.Projects.Assets`, `Storyarn.Platform.Billing`,
  `Storyarn.Platform.Emails`, `Storyarn.Platform.Notifications`, `Storyarn.Projects.References`,
  `Storyarn.Projects.Versioning`, `Storyarn.Projects.Imports`, `Storyarn.Projects.Exports` and
  `Storyarn.Projects.ProjectTemplates` are not additional bounded contexts. Ownership follows the physical capability
  boundary above, not the namespace name. `Billing` and `Notifications` remain stable identities inside their Platform
  owners and may contain capability facades; `Emails` remains a technical adapter. Project identities remain owned by
  Projects. Preserve a stable identity when compatibility requires it, while keeping its files and business decisions
  inside the owning context.

Background jobs live under `lib/storyarn/workers/{owner}/`. Each owner slice belongs to the corresponding bounded
context in the architecture ratchet; `Storyarn.Workers.*` is only the stable technical identity persisted by Oban,
not a bounded context or shared business layer. Worker implementations orchestrate through their owner's public facade.

## Event Contracts

There is no static contract table — the flow editor alone has 116 `handle_event` clauses in `show.ex` and 121 `pushEvent` call sites in Vue. The contract lives in two files and **must be read before adding an event**:

| Direction     | Source of truth                                                                               |
| ------------- | --------------------------------------------------------------------------------------------- |
| Server→Client | `assets/app/modules/flows/editor/composables/flowCanvasServerEvents.ts` — every `handleEvent` |
| Client→Server | `lib/storyarn_web/live/flow_live/show.ex` — every `handle_event`, delegating to `handlers/`   |

Server→client events the flow canvas listens for: `flow_updated`, `flow_meta_changed`, `node_added`, `node_removed`, `node_restored`, `node_updated`, `node_data_changed`, `node_moved`, `node_reparented`, `connection_added`, `connection_removed`, `connection_updated`, `sequence_renamed`, `sequence_config_updated`, `navigate_to_node`, `navigate_to_hub`, `navigate_to_jumps`, `navigate_to_connection`, `debug_highlight_node`, `debug_highlight_connections`, `debug_update_breakpoints`, `debug_clear_highlights`.

Other Vue islands register their own `handleEvent` names; grep the island's composable rather than assuming.

**A LiveView `push_event` with no matching `handleEvent` fails silently, and so does the reverse.** Land both sides in the same pass — a green `mix compile` proves nothing about a Vue listener.

### Passing Data to Vue

Data reaches Vue as **props on `<.vue>`**, not `data-*` attributes. There are no canvas data attributes (`data-flow`, `data-sheets`, `data-locks`, `data-user-id`, … were removed with the JS hooks). Any Ecto struct in a prop needs a `Protocol.derive(LiveVue.Encoder, …)` entry in `lib/storyarn_web/live_vue_encoders.ex`.

### Node Data Shape by Type

`lib/storyarn/flows/node_types.ex` is the domain source of truth for the node vocabulary, default data, form normalization and duplication semantics. `lib/storyarn_web/live/flow_live/node_type_registry.ex` maps those types to presentation modules only: labels, icons and socket/navigation behavior. Vue renders each type from `assets/app/modules/flows/editor/components/entities/nodes/{Type}Node.vue`.

| Type          | `Storyarn.Flows.NodeTypes.default_data/1`                                                                                                                                   |
| ------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `annotation`  | `%{text, color, font_size}` — `font_size` in `sm \| md \| lg`                                                                                                               |
| `entry`       | `%{}`                                                                                                                                                                       |
| `exit`        | `%{label, technical_id, outcome_tags, outcome_color, exit_mode, referenced_flow_id, target_type, target_id}` — `exit_mode` in `terminal \| flow_reference \| caller_return` |
| `dialogue`    | `%{speaker_sheet_id, text, stage_directions, menu_text, audio_asset_id, technical_id, localization_id, avatar_id, responses}`                                               |
| `hub`         | `%{hub_id, label, color}`                                                                                                                                                   |
| `condition`   | `%{condition: %{logic, rules}, switch_mode}`                                                                                                                                |
| `instruction` | `%{assignments, description}`                                                                                                                                               |
| `jump`        | `%{target_hub_id}`                                                                                                                                                          |
| `subflow`     | `%{referenced_flow_id}`                                                                                                                                                     |

A dialogue response is `%{id, text, condition, instruction, instruction_assignments}`. `annotation` and `entry` are excluded from `user_addable_types/0`.

### File Size

Nothing enforces a line limit — Credo checks line _length_ (120), not file length, and files such as `lib/storyarn/projects/assets/assets.ex`, `scene_live/show.ex` and `flow_live/show.ex` are intentionally large while they retain cohesive workflows. Treat these as direction, not gates:

- A LiveView `show.ex` should dispatch, not implement — push logic into `handlers/` (event handling, returns `{:noreply, socket}`) and `helpers/` (pure functions, no socket mutation)
- A Vue component that owns more than one concern belongs in `composables/` plus a thin SFC
- Split when a file gains a second responsibility, not when it hits a number

### AI Agent Checklist

Before changing the flow editor:

1. **Read both sides of the event** — `show.ex` and `flowCanvasServerEvents.ts`. Adding one half ships a silent no-op
2. **Check the Flow domain contract** — a new field belongs in `Storyarn.Flows.NodeTypes` and in the closed authoring operations of `Storyarn.Flows.NodeEditor`; Web must not define its defaults or mutation rules
3. **Check the Vue node component** — `entities/nodes/{Type}Node.vue` renders it
4. **Authorize the handler** — every mutating `handle_event` goes through `Authorize`
5. Run `mix compile --warnings-as-errors`, then `mix test`
6. Run `pnpm run typecheck` and `pnpm arch` for any frontend change
7. Run `mix convention.check` before you claim you are done
