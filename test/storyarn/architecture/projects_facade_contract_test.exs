defmodule Storyarn.Architecture.ProjectsFacadeContractTest do
  use ExUnit.Case, async: true

  alias Storyarn.Projects

  @public_contract [
    accept_invitation: 2,
    archive_project_template: 2,
    asset_content_type_allowed?: 1,
    asset_upload_purpose_supported?: 1,
    authorize: 3,
    authorize_asset_download: 2,
    auto_versioning_enabled?: 2,
    can?: 2,
    can_manage_project_template?: 2,
    can_publish_project_template?: 2,
    canonical_storage_key?: 1,
    cancel_invitation_delivery: 1,
    cancel_project_import: 2,
    cancel_project_snapshot: 3,
    cancel_workspace_snapshot_upload: 3,
    change_new_project: 0,
    change_new_project: 1,
    change_new_project: 2,
    change_project: 1,
    change_project: 2,
    check_invitation_rate: 2,
    count_assets: 1,
    count_assets: 2,
    count_assets_by_type: 1,
    count_project_export_entities: 2,
    create_admin_invitation: 3,
    create_admin_invitation: 4,
    create_asset_from_blob: 5,
    create_asset_from_blob: 6,
    create_binary_asset: 3,
    create_binary_asset: 4,
    create_generated_asset: 3,
    create_generated_asset: 4,
    create_invitation: 3,
    create_invitation: 4,
    create_membership: 3,
    create_project: 2,
    create_sanitized_svg_asset: 3,
    create_sanitized_svg_asset: 4,
    delete_project: 2,
    delete_project_snapshot: 3,
    delete_project_template: 2,
    delete_retention_candidate: 2,
    deleted_items_retention_cutoff: 0,
    deliver_invitation_email: 2,
    dismiss_project_template_installation_failure: 3,
    effective_role: 2,
    enqueue_project_import: 3,
    enqueue_project_import: 4,
    export_portable_project_template: 2,
    export_portable_project_template: 3,
    external_project_storage?: 0,
    get_asset: 2,
    get_asset_family_usages: 2,
    get_deleted_project: 2,
    get_flow_including_deleted: 2,
    get_invitation_by_token: 1,
    get_membership: 2,
    get_pending_invitation: 1,
    get_project: 2,
    get_project!: 1,
    get_project_by_slugs: 3,
    get_project_import_attempt: 2,
    get_project_snapshot_reconciliation_run: 1,
    get_project_template: 2,
    get_project_template: 3,
    get_scene_brief: 2,
    get_scene_including_deleted: 2,
    get_trashed_sheet: 2,
    import_error_deduplicator_child_spec: 0,
    import_portable_project_template: 1,
    import_portable_project_template: 2,
    inspect_asset_upload: 3,
    list_active_project_template_installations: 2,
    list_active_workspace_template_installations: 2,
    list_assets: 1,
    list_assets: 2,
    list_deleted_items: 1,
    list_deleted_items: 2,
    list_deleted_items_for_retention: 0,
    list_deleted_items_for_retention: 1,
    list_deleted_projects: 1,
    list_flow_dashboard_health_findings: 1,
    list_image_asset_ids: 1,
    list_pending_invitations: 1,
    list_pending_project_template_installation_failures: 2,
    list_pending_workspace_template_installation_failures: 2,
    list_project_export_formats: 0,
    list_project_members: 1,
    list_project_snapshot_reconciliation_findings: 1,
    list_project_snapshot_reconciliation_findings: 2,
    list_project_snapshot_reconciliation_repairs: 1,
    list_project_snapshot_reconciliation_repairs: 2,
    list_project_snapshot_restores: 1,
    list_project_snapshot_restores: 2,
    list_project_snapshots: 1,
    list_project_snapshots: 2,
    list_project_template_installs: 2,
    list_project_template_installs: 3,
    list_project_template_publications: 1,
    list_project_template_publications: 2,
    list_project_template_versions: 2,
    list_project_templates: 1,
    list_project_templates: 2,
    list_project_variable_usages: 2,
    list_project_variable_usages: 3,
    list_projects: 1,
    list_projects_for_workspace: 2,
    list_scene_dashboard_health_findings: 1,
    list_sheet_dashboard_health_findings: 1,
    list_sheet_dashboard_health_findings: 2,
    list_workspace_snapshot_imports: 2,
    link_asset_variant: 3,
    lock_and_check_workspace_capacity: 1,
    materialize_asset_upload_variant: 3,
    max_sync_project_export_bytes: 0,
    move_asset_to_trash: 3,
    new_project: 0,
    paginate_deleted_items: 1,
    paginate_deleted_items: 2,
    paginate_project_templates: 1,
    paginate_project_templates: 2,
    parse_asset_upload_purpose: 1,
    permanently_delete_project: 1,
    permanently_delete_trashed_flow: 1,
    permanently_delete_trashed_flow: 2,
    permanently_delete_trashed_scene: 1,
    permanently_delete_trashed_scene: 2,
    permanently_delete_trashed_sheet: 1,
    plan_project_snapshot_reconciliation_repairs: 1,
    plan_project_snapshot_reconciliation_repairs: 2,
    prepare_external_workspace_snapshot_import: 3,
    prepare_project_export: 3,
    prepare_project_import: 4,
    prepare_project_import: 5,
    prepare_workspace_data_hard_delete: 1,
    prepare_workspace_data_hard_delete: 2,
    preview_portable_project_template: 1,
    preview_portable_project_template: 2,
    project_classification_options: 0,
    project_asset_route_key?: 2,
    project_export_options: 1,
    project_import_active_statuses: 0,
    project_import_resume_storage_key: 2,
    project_media_route_key?: 2,
    project_snapshot_accounting: 2,
    project_snapshot_archive_max_size_bytes: 0,
    project_snapshot_build_statuses: 1,
    project_snapshot_reconciliation_repair_page_limit: 0,
    project_snapshot_restore_enabled?: 0,
    project_stats: 1,
    project_theme_colors: 1,
    publish_committed_workspace_data_hard_delete: 1,
    purge_asset_trash_candidate: 2,
    purge_trashed_asset: 4,
    purge_trashed_assets: 3,
    ready_project_snapshot_archive_key?: 3,
    recent_activity: 1,
    recent_activity: 2,
    register_materialized_asset: 3,
    register_uploaded_asset: 4,
    reload_project: 2,
    remove_member: 3,
    repair_stale_project_variable_references: 2,
    request_full_project_snapshot: 3,
    request_project_snapshot_restore: 4,
    request_project_template_instantiation: 5,
    request_project_template_publication: 3,
    request_project_template_version_publication: 4,
    request_stored_workspace_snapshot_import: 3,
    request_workspace_snapshot_import: 4,
    resolve_project_import_review: 4,
    restore_trashed_asset: 4,
    restore_trashed_flow: 2,
    restore_trashed_scene: 1,
    restore_trashed_sheet: 1,
    resume_latest_active_project_import: 2,
    resume_latest_active_project_import: 3,
    resume_project_import: 3,
    resume_project_import: 4,
    revoke_invitation: 3,
    run_asset_materialization_scope: 2,
    run_snapshot_archive_smoke!: 1,
    save_project_import_review: 3,
    sheet_referenced_block_ids: 1,
    slugify_project_name: 1,
    start_project_snapshot_reconciliation: 0,
    start_project_snapshot_reconciliation: 1,
    storage_provider_namespace_fingerprint: 0,
    subscribe_project_imports: 1,
    subscribe_project_ownership_changes: 1,
    subscribe_project_snapshot_restores: 1,
    subscribe_project_snapshots: 1,
    subscribe_project_template_publications: 1,
    subscribe_user_template_installations: 1,
    subscribe_workspace_snapshot_imports: 1,
    subscribe_workspace_template_installations: 2,
    tool_health_summary: 1,
    touch_project: 1,
    touch_project: 2,
    transfer_owner: 3,
    unarchive_project_template: 2,
    update_member_role: 4,
    update_project: 3,
    update_project_import_mode: 3,
    update_project_import_strategy: 3,
    update_workspace_snapshot_upload_progress: 4,
    upload_asset: 4,
    upload_asset: 5,
    upload_binary_asset: 4,
    upload_binary_asset_for_purpose: 4,
    valid_project_export_formats: 0,
    validate_project_email_format: 1,
    validate_project_export: 1,
    validate_project_export: 2,
    version_control_settings_updated: 3,
    with_asset_copy_tracker: 2,
    with_authorized_project_snapshot_download: 4,
    with_project_storage_lock: 2
  ]

  @worker_contract [
    advance_project_snapshot_reconciliation: 2,
    delete_expired_project_snapshot_build_candidate: 1,
    delete_project_snapshot_retention_candidate: 1,
    delete_storage_keys: 1,
    discard_stale_project_snapshot_maintenance_jobs: 0,
    enqueue_due_cleanup_request_jobs: 0,
    emit_storage_cleanup_request_backlog: 0,
    expire_stale_imports_batch: 0,
    fail_project_snapshot_reconciliation: 3,
    fail_project_snapshot_reconciliation_repair: 2,
    heartbeat_project_snapshot_build: 2,
    inspect_storage_multipart_inventory: 0,
    list_abandoned_project_snapshot_restore_deliveries: 1,
    list_expired_project_snapshot_build_candidates: 2,
    list_project_snapshot_cleanup_recovery_candidates: 1,
    list_project_snapshot_retention_candidates: 2,
    perform_import: 2,
    perform_project_snapshot_build: 2,
    perform_project_snapshot_reconciliation_repair: 1,
    perform_project_snapshot_restore: 3,
    perform_template_artifact_gc: 1,
    perform_template_installation: 2,
    perform_template_publication: 2,
    perform_workspace_snapshot_import: 2,
    persist_cleanup_request: 1,
    process_project_snapshot_cleanup_intent: 2,
    project_snapshot_build_heartbeat_interval_ms: 0,
    project_snapshot_build_recovery_quarantine_seconds: 0,
    project_snapshot_cleanup_backlog: 0,
    project_snapshot_cleanup_operator_action: 1,
    project_snapshot_cleanup_recovery_high_watermark: 0,
    project_snapshot_export_lease_retention_seconds: 0,
    project_snapshot_lifecycle_high_watermark: 0,
    project_snapshot_reconciliation_metrics_child_specs: 1,
    project_snapshot_reconciliation_repair_recovery_high_watermark: 0,
    project_snapshot_restore_delivery_recovery_high_watermark: 0,
    purge_released_project_snapshot_export_leases: 2,
    reconcile_abandoned_workspace_snapshot_import_deliveries: 1,
    reconcile_stale_project_snapshot_builds: 0,
    recover_abandoned_project_snapshot_restore_delivery: 1,
    recover_expired_project_snapshot_export_leases: 2,
    recover_project_snapshot_cleanup_intent: 1,
    recover_project_snapshot_reconciliation_repair_delivery_page: 1,
    replay_terminal_project_snapshot_cleanup: 1,
    rescue_stale_project_snapshot_cleanup_jobs: 0,
    retry_persisted_cleanup_request_by_id: 1,
    retry_persisted_cleanup_requests: 0
  ]

  @public_types ~w(action attrs changeset invitation membership project role scope user)a
  @comment_contract [
    list_flow_comment_threads: 3,
    list_flow_comment_threads: 4,
    list_scene_comment_threads: 3,
    list_scene_comment_threads: 4,
    get_comment_thread: 3,
    get_comment_thread: 4,
    create_flow_node_comment: 5,
    create_flow_canvas_comment: 4,
    create_scene_canvas_comment: 4,
    move_comment_thread: 5,
    list_flow_comment_pins: 3,
    list_scene_comment_pins: 3,
    reply_to_comment_thread: 4,
    set_comment_thread_status: 5,
    list_comment_members: 2,
    flow_comment_counts: 3,
    comment_destination: 3,
    comment_destinations: 2,
    subscribe_flow_comments: 3,
    unsubscribe_flow_comments: 2,
    subscribe_scene_comments: 3,
    unsubscribe_scene_comments: 2
  ]
  @docs_digest "97d4e95d55529373850e175b9ee37ebd5919fd3f2c1c82b7b903d923255a9ba4"
  @types_digest "f7f60ba66ab4261d3cc675ac4fac9ad00574aab9af5b64425cf8497175a7f9f8"
  @specs_digest "0e2ca5f35a9a51106f384b5f633a32ea0bd7c364cea1f4c48b8c5c24f7fa9c94"

  test "the root facade preserves every established function and arity" do
    expected = MapSet.new(@public_contract ++ @worker_contract ++ @comment_contract)
    assert :functions |> Projects.__info__() |> MapSet.new() == expected
  end

  test "the compiled facade preserves docs and semantic default signatures" do
    assert {:docs_v1, _, _, _, _, _, entries} = Code.fetch_docs(Projects)

    function_docs =
      Enum.flat_map(entries, fn
        {{:function, name, arity}, _, signatures, doc, metadata} ->
          [{name, arity, signatures, doc, Map.get(metadata, :defaults, 0)}]

        _other ->
          []
      end)

    established_keys = MapSet.new(@public_contract)
    worker_keys = MapSet.new(@worker_contract)

    established_docs =
      Enum.filter(function_docs, fn {name, arity, _signatures, _doc, _defaults} ->
        MapSet.member?(established_keys, {name, arity})
      end)

    worker_docs =
      Enum.filter(function_docs, fn {name, arity, _signatures, _doc, _defaults} ->
        MapSet.member?(worker_keys, {name, arity})
      end)

    assert length(established_docs) == 186

    assert Enum.frequencies_by(established_docs, &doc_status/1) ==
             %{documented: 76, hidden: 16, none: 94}

    assert length(worker_docs) == 47
    assert Enum.all?(worker_docs, &(doc_status(&1) == :hidden))

    assert digest(Enum.sort(established_docs)) == @docs_digest
  end

  test "the compiled facade preserves public types" do
    assert {:ok, types} = Code.Typespec.fetch_types(Projects)

    type_names =
      types
      |> Enum.map(fn {_kind, {name, _definition, _args}} -> name end)
      |> Enum.sort()

    normalized_types =
      types
      |> Enum.map(fn {kind, type} ->
        {kind, type |> Code.Typespec.type_to_quoted() |> Macro.to_string()}
      end)
      |> Enum.sort()

    assert type_names == Enum.sort(@public_types)
    assert digest(normalized_types) == @types_digest
  end

  test "the compiled facade preserves every established public spec" do
    assert {:ok, specs} = Code.Typespec.fetch_specs(Projects)

    normalized_specs =
      specs
      |> Enum.flat_map(fn {{name, arity}, definitions} ->
        Enum.map(definitions, fn definition ->
          quoted = Code.Typespec.spec_to_quoted(name, definition)
          {name, arity, Macro.to_string(quoted)}
        end)
      end)
      |> Enum.sort()

    assert length(normalized_specs) == 41
    assert digest(normalized_specs) == @specs_digest
  end

  test "workspace snapshot import entry points preserve the root facade's ID-only contract" do
    workspace = %{id: 123}

    assert Projects.request_workspace_snapshot_import(:scope, workspace, "/tmp/upload.zip", %{}) ==
             {:error, :invalid_snapshot_import_request}

    assert Projects.prepare_external_workspace_snapshot_import(:scope, workspace, %{}) ==
             {:error, :invalid_snapshot_import_request}

    assert Projects.request_stored_workspace_snapshot_import(:scope, workspace, 456) ==
             {:error, :invalid_snapshot_import_request}

    assert Projects.update_workspace_snapshot_upload_progress(:scope, workspace, 456, 10) ==
             {:error, :workspace_snapshot_upload_not_found}

    assert Projects.cancel_workspace_snapshot_upload(:scope, workspace, 456) ==
             {:error, :workspace_snapshot_upload_not_found}

    assert Projects.list_workspace_snapshot_imports(:scope, workspace) == []
  end

  defp doc_status({_name, _arity, _signatures, doc, _defaults}) do
    case doc do
      :hidden -> :hidden
      :none -> :none
      %{} -> :documented
    end
  end

  defp digest(term) do
    :sha256
    |> :crypto.hash(:erlang.term_to_binary(term))
    |> Base.encode16(case: :lower)
  end
end
