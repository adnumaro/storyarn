# Project Templates - Execution Plan

**Status:** execution plan. This document describes the implementation path for
publishable, versioned project templates. It complements `OVERVIEW.md`, which is
the older product vision for feature gating by project intent.

## 1. Objective

Implement a versioned template system where users can publish normal projects as
private templates, update those template publications by creating new immutable
versions, and create new mutable projects from any allowed template version.

The system must also support an official Storyarn demo template, initially
Veilbreak, exposed through `visibility = "public"`.

Core contract:

```text
Project mutable
  -> publish
ProjectTemplate mutable metadata
  -> current_version_id
ProjectTemplateVersion immutable artifact
  -> instantiate
Project mutable
```

Rules:

- Source projects are normal mutable projects.
- `ProjectTemplate` is a mutable publication container: name, description,
  visibility, status, and `current_version_id` can change.
- `ProjectTemplateVersion` is immutable content: once published, its snapshot,
  asset manifest, checksum, counts, and audit report never change.
- Projects created from templates are normal mutable projects.
- Private templates belong to a user and can be used in any workspace where that
  user can create projects.
- `public` templates are visible to all users but are not created or edited
  through the normal UI in v1.

## 2. Phase 1 - Data Model

Create `project_templates`:

```text
id
owner_id nullable
source_project_id nullable
current_version_id nullable
name
slug
description
visibility: private | public
status: active | archived
inserted_at
updated_at
```

Create `project_template_versions`:

```text
id
project_template_id
version_number
source_project_id
snapshot_storage_key
asset_manifest_storage_key
checksum
entity_counts
audit_report
published_by_id
published_at
inserted_at
updated_at
```

Create `project_template_installs`:

```text
id
project_template_version_id
user_id
workspace_id
project_id
installed_at
inserted_at
updated_at
```

Add to `projects`:

```text
created_from_template_version_id nullable
```

Schema rules:

- `project_templates.owner_id` references users and is required for private
  templates.
- `project_templates.source_project_id` references the latest/default source
  project used for publishing, but the template must not depend on that project
  staying unchanged.
- `project_templates.current_version_id` references a template version and is
  updated only after a successful publish.
- `project_template_versions.version_number` is unique per template.
- `project_template_installs.project_id` references the created mutable project.
- `projects.created_from_template_version_id` is traceability only; it does not
  imply synchronization.

Visibility behavior:

- `private`: visible only to `owner_id`.
- `public`: visible to all authenticated users.
- In v1, `public` visibility is set manually through DB/admin operations, not through
  normal product UI.

## 3. Phase 2 - Backend Context

Create a new context:

```elixir
Storyarn.ProjectTemplates
```

Minimum public API:

```elixir
list_templates(scope, opts \\ [])
get_template!(scope, id)
create_template_from_project(scope, project, attrs)
publish_new_version(scope, template, source_project)
instantiate_template(scope, template_version, workspace, attrs)
```

Behavior:

- All APIs receive the authenticated scope and use `scope.user` for permission
  checks.
- `list_templates/2` returns private templates owned by the user plus active
  `public` templates.
- `get_template!/2` rejects private templates owned by other users.
- `create_template_from_project/3` validates source project access, runs the
  publishing pipeline, creates `project_templates`, creates version `1`, and
  sets `current_version_id`.
- `publish_new_version/3` validates template ownership and source project
  access, creates version `N + 1`, and updates `current_version_id` atomically.
- `instantiate_template/4` validates visibility, creates a new mutable project in
  the destination workspace, materializes the template version, records the
  install, and sets `projects.created_from_template_version_id`.

Permission defaults:

- A user can publish a template from a project only if they are owner or have an
  equivalent project permission already accepted by the Projects context.
- A user can instantiate a template into a workspace only if they can create a
  project in that workspace.
- A user can update a template only if they own the template.
- `public` templates are read/install-only from the normal UI.

## 4. Phase 3 - Publish Audit

Create:

```elixir
Storyarn.ProjectTemplates.Audit
```

The audit runs before every template publish. Publishing is blocked on any error.

Audit pipeline:

```text
source project
  -> build project snapshot
  -> build asset manifest
  -> recover snapshot in a transaction
  -> inspect recovered project
  -> rollback
  -> compare source/snapshot/recovered reports
```

The audit report must be serializable as JSON and saved into
`project_template_versions.audit_report`.

Audit errors:

- Active flow connections whose source or target node is missing or soft-deleted.
- Dynamic flow pins containing DB IDs that cannot be remapped.
- Subflow return pins using `exit_<old_node_id>` without a valid remap strategy.
- Referenced assets without a valid storage key or blob/copy source.
- Asset references in the recovered project that still point to the source
  project.
- Count mismatches between source project, snapshot, and recovered project.
- Invalid scene refs: `scene_pins.sheet_id`, `scene_pins.flow_id`,
  `scene_zones.target_id`.
- Localization refs that cannot be remapped to recovered entities.

Audit warnings:

