defmodule Storyarn.Projects do
  @moduledoc """
  The Projects context.

  Handles project management including CRUD operations, memberships,
  invitations, and authorization.

  This module is the bounded-context facade. It composes Project-owned
  capabilities while keeping their implementation roles private.
  """

  alias Storyarn.Accounts.Scope
  alias Storyarn.Accounts.User
  alias Storyarn.Projects.Access
  alias Storyarn.Projects.Assets
  alias Storyarn.Projects.Assets.Asset
  alias Storyarn.Projects.Interchange
  alias Storyarn.Projects.Lifecycle
  alias Storyarn.Projects.Overview
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.ProjectInvitation
  alias Storyarn.Projects.ProjectMembership
  alias Storyarn.Projects.ProjectTrash
  alias Storyarn.Projects.References
  alias Storyarn.Projects.SnapshotAccounting
  alias Storyarn.Projects.Templates
  alias Storyarn.Projects.Trash
  alias Storyarn.Projects.Versioning

  @doc false
  defdelegate ensure_source_language(project), to: Lifecycle

  @doc false
  defdelegate get_source_language(project_id), to: Lifecycle

  @doc false
  defdelegate change_source_language(actor_scope, project, locale_code, opts),
    to: Lifecycle

  @doc false
  defdelegate source_language_options(), to: Lifecycle

  @doc false
  defdelegate source_language_option(code, label), to: Lifecycle

  @doc "Returns the Project-owned classification options used by project forms."
  defdelegate project_classification_options(), to: Lifecycle

  # =============================================================================
  # Type Definitions
  # =============================================================================

  @type project :: Project.t()
  @type membership :: ProjectMembership.t()
  @type invitation :: ProjectInvitation.t()
  @type scope :: Scope.t()
  @type user :: User.t()
  @type changeset :: Ecto.Changeset.t()
  @type attrs :: map()
  @type role :: String.t()
  @type action :: :manage_project | :manage_members | :edit_content | :use_ai | :run_bulk_ai | :view

  @doc false
  @spec import_error_deduplicator_child_spec() :: Supervisor.child_spec()
  defdelegate import_error_deduplicator_child_spec(), to: Interchange

  # =============================================================================
  # Project CRUD
  # =============================================================================

  @doc """
  Lists all projects the user has access to (owned or as a member).
  """
  @spec list_projects(scope()) :: [project()]
  defdelegate list_projects(scope), to: Lifecycle

  @doc """
  Lists all projects in a workspace that the user has access to.

  Access is determined by:
  1. Direct project membership, OR
  2. Workspace membership (inherited access)
  """
  @spec list_projects_for_workspace(integer(), scope()) :: [project()]
  defdelegate list_projects_for_workspace(workspace_id, scope), to: Lifecycle

  @doc """
  Gets a single project by ID with authorization check.

  Returns `{:ok, project, membership}` if the user has access,
  `{:error, :not_found}` if the project doesn't exist,
  `{:error, :unauthorized}` if the user doesn't have access.
  """
  @spec get_project(scope(), integer()) ::
          {:ok, project(), membership()} | {:error, :not_found | :unauthorized}
  defdelegate get_project(scope, id), to: Lifecycle

  @doc """
  Reloads an accessible project with its Project-owned workspace read model.

  Long-lived adapters use this operation instead of coupling their refresh
  path to `Storyarn.Repo`.
  """
  @spec reload_project(scope(), integer()) ::
          {:ok, project(), membership()} | {:error, :not_found | :unauthorized}
  defdelegate reload_project(scope, id), to: Lifecycle

  @doc """
  Gets a project without authorization check.
  """
  @spec get_project!(integer()) :: project()
  defdelegate get_project!(id), to: Lifecycle

  @doc """
  Gets a project by workspace slug and project slug with authorization check.

  Returns `{:ok, project, membership}` if the user has access,
  `{:error, :not_found}` if the project doesn't exist or user doesn't have access.
  """
  @spec get_project_by_slugs(scope(), String.t(), String.t()) ::
          {:ok, project(), membership()} | {:error, :not_found}
  defdelegate get_project_by_slugs(scope, workspace_slug, project_slug), to: Lifecycle

  @doc """
  Creates a project and sets up the owner membership.

  The creating user becomes the owner of the project.
  """
  @spec create_project(scope(), attrs()) ::
          {:ok, project()}
          | {:error, changeset()}
          | {:error, :not_found | :unauthorized}
          | {:error, :limit_reached, map()}
  defdelegate create_project(scope, attrs), to: Lifecycle

  @doc false
  @spec lock_and_check_workspace_capacity(integer()) ::
          :ok | {:error, :not_found} | {:error, :limit_reached, map()}
  defdelegate lock_and_check_workspace_capacity(workspace_id), to: Lifecycle

  @doc """
  Returns a changeset for tracking project changes.
  """
  @spec change_project(project(), attrs()) :: changeset()
  defdelegate change_project(project, attrs \\ %{}), to: Lifecycle

  @doc """
  Returns a changeset for validating new project form input.
  """
  @spec change_new_project() :: changeset()
  defdelegate change_new_project(), to: Lifecycle

  @doc "Publishes the product fact for updated version control settings."
  @spec version_control_settings_updated(scope(), map(), map()) :: :ok
  defdelegate version_control_settings_updated(scope, project, attrs), to: Lifecycle

  @spec change_new_project(project(), attrs()) :: changeset()
  defdelegate change_new_project(project, attrs \\ %{}), to: Lifecycle

  @doc """
  Updates a project.
  """
  @spec update_project(project(), attrs()) :: {:ok, project()} | {:error, changeset()}
  defdelegate update_project(project, attrs), to: Lifecycle

  @doc """
  Marks a project as having content activity without changing project metadata.
  """
  @spec touch_project(integer(), DateTime.t() | nil) :: :ok
  defdelegate touch_project(project_id, at \\ nil), to: Lifecycle

  @doc """
  Soft-deletes a project.
  """
  @spec delete_project(project(), integer()) :: {:ok, project()} | {:error, changeset()}
  defdelegate delete_project(project, user_id), to: Lifecycle

  @doc """
  Permanently deletes a project (for retention cleanup).
  """
  @spec permanently_delete_project(project()) :: {:ok, project()} | {:error, changeset()}
  defdelegate permanently_delete_project(project), to: Lifecycle

  @doc """
  Lists soft-deleted projects in a workspace.
  """
  @spec list_deleted_projects(integer()) :: [project()]
  defdelegate list_deleted_projects(workspace_id), to: Lifecycle

  @doc """
  Gets a single deleted project.
  """
  @spec get_deleted_project(integer(), integer()) :: project() | nil
  defdelegate get_deleted_project(workspace_id, project_id), to: Lifecycle

  defdelegate auto_versioning_enabled?(project_id, entity_type), to: Lifecycle

  # =============================================================================
  # Project Trash
  # =============================================================================

  @doc """
  Returns a DB-paginated trash page for all project-level entities.
  """
  @spec paginate_deleted_items(integer(), keyword()) :: ProjectTrash.page()
  defdelegate paginate_deleted_items(project_id, opts \\ []), to: Trash

  @doc """
  Lists deleted project-level entities across all trash domains.
  """
  @spec list_deleted_items(integer(), keyword()) :: [ProjectTrash.deleted_item()]
  defdelegate list_deleted_items(project_id, opts \\ []), to: Trash

  @doc """
  Lists deleted project-level entities with retention metadata for cleanup jobs.
  """
  @spec list_deleted_items_for_retention(keyword()) :: [map()]
  defdelegate list_deleted_items_for_retention(opts \\ []), to: Trash
  defdelegate deleted_items_retention_cutoff(), to: Trash

  @doc false
  defdelegate delete_retention_candidate(item, delete_fun), to: Trash

  @doc false
  @spec purge_asset_trash_candidate(map(), pos_integer() | nil) ::
          {:ok, Asset.t()} | {:error, term()}
  defdelegate purge_asset_trash_candidate(item, actor_id), to: Trash

  @doc "Returns a Project-owned Flow record, including recoverable trash state."
  defdelegate get_flow_including_deleted(project_id, flow_id), to: Overview

  @doc "Restores a trashed Flow through the Project lifecycle boundary."
  defdelegate restore_trashed_flow(project_id, flow_id), to: Trash

  @doc false
  defdelegate permanently_delete_trashed_flow(flow), to: Trash

  @doc "Permanently deletes a trashed Flow through the Project lifecycle boundary."
  defdelegate permanently_delete_trashed_flow(project_id, flow_id), to: Trash

  @doc "Gets a trashed Sheet scoped to its project for the Project trash surfaces."
  defdelegate get_trashed_sheet(project_id, sheet_id), to: Trash

  @doc "Restores a trashed Sheet through the Project lifecycle boundary."
  defdelegate restore_trashed_sheet(sheet), to: Trash

  @doc "Permanently deletes a trashed Sheet through the Project lifecycle boundary."
  defdelegate permanently_delete_trashed_sheet(sheet), to: Trash

  @doc "Permanently deletes a trashed Scene through the Project lifecycle boundary."
  defdelegate permanently_delete_trashed_scene(scene), to: Trash

  @doc "Permanently deletes a trashed Scene through the Project lifecycle boundary."
  defdelegate permanently_delete_trashed_scene(project_id, scene_id), to: Trash

  @doc "Gets an active Scene projection for lightweight Project-owned surfaces."
  defdelegate get_scene_brief(project_id, scene_id), to: Overview

  @doc "Gets a Scene projection including recoverable trash state."
  defdelegate get_scene_including_deleted(project_id, scene_id), to: Overview

  @doc "Restores a trashed Scene through the Project lifecycle boundary."
  defdelegate restore_trashed_scene(scene), to: Trash

  @doc "Project-wide Sheet health findings for the dashboard."
  defdelegate list_sheet_dashboard_health_findings(project_id, referenced_ids \\ nil),
    to: Overview

  @doc "Block ids referenced by variables or table formula bindings."
  defdelegate sheet_referenced_block_ids(project_id),
    to: Overview

  @doc "Returns Project-owned dashboard health findings for all active Scenes."
  defdelegate list_scene_dashboard_health_findings(project_id),
    to: Overview

  # =============================================================================
  # Project assets
  # =============================================================================

  @doc "Lists active image asset ids available to a Project tool."
  defdelegate list_image_asset_ids(project_id), to: Assets

  @doc "Gets an active Project asset by its project-scoped identity."
  defdelegate get_asset(project_id, asset_id), to: Assets

  @doc "Consumes an uploaded file through the Project-owned asset boundary."
  defdelegate upload_asset(path, entry, project_id, uploaded_by_id, opts \\ []),
    to: Assets

  @doc "Creates an asset generated by a Project tool."
  defdelegate create_generated_asset(project_id, binary, attrs, uploaded_by_id \\ nil),
    to: Assets

  @doc "Creates an arbitrary binary Project asset."
  defdelegate create_binary_asset(project_id, binary, attrs, uploaded_by_id \\ nil),
    to: Assets

  @doc "Sanitizes and creates an SVG Project asset."
  defdelegate create_sanitized_svg_asset(project_id, binary, attrs, uploaded_by_id \\ nil),
    to: Assets

  @doc "Reconstitutes a Project asset from canonical blob content."
  defdelegate create_asset_from_blob(
                project_id,
                user_id,
                blob_hash,
                source_key,
                metadata,
                opts \\ []
              ),
              to: Assets

  @doc "Runs a Project-owned asset materialization scope."
  defdelegate run_asset_materialization_scope(opts, fun), to: Assets

  @doc "Runs asset materialization with the canonical storage compensation tracker."
  defdelegate with_asset_copy_tracker(opts, fun), to: Assets

  @doc "Runs Project asset materialization under the canonical workspace storage lock."
  defdelegate with_project_storage_lock(project_id, fun), to: Assets

  @doc false
  defdelegate new_project(), to: Lifecycle

  @doc false
  defdelegate project_theme_colors(project), to: Lifecycle

  # Public Web-facing asset operations. StoryarnWeb enters the bounded context
  # here; storage and media modules remain implementation details of Projects.
  defdelegate authorize_asset_download(scope, asset_id), to: Assets, as: :authorize_download
  defdelegate inspect_asset_upload(scope, project_id, attrs), to: Assets, as: :inspect_authorized_upload

  defdelegate materialize_asset_upload_variant(scope, project_id, attrs),
    to: Assets,
    as: :materialize_authorized_upload_variant

  defdelegate upload_binary_asset_for_purpose(scope, project_id, binary, attrs),
    to: Assets,
    as: :upload_authorized_binary_for_purpose

  defdelegate upload_binary_asset(scope, project_id, binary, attrs),
    to: Assets,
    as: :upload_authorized_binary

  defdelegate count_assets_by_type(project_id), to: Assets
  defdelegate count_assets(project_id, opts \\ []), to: Assets
  defdelegate list_assets(project_id, opts \\ []), to: Assets
  defdelegate get_asset_family_usages(project_id, asset_id), to: Assets
  defdelegate asset_content_type_allowed?(content_type), to: Assets, as: :allowed_content_type?
  defdelegate move_asset_to_trash(project_id, asset_id, actor_id), to: Assets
  defdelegate restore_trashed_asset(project_id, asset_id, generation, actor_id), to: Assets
  defdelegate purge_trashed_asset(project_id, asset_id, generation, actor_id), to: Assets
  defdelegate purge_trashed_assets(project_id, candidates, actor_id), to: Assets

  defdelegate parse_asset_upload_purpose(purpose), to: Assets
  defdelegate asset_upload_purpose_supported?(purpose), to: Assets

  defdelegate external_project_storage?(), to: Assets
  @doc false
  defdelegate canonical_storage_key?(key), to: Assets

  @doc false
  defdelegate project_asset_route_key?(project_id, key), to: Assets

  @doc false
  defdelegate project_media_route_key?(project_id, key), to: Assets

  # Project exports and imports.
  defdelegate prepare_project_export(scope, project, opts), to: Interchange, as: :prepare_download
  defdelegate validate_project_export(project_id, opts \\ %{}), to: Interchange, as: :validate_project
  defdelegate count_project_export_entities(project_id, opts), to: Interchange, as: :count_entities
  defdelegate list_project_export_formats(), to: Interchange, as: :list_formats_with_metadata
  defdelegate valid_project_export_formats(), to: Interchange, as: :valid_export_formats
  defdelegate max_sync_project_export_bytes(), to: Interchange, as: :max_sync_export_bytes
  defdelegate slugify_project_name(name), to: Lifecycle
  defdelegate project_export_options(attrs), to: Interchange, as: :export_options

  defdelegate project_import_resume_storage_key(scope, project), to: Interchange, as: :resume_storage_key
  defdelegate subscribe_project_imports(project), to: Interchange
  defdelegate get_project_import_attempt(scope, attempt_id), to: Interchange, as: :get_import_attempt
  defdelegate update_project_import_strategy(scope, attempt_id, strategy), to: Interchange, as: :update_import_strategy
  defdelegate update_project_import_mode(scope, attempt_id, mode), to: Interchange, as: :update_import_mode
  defdelegate prepare_project_import(scope, project, filename, binary), to: Interchange, as: :prepare_import
  defdelegate prepare_project_import(scope, project, filename, binary, opts), to: Interchange, as: :prepare_import
  defdelegate enqueue_project_import(scope, attempt_id, strategy), to: Interchange, as: :enqueue_import
  defdelegate enqueue_project_import(scope, attempt_id, strategy, opts), to: Interchange, as: :enqueue_import
  defdelegate save_project_import_review(scope, attempt_id, decisions), to: Interchange, as: :save_import_review

  defdelegate resolve_project_import_review(scope, attempt_id, acknowledged, decisions),
    to: Interchange,
    as: :resolve_import_review

  defdelegate resume_latest_active_project_import(scope, project),
    to: Interchange,
    as: :resume_latest_active_import

  defdelegate resume_latest_active_project_import(scope, project, opts),
    to: Interchange,
    as: :resume_latest_active_import

  defdelegate resume_project_import(scope, project, attempt_id), to: Interchange, as: :resume_import
  defdelegate resume_project_import(scope, project, attempt_id, opts), to: Interchange, as: :resume_import
  defdelegate cancel_project_import(scope, attempt_id), to: Interchange, as: :cancel_import
  defdelegate project_import_active_statuses(), to: Interchange, as: :active_import_statuses

  # Templates are a Project-owned capability, not a separate Web entry point.
  defdelegate list_project_templates(scope, opts \\ []), to: Templates, as: :list_templates
  defdelegate paginate_project_templates(scope, opts \\ []), to: Templates, as: :paginate_templates
  defdelegate get_project_template(scope, id, opts \\ []), to: Templates, as: :get_template
  defdelegate list_project_template_versions(scope, template), to: Templates, as: :list_template_versions

  @doc "Reads a portable Project template bundle without importing it."
  defdelegate preview_portable_project_template(path, opts \\ []),
    to: Templates,
    as: :preview_portable_template

  @doc "Imports a portable Project template bundle."
  defdelegate import_portable_project_template(path, opts \\ []),
    to: Templates,
    as: :import_portable_template

  @doc false
  defdelegate export_portable_project_template(project_id, output_path, opts \\ []),
    to: Templates,
    as: :export_portable_template

  defdelegate list_project_template_installs(scope, template, opts \\ []),
    to: Templates,
    as: :list_template_installs

  defdelegate list_project_template_publications(scope, opts \\ []),
    to: Templates,
    as: :list_template_publications

  defdelegate can_manage_project_template?(scope, template), to: Templates, as: :can_manage_template?

  defdelegate can_publish_project_template?(scope, project),
    to: Templates,
    as: :can_publish_source_project?

  defdelegate request_project_template_publication(scope, project, attrs),
    to: Templates,
    as: :request_template_publication

  defdelegate request_project_template_version_publication(scope, template_id, project_id, attrs),
    to: Templates

  defdelegate subscribe_project_template_publications(project_or_template),
    to: Templates,
    as: :subscribe_template_publications

  defdelegate archive_project_template(scope, template), to: Templates, as: :archive_template
  defdelegate unarchive_project_template(scope, template), to: Templates, as: :unarchive_template
  defdelegate delete_project_template(scope, template), to: Templates, as: :delete_template

  defdelegate request_project_template_instantiation(scope, template_id, version_id, workspace_id, attrs),
    to: Templates

  defdelegate list_active_workspace_template_installations(scope, workspace_id), to: Templates

  defdelegate list_pending_workspace_template_installation_failures(scope, workspace_id),
    to: Templates

  defdelegate list_pending_project_template_installation_failures(scope, template),
    to: Templates,
    as: :list_pending_template_installation_failures

  defdelegate dismiss_project_template_installation_failure(scope, workspace_id, installation_id),
    to: Templates

  defdelegate list_active_project_template_installations(scope, template),
    to: Templates,
    as: :list_active_template_installations

  defdelegate subscribe_workspace_template_installations(scope, workspace_id), to: Templates

  defdelegate subscribe_user_template_installations(scope),
    to: Templates,
    as: :subscribe_user_installations

  # Project versioning and cross-project lifecycle surfaces.
  defdelegate request_workspace_snapshot_import(scope, workspace_id, path, attrs),
    to: Versioning,
    as: :request_authorized_workspace_snapshot_import

  defdelegate prepare_external_workspace_snapshot_import(scope, workspace_id, attrs),
    to: Versioning,
    as: :prepare_authorized_external_workspace_snapshot_import

  defdelegate request_stored_workspace_snapshot_import(scope, workspace_id, import_id),
    to: Versioning,
    as: :request_authorized_stored_workspace_snapshot_import

  defdelegate update_workspace_snapshot_upload_progress(scope, workspace_id, import_id, percent),
    to: Versioning,
    as: :update_authorized_workspace_snapshot_upload_progress

  defdelegate cancel_workspace_snapshot_upload(scope, workspace_id, import_id),
    to: Versioning,
    as: :cancel_authorized_workspace_snapshot_upload

  defdelegate list_workspace_snapshot_imports(scope, workspace_id),
    to: Versioning,
    as: :list_authorized_workspace_snapshot_imports

  defdelegate subscribe_workspace_snapshot_imports(workspace_id), to: Versioning

  @doc "Starts the observation-only reconciliation of Project snapshot storage."
  defdelegate start_project_snapshot_reconciliation(opts \\ []), to: Versioning

  @doc "Gets a Project snapshot reconciliation run."
  defdelegate get_project_snapshot_reconciliation_run(run_id), to: Versioning

  @doc "Lists one bounded page of findings for a Project snapshot reconciliation run."
  defdelegate list_project_snapshot_reconciliation_findings(run_id, opts \\ []), to: Versioning

  @doc "Plans one bounded page of fenced repairs for a Project snapshot reconciliation run."
  defdelegate plan_project_snapshot_reconciliation_repairs(run_id, opts \\ []), to: Versioning

  @doc "Lists one bounded page of repair outcomes for a Project snapshot reconciliation run."
  defdelegate list_project_snapshot_reconciliation_repairs(run_id, opts \\ []), to: Versioning

  @doc "Returns the maximum repair page size accepted by Project snapshot reconciliation."
  defdelegate project_snapshot_reconciliation_repair_page_limit(), to: Versioning

  @doc "Prepares Project-owned data before its parent Workspace is hard-deleted."
  defdelegate prepare_workspace_data_hard_delete(workspace_id), to: Lifecycle

  @doc "Publishes Project lifecycle facts after the parent Workspace deletion commits."
  defdelegate publish_committed_workspace_data_hard_delete(preparation), to: Lifecycle

  defdelegate request_full_project_snapshot(scope, project, attrs), to: Versioning

  @doc false
  defdelegate run_snapshot_archive_smoke!(snapshot_id), to: Versioning

  defdelegate request_project_snapshot_restore(scope, project, snapshot, attrs), to: Versioning
  defdelegate project_snapshot_restore_enabled?(), to: Versioning
  defdelegate list_project_snapshot_restores(project_id, opts \\ []), to: Versioning
  defdelegate subscribe_project_snapshot_restores(project_id), to: Versioning
  defdelegate cancel_project_snapshot(scope, project, snapshot_id), to: Versioning
  defdelegate delete_project_snapshot(scope, project, snapshot_id), to: Versioning
  defdelegate subscribe_project_snapshots(project_id), to: Versioning
  defdelegate list_project_snapshots(project_id, opts \\ []), to: Versioning

  defdelegate with_authorized_project_snapshot_download(scope, project_id, snapshot_id, callback),
    to: Versioning

  defdelegate project_snapshot_build_statuses(snapshots), to: Versioning

  @doc "Returns the authorized Project-owned snapshot settings projection."
  @spec project_snapshot_accounting(scope(), pos_integer()) ::
          {:ok, SnapshotAccounting.accounting()} | {:error, term()}
  defdelegate project_snapshot_accounting(scope, project_id), to: Versioning

  defdelegate project_snapshot_archive_max_size_bytes(), to: Versioning

  defdelegate ready_project_snapshot_archive_key?(project_id, prefix, key), to: Versioning

  defdelegate repair_stale_project_variable_references(project_id),
    to: References,
    as: :repair_stale_variable_references

  @doc "Lists Project-owned occurrences of one Sheet variable definition."
  defdelegate list_project_variable_usages(project_id, definition, opts \\ []),
    to: References,
    as: :list_variable_usages

  defdelegate validate_project_email_format(changeset), to: Access

  # =============================================================================
  # Worker entry points
  # =============================================================================

  @doc false
  defdelegate perform_project_snapshot_build(snapshot_id, opts), to: Versioning

  @doc false
  defdelegate project_snapshot_build_heartbeat_interval_ms(), to: Versioning

  @doc false
  defdelegate heartbeat_project_snapshot_build(snapshot_id, job_id), to: Versioning

  @doc false
  defdelegate process_project_snapshot_cleanup_intent(intent_id, opts), to: Versioning

  @doc false
  defdelegate project_snapshot_cleanup_operator_action(intent_id), to: Versioning

  @doc false
  defdelegate replay_terminal_project_snapshot_cleanup(intent_id), to: Versioning

  @doc false
  defdelegate perform_template_artifact_gc(storage_keys), to: Templates

  @doc false
  defdelegate delete_storage_keys(cleanup_targets), to: Assets

  @doc false
  defdelegate persist_cleanup_request(cleanup_targets), to: Assets

  @doc false
  defdelegate expire_stale_imports_batch(), to: Interchange

  @doc false
  defdelegate perform_workspace_snapshot_import(import_id, opts), to: Versioning

  @doc false
  defdelegate perform_import(attempt_id, opts), to: Interchange

  @doc false
  defdelegate advance_project_snapshot_reconciliation(run_id, expected_generation), to: Versioning

  @doc false
  defdelegate fail_project_snapshot_reconciliation(run_id, expected_generation, reason), to: Versioning

  @doc false
  defdelegate perform_template_installation(installation_id, opts), to: Templates

  @doc false
  defdelegate discard_stale_project_snapshot_maintenance_jobs(), to: Versioning

  @doc false
  defdelegate reconcile_stale_project_snapshot_builds(), to: Versioning

  @doc false
  defdelegate reconcile_abandoned_workspace_snapshot_import_deliveries(opts), to: Versioning

  @doc false
  defdelegate recover_expired_project_snapshot_export_leases(now, opts), to: Versioning

  @doc false
  defdelegate purge_released_project_snapshot_export_leases(cutoff, opts), to: Versioning

  @doc false
  defdelegate project_snapshot_lifecycle_high_watermark(), to: Versioning

  @doc false
  defdelegate project_snapshot_restore_delivery_recovery_high_watermark(), to: Versioning

  @doc false
  defdelegate list_abandoned_project_snapshot_restore_deliveries(opts), to: Versioning

  @doc false
  defdelegate list_expired_project_snapshot_build_candidates(now, opts), to: Versioning

  @doc false
  defdelegate list_project_snapshot_retention_candidates(now, opts), to: Versioning

  @doc false
  defdelegate delete_expired_project_snapshot_build_candidate(candidate), to: Versioning

  @doc false
  defdelegate delete_project_snapshot_retention_candidate(candidate), to: Versioning

  @doc false
  defdelegate recover_abandoned_project_snapshot_restore_delivery(candidate), to: Versioning

  @doc false
  defdelegate project_snapshot_build_recovery_quarantine_seconds(), to: Versioning

  @doc false
  defdelegate project_snapshot_export_lease_retention_seconds(), to: Versioning

  @doc false
  defdelegate perform_template_publication(publication_id, opts), to: Templates

  @doc false
  defdelegate rescue_stale_project_snapshot_cleanup_jobs(), to: Versioning

  @doc false
  defdelegate project_snapshot_cleanup_recovery_high_watermark(), to: Versioning

  @doc false
  defdelegate list_project_snapshot_cleanup_recovery_candidates(opts), to: Versioning

  @doc false
  defdelegate recover_project_snapshot_cleanup_intent(intent_id), to: Versioning

  @doc false
  defdelegate project_snapshot_cleanup_backlog(), to: Versioning

  @doc false
  defdelegate project_snapshot_reconciliation_repair_recovery_high_watermark(), to: Versioning

  @doc false
  defdelegate recover_project_snapshot_reconciliation_repair_delivery_page(opts), to: Versioning

  @doc false
  defdelegate perform_project_snapshot_reconciliation_repair(action_id), to: Versioning

  @doc false
  defdelegate fail_project_snapshot_reconciliation_repair(action_id, reason), to: Versioning

  @doc false
  defdelegate perform_project_snapshot_restore(restore_id, generation, opts), to: Versioning

  @doc false
  defdelegate retry_persisted_cleanup_requests(), to: Assets

  # =============================================================================
  # Memberships
  # =============================================================================

  @doc """
  Checks if a role can perform a given action.
  """
  @spec can?(role(), action()) :: boolean()
  defdelegate can?(role, action), to: Access

  @doc """
  Resolves the effective project role from a direct project role and a
  workspace role (direct membership wins; workspace roles map to synthetic
  project roles). Returns `nil` when the user has neither.
  """
  @spec effective_role(role() | nil, String.t() | nil) :: role() | nil
  defdelegate effective_role(project_role, workspace_role), to: Access

  @doc """
  Lists all members of a project.
  """
  @spec list_project_members(integer()) :: [membership()]
  defdelegate list_project_members(project_id), to: Access

  @doc """
  Gets a membership by project and user.
  """
  @spec get_membership(integer(), integer()) :: membership() | nil
  defdelegate get_membership(project_id, user_id), to: Access

  @doc """
  Creates a membership.

  The owner membership is created only by the Project lifecycle or exact
  reconstitution. Ordinary membership operations cannot assign `owner`.
  """
  @spec create_membership(integer(), integer(), role()) ::
          {:ok, membership()} | {:error, changeset() | :cannot_assign_owner_role}
  defdelegate create_membership(project_id, user_id, role), to: Access

  @doc """
  Updates a member's role.

  Cannot change the owner's role.
  Cannot promote an ordinary membership to owner.
  """
  @spec update_member_role(membership(), role()) ::
          {:ok, membership()}
          | {:error, changeset() | :cannot_assign_owner_role | :cannot_change_owner_role}
  defdelegate update_member_role(membership, role), to: Access

  @doc """
  Removes a member from a project.

  Cannot remove the owner.
  """
  @spec remove_member(membership()) ::
          {:ok, membership()} | {:error, changeset() | :cannot_remove_owner}
  defdelegate remove_member(membership), to: Access

  @doc """
  Authorizes a user action on a project.

  Returns `{:ok, project, membership}` if authorized, `{:error, reason}` otherwise.

  ## Actions

  - `:manage_project` - update settings, delete project (owner only)
  - `:manage_members` - invite/remove members, change roles (owner only)
  - `:edit_content` - edit flows, entities (owner, editor)
  - `:view` - view project content (all roles)
  """
  @spec authorize(scope(), integer(), action()) ::
          {:ok, project(), membership()} | {:error, :not_found | :unauthorized}
  defdelegate authorize(scope, project_id, action), to: Access

  # =============================================================================
  # Invitations
  # =============================================================================

  @doc """
  Lists pending invitations for a project.
  """
  @spec list_pending_invitations(integer()) :: [invitation()]
  defdelegate list_pending_invitations(project_id), to: Access

  @doc """
  Creates an invitation and queues its email for durable delivery.

  Returns `{:ok, invitation}` on success.
  Returns `{:error, :already_member}` if the email is already a member.
  Returns `{:error, :already_invited}` if a pending invitation exists.
  Returns `{:error, :rate_limited}` if too many invitations have been sent.
  Returns `{:error, :limit_reached, details}` if the plan has no free member seats.
  Returns `{:error, :not_found}` if the project is no longer active.
  """
  @spec create_invitation(project(), user(), String.t(), role()) ::
          {:ok, invitation()}
          | {:error, :already_member | :already_invited | :rate_limited | :not_found | changeset()}
          | {:error, :limit_reached, map()}
  defdelegate create_invitation(project, invited_by, email, role \\ "editor"), to: Access

  @doc """
  Creates an admin-initiated invitation (no rate limit, no invited_by user).
  """
  @spec create_admin_invitation(project(), String.t(), String.t(), keyword()) ::
          {:ok, invitation()}
          | {:error, :already_member | :already_invited | :not_found | changeset()}
          | {:error, :limit_reached, map()}
  defdelegate create_admin_invitation(project, email, role, opts \\ []), to: Access

  @doc """
  Gets an invitation by token.

  Returns `{:ok, invitation}` if valid, `{:error, :invalid_token}` otherwise.
  """
  @spec get_invitation_by_token(String.t()) :: {:ok, invitation()} | {:error, :invalid_token}
  defdelegate get_invitation_by_token(token), to: Access

  @doc "Delivers a pending invitation email from the durable worker."
  defdelegate deliver_invitation_email(token, opts), to: Access

  @doc "Cancels a pending invitation delivery from the durable worker."
  defdelegate cancel_invitation_delivery(token), to: Access

  @doc """
  Accepts an invitation and creates a membership for the user.

  Returns `{:ok, membership}` on success.
  Returns `{:error, :email_mismatch}` if the user's email doesn't match.
  Returns `{:error, :already_member}` if the user is already a member.
  Returns `{:error, :already_accepted}` if the invitation was already accepted.
  Returns `{:error, :expired}` if the invitation has expired.
  Returns `{:error, :limit_reached, details}` if the workspace has no free member seat.
  Returns `{:error, :invitation_unavailable}` if the invitation or account disappeared while accepting.
  """
  @spec accept_invitation(invitation(), user()) ::
          {:ok, membership()}
          | {:error,
             :email_mismatch
             | :already_member
             | :already_accepted
             | :expired
             | :invitation_unavailable
             | changeset()}
          | {:error, :limit_reached, map()}
  defdelegate accept_invitation(invitation, user), to: Access

  @doc """
  Revokes a pending invitation.
  """
  @spec revoke_invitation(invitation()) :: {:ok, invitation()} | {:error, changeset()}
  defdelegate revoke_invitation(invitation), to: Access

  @doc """
  Gets a pending invitation by ID.
  """
  @spec get_pending_invitation(integer()) :: invitation() | nil
  defdelegate get_pending_invitation(id), to: Access

  @doc "Checks the Project invitation rate-limit policy."
  defdelegate check_invitation_rate(project_id, user_id), to: Access

  # =============================================================================
  # Dashboard
  # =============================================================================

  defdelegate project_stats(project_id), to: Overview

  defdelegate list_flow_dashboard_health_findings(project_id), to: Overview

  defdelegate tool_health_summary(findings_by_tool), to: Overview
  defdelegate recent_activity(project_id, limit \\ 10), to: Overview
end
