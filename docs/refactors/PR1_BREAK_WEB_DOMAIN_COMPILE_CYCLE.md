# PR1 - Break the Web/Domain Compile Cycle

## Goal

Remove the current `compile-connected` cycle that pulls web, email, and domain modules into a single recompilation ring. This PR must reduce structural coupling without changing product behavior.

The baseline problem is visible with:

```bash
mix xref graph --format cycles --label compile-connected
mix xref graph --format stats --label compile-connected
```

At planning time this reports a single cycle of `234` files.

## Why This PR Exists

The current cycle is driven by three concrete patterns:

1. Global helper imports in [lib/storyarn_web.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn_web.ex#L80) pull UI components and `Layouts` into every `use StoryarnWeb, ...`.
2. Invitation configs in [lib/storyarn/projects/invitations.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/projects/invitations.ex#L8) and [lib/storyarn/workspaces/invitations.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/workspaces/invitations.ex#L8) capture email template functions at compile time.
3. [lib/storyarn/urls.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/urls.ex) still references `StoryarnWeb.Endpoint`, which keeps a domain helper tied to the web layer.

This PR fixes those three sources directly. It does not attempt wider domain redesign.

## Hard Decisions

These decisions are fixed for this PR. Do not improvise alternatives.

1. `use StoryarnWeb, :html`, `:live_view`, and `:live_component` must stop importing app-specific components globally.
2. `StoryarnWeb.Layouts` must never be aliased globally from `StoryarnWeb`.
3. Any module that needs `CoreComponents`, `TextComponents`, `UIComponents`, `Layouts`, or helper modules must import or alias them explicitly in that file.
4. `Storyarn.Urls` must not reference `StoryarnWeb.Endpoint` at all.
5. Invitation modules must not capture template functions in module attributes.
6. Email delivery stays best-effort and synchronous in this PR. No Oban migration here.
7. No route moves and no auth scope changes in this PR.

## Out of Scope

Do not include any of the following:

- Extracting a new `References` context
- Changing the semantics of invitations, auth, or email templates
- UI redesign
- New background jobs
- Refactoring domain APIs beyond what is needed to remove compile-time coupling

## Success Criteria

This PR is complete only when all of the following are true:

- `mix xref graph --format cycles --label compile-connected` no longer reports the current `234`-file cycle
- `mix precommit` passes
- Invitation acceptance, login, and the main authenticated LiveViews still work
- `Storyarn.Urls.base_url/0` resolves correctly in dev, test, and prod without referencing `StoryarnWeb.Endpoint`

## Files That Must Change

At minimum, expect changes in these files:

- [lib/storyarn_web.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn_web.ex)
- [lib/storyarn/urls.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/urls.ex)
- [lib/storyarn/projects/invitations.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/projects/invitations.ex)
- [lib/storyarn/workspaces/invitations.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/workspaces/invitations.ex)
- [lib/storyarn/shared/invitation_operations.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/shared/invitation_operations.ex)
- [lib/storyarn/shared/invitation_notifier.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/shared/invitation_notifier.ex) or its replacement if moved
- [lib/storyarn/emails/templates.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/emails/templates.ex)
- [lib/storyarn/emails/layout.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/emails/layout.ex)
- [config/config.exs](/Users/adnumaro/Work/Personal/Code/storyarn/config/config.exs)
- [config/runtime.exs](/Users/adnumaro/Work/Personal/Code/storyarn/config/runtime.exs)

Also expect explicit import cleanup in a large number of `lib/storyarn_web/components/**` and `lib/storyarn_web/live/**` modules.

## Required End State

### 1. `StoryarnWeb` becomes minimal

Update [lib/storyarn_web.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn_web.ex) so that `html_helpers/0` contains only framework-level helpers:

- `use Gettext, backend: StoryarnWeb.Gettext`
- `import Phoenix.HTML`
- `alias Phoenix.LiveView.JS`
- `verified_routes/0`
- controller helper imports already present for `:html`

It must not import:

- `StoryarnWeb.Components.CoreComponents`
- `StoryarnWeb.Components.TextComponents`
- `StoryarnWeb.Components.UIComponents`
- `StoryarnWeb.Layouts`

It must not alias any project-specific UI module.

### 2. Explicit imports in callers

Every module that previously relied on implicit imports must now declare them explicitly.

Required pattern:

```elixir
use StoryarnWeb, :live_view

import StoryarnWeb.Components.CoreComponents
import StoryarnWeb.Components.TextComponents
import StoryarnWeb.Components.UIComponents
alias StoryarnWeb.Layouts
```

Only import what the file actually uses. Do not add blanket imports if the module only needs one component.

Use compile errors to drive the cleanup:

1. Make `StoryarnWeb` minimal first.
2. Run `mix compile`.
3. Add missing imports or aliases per file.
4. Repeat until compile is clean.

Do not reintroduce a new global macro like `:app_ui` or `:html_with_components`. That would recreate the same coupling under a different name.

### 3. `Storyarn.Urls` becomes pure domain config

Update [lib/storyarn/urls.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/urls.ex) to read only:

```elixir
Application.get_env(:storyarn, :public_base_url)
```

Required behavior:

- If `:public_base_url` is set, return it exactly after trimming any trailing slash
- If not set, return `"http://localhost:4000"`

It must not:

- call `Application.get_env(:storyarn, StoryarnWeb.Endpoint, ...)`
- mention `StoryarnWeb.Endpoint`
- build URLs from endpoint config

### 4. Public base URL config source of truth

Add `:public_base_url` configuration as follows:

- In [config/config.exs](/Users/adnumaro/Work/Personal/Code/storyarn/config/config.exs), add a development-safe default:
  - `config :storyarn, :public_base_url, "http://localhost:4000"`
- In [config/runtime.exs](/Users/adnumaro/Work/Personal/Code/storyarn/config/runtime.exs), after `host` and `port` are computed for prod, also set:

```elixir
config :storyarn, :public_base_url, "https://#{host}"
```

Do not include port `:443` in the prod URL.

Do not attempt to support custom schemes here beyond the existing prod setup. This PR only needs to match current behavior.

### 5. Invitation template selection becomes runtime-only

Update both invitation config maps:

- [lib/storyarn/projects/invitations.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/projects/invitations.ex)
- [lib/storyarn/workspaces/invitations.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/workspaces/invitations.ex)

Replace:

- `template_fn: &Templates.project_invitation/6`
- `template_fn: &Templates.workspace_invitation/6`

With:

- `template_name: :project_invitation`
- `template_name: :workspace_invitation`

Remove the `Templates` alias from those files.

### 6. Invitation notifier resolves templates by name

Update the notifier layer so template resolution happens at runtime.

Required implementation shape:

- Keep the public API the same for `InvitationOperations`
- In the notifier, switch on `config.template_name`
- Resolve the concrete template with direct calls to `Storyarn.Emails.Templates`

Required mapping:

- `:project_invitation -> Templates.project_invitation/6`
- `:workspace_invitation -> Templates.workspace_invitation/6`

If an unknown template name is passed, raise immediately with a clear error. Do not silently ignore it.

### 7. Keep email rendering behavior unchanged

This PR must not change:

- email subject text
- HTML output structure
- sender resolution
- mailer adapter behavior

Only the compile-time dependency shape changes.

## Ordered Execution Plan

### Phase 0 - Baseline and safety

Run and record:

```bash
mix xref graph --format cycles --label compile-connected
mix xref graph --format stats --label compile-connected
mix compile
```

Do not start editing before saving the baseline output in the PR description.

### Phase 1 - URL decoupling

1. Update [config/config.exs](/Users/adnumaro/Work/Personal/Code/storyarn/config/config.exs)
2. Update [config/runtime.exs](/Users/adnumaro/Work/Personal/Code/storyarn/config/runtime.exs)
3. Update [lib/storyarn/urls.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/urls.ex)
4. Add or update tests for `Storyarn.Urls.base_url/0`

Verify:

```bash
mix test test/storyarn/**/*urls* test/**/*emails*
```

If no URL-specific test file exists, create one under `test/storyarn/urls_test.exs`.

### Phase 2 - Invitation config decoupling

1. Update [lib/storyarn/projects/invitations.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/projects/invitations.ex)
2. Update [lib/storyarn/workspaces/invitations.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/workspaces/invitations.ex)
3. Update the notifier implementation
4. Confirm invitation flows still build URLs via `Storyarn.Urls.base_url/0`

Verify:

```bash
mix test test/storyarn/projects* test/storyarn/workspaces* test/storyarn/accounts*
```

### Phase 3 - Shrink `StoryarnWeb`

1. Remove app-specific imports and aliases from [lib/storyarn_web.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn_web.ex)
2. Run `mix compile`
3. Fix each broken module by adding explicit imports and aliases
4. Continue until compile succeeds

When patching files:

- Prefer file-local imports over introducing new helper macros
- Keep imports near the top of the file
- Do not remove imports that are still required
- Do not reorder unrelated logic

### Phase 4 - Verify cycle removal

Run:

```bash
mix xref graph --format cycles --label compile-connected
mix xref graph --format stats --label compile-connected
mix precommit
```

If a cycle remains:

1. Use `mix xref graph --source <file> --label compile-connected`
2. Identify the remaining compile edge
3. Remove the edge in the smallest possible change

Do not merge this PR while the original large cycle still exists.

## Test Plan

Run all of these before finishing:

```bash
mix compile
mix test
mix xref graph --format cycles --label compile-connected
mix precommit
```

Also manually smoke-check if feasible:

- login page renders
- authenticated project route renders
- project invitation route renders
- workspace invitation route renders

## Commit Plan

Use this commit order inside the branch:

1. `config + urls decoupling`
2. `invitation template resolution becomes runtime-only`
3. `shrink storyarn_web global helpers`
4. `add explicit web imports after helper shrink`
5. `xref verification and cleanup`

## Reviewer Checklist

- `StoryarnWeb` no longer imports app components globally
- `Storyarn.Urls` no longer references `StoryarnWeb.Endpoint`
- invitation config maps no longer capture template functions
- no route behavior changed
- `xref` cycle output is materially improved, not just moved

## Rollback Plan

If this PR causes widespread UI breakage late in the branch:

1. Keep the URL and invitation decoupling changes
2. Revert only the `StoryarnWeb` minimization commit
3. Re-run `xref`
4. Open a smaller follow-up PR for the explicit-import migration

Do not roll back the config or invitation changes unless they are directly broken.