- Assets present in the project library but not referenced by the template
  artifact.
- Soft-deleted entities that are intentionally excluded from snapshots.
- Source project metadata missing optional fields such as description.

The first Veilbreak audit is expected to expose current known issues:

- Chapter 2 has active connections to soft-deleted jump nodes.
- Existing subflow return pins use old DB IDs such as `exit_<node_id>`.
- Current recovery loses extra sheet avatars, sheet banners, and gallery images.
- Current scene background recovery can reference the original project asset.

## 5. Phase 4 - Template Artifact

Do not store template content in migrations or seeds.

Each `ProjectTemplateVersion` stores immutable artifacts:

```text
snapshot_storage_key
asset_manifest_storage_key
checksum
entity_counts
audit_report
```

The project snapshot must include:

- Sheets.
- Blocks.
- Table columns and rows.
- All `sheet_avatars`, not just the default avatar.
- `block_gallery_images`.
- Sheet banners.
- Flows.
- Flow nodes.
- Flow connections.
- Subflow return pins that can be remapped.
- Scenes.
- Scene layers.
- Scene pins.
- Scene zones.
- Scene annotations.
- Scene connections.
- Scene background assets.
- Scene pin icon assets.
- Scene zone label icon assets.
- Localization languages.
- Localized texts.
- Glossary entries.

The asset manifest must include all referenced assets:

```text
asset_id
filename
content_type
size
source_key
blob_hash
metadata
usage_refs
checksum
```

The manifest is a copy plan, not a reused-ID plan. Installing a template must
copy referenced assets into the destination project and store destination project
asset IDs.

Checksums:

- Compute one checksum for the normalized snapshot.
- Compute one checksum for the normalized asset manifest.
- Store a combined checksum on the template version.

## 6. Phase 5 - Snapshot And Recovery Fixes

Extend sheet snapshot/recovery:

- Capture all `sheet_avatars`, preserving `is_default` and `position`.
- Capture sheet banners.
- Capture `block_gallery_images`, including label, description, position, and
  asset reference.
- Restore avatars, banners, and gallery image rows into the destination project.

Extend asset recovery:

- Add a template clone mode that always creates destination project asset rows.
- Copy storage objects from `source_key` to a destination project key.
- Do not return the source asset ID just because that source row still exists.
- Preserve relevant metadata and `blob_hash`.

Extend flow recovery:

- Keep `r_*`, `true`, `false`, `input`, and `output` pins unchanged.
- Detect `exit_<old_node_id>` source or target pins.
- Remap `exit_<old_node_id>` to `exit_<new_node_id>` using `id_maps.node`.
- Leave unknown pin formats unchanged only if the audit marks them as safe.
- Continue remapping node data fields such as `speaker_sheet_id`,
  `location_sheet_id`, and `referenced_flow_id`.

Extend scene recovery:

- Copy scene background assets to the destination project.
- Copy scene pin icon assets to the destination project.
- Copy scene zone label icon assets to the destination project.
- Continue remapping scene pin sheet/flow refs.
- Continue remapping scene zone target refs.

Clarify recovery modes:

- Existing historical recovery can preserve old behavior where appropriate.
- Template instantiation must use a strict clone mode with no cross-project asset
  references.

## 7. Phase 6 - Publish Flows

Create new template:

```text
validate source project permission
validate template attrs
run audit
build snapshot
build asset manifest
store artifacts
create project_template
create project_template_version v1
set project_template.current_version_id = v1
return template
```

Update existing template:

```text
validate template ownership
validate source project permission
run audit
build snapshot
build asset manifest
store artifacts
create project_template_version vN+1
set project_template.current_version_id = vN+1
return template
```

Atomicity:

- If audit fails, do not write a template version.
- If artifact storage fails, do not write a template version.
- If version creation fails, do not update `current_version_id`.
- If `current_version_id` update fails, the new version must not become current.

Metadata updates:

- Template name, description, visibility, and status can be changed without
  changing any version content.
- In v1, visibility changes to or from `public` are admin-only.

## 8. Phase 7 - Instantiation

Create project from template:

```text
validate template visibility
load current version or explicit version
validate workspace project creation permission
create destination project
materialize snapshot in strict template clone mode
copy referenced assets into destination project
remap all IDs
create project_template_install
set projects.created_from_template_version_id
return project
```

Behavior:

- The created project is mutable.
- The created project is not synchronized with future template versions.
- Installs from older versions remain valid.
- A private template can be installed into any workspace where the owner can
  create projects.
- A `public` template can be installed by any authenticated user into a
  workspace where they can create projects.

Failure behavior:

- If materialization fails, rollback project creation.
- If asset copy fails, rollback project creation.
- If install tracking fails, rollback project creation.

## 9. Phase 8 - Minimal UI

Authenticated routes go inside the existing `live_session :require_authenticated_user`:

```elixir
scope "/", StoryarnWeb do
  pipe_through [:browser, :require_authenticated_user]

  live_session :require_authenticated_user,
    on_mount: [{StoryarnWeb.UserAuth, :require_authenticated}] do
    live "/templates", TemplateLive.Index, :index
    live "/templates/:id", TemplateLive.Show, :show
  end
end
```

Reason: publishing and installing templates requires a logged-in user, workspace
permissions, and `@current_scope`. Templates and LiveViews must use
`@current_scope.user`, never `@current_user`.

Project UI:

- Add `Publish as template` in project settings or project menu.
- Show the button only to users who can publish from that project.
- Use a modal with:
  - name
  - description
  - create new template
  - update existing template

Project creation UI:

- Offer `Blank project`.
- Offer `My templates`.
- Offer `Storyarn demo` when an active public template exists.

Template index:

- List private templates owned by the user.
- List active public templates.
- Show current version number and last published date.

Template show:

- Show metadata.
- Show current version.
- Show version history.
- Show `Publish new version` for owner templates.
- Show `Create project from template`.
- Show basic install history for owner templates.

UI constraints:

- Use Phoenix 1.8 layouts correctly.
- Use `@current_scope`.
- Use daisyUI and existing component patterns.
- Do not expose public template management in normal UI for v1.

## 10. Phase 9 - Veilbreak Public Demo

Veilbreak must be published from the real DB project after audit, not from seeds.

Preparation:

- Clean source data.
- Repair or explicitly exclude stale Chapter 2 connections to soft-deleted jump
  nodes.
- Ensure `project_type` and `project_subtype` are set.
- Verify sheets, flows, scenes, avatars, banners, gallery images, localization,
  and scene background survive template instantiation.

Publish process:

```text
run audit on Veilbreak source project
publish as private template first
instantiate in rollback and verify counts
mark template visibility = public manually
verify all users can list it
verify normal users cannot edit public metadata
```

Onboarding behavior:

- V1 can show `Storyarn demo` as an option in project creation.
- Automatic install for every new user can be added later after the explicit
  install path is proven stable.

## 11. Tests

Backend tests:

- Creates a private template from a project.
- Publishes a new version without mutating prior versions.
- Instantiates a project from a private template.
- Instantiates a project from a `public` template.
- Denies access to private templates owned by another user.
- Stores `projects.created_from_template_version_id`.
- Creates `project_template_installs`.

Audit tests:

- Detects active flow connections to soft-deleted nodes.
- Detects unsafe `exit_<old_id>` pins before remap support.
- Passes when `exit_<old_id>` pins remap to new exit node IDs.
- Detects referenced assets without a valid copy source.
- Detects cross-project asset refs after rollback clone.
- Reports count mismatches between source, snapshot, and recovered project.

Recovery tests:

- Restores sheet banners.
- Restores all sheet avatars.
- Restores block gallery images.
- Restores scene background as an asset owned by the destination project.
- Restores scene pin and zone icon assets as destination project assets.
- Remaps flow `referenced_flow_id`.
- Remaps `source_pin = "exit_<old_node_id>"` to the new exit node ID.
- Remaps scene pin sheet/flow refs.
- Remaps scene zone target refs.
- Restores localization refs.

UI tests:

- Publish modal renders for a project owner.
- Publish modal does not render for a user without permission.
- Create project from template creates a mutable project.
- My templates lists private templates.
- Public demo appears for all authenticated users.
- Public demo management controls do not appear in normal UI.

Validation:

- Run focused backend tests for `ProjectTemplates`.
- Run focused recovery tests for `ProjectRecovery` and snapshot builders.
- Run relevant LiveView tests.
- Run `mix precommit` before merge.

## 12. Acceptance Criteria

The implementation is complete when:

- A user can publish a project as a new private template.
- A user can update that template by publishing a new immutable version.
- Older versions remain installable and unchanged.
- Another user cannot view or install private templates they do not own.
- All authenticated users can view and install active `public` templates.
- Creating a project from a template creates a normal mutable project.
- Template instantiation records `created_from_template_version_id`.
- Template instantiation records `project_template_installs`.
- Veilbreak can be published as `public` without losing sheets, flows,
  scene refs, avatars, banners, galleries, localization, or scene assets.
- The template clone path leaves no asset refs pointing back to the source
  project.
- `mix precommit` passes.

## 13. Closed Decisions

- Execution doc path: `docs/features/project-templates/EXECUTION.md`.
- Context name: `Storyarn.ProjectTemplates`.
- `ProjectTemplate` is mutable metadata.
- `ProjectTemplateVersion` is immutable content.
- `visibility = "public"` lives on `project_templates`.
- `public` visibility is not managed through normal UI in v1.
- Created projects do not synchronize with future template versions.
- Published content is stored as artifact, not seed data.
- Veilbreak is published from the audited DB project, not from migrations.
- Template instantiation uses strict clone mode with destination-owned assets.
- Response pins such as `r_*` are stable and are not remapped.
- Subflow return pins matching `exit_<node_id>` are remapped through node ID maps.
