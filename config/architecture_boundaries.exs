# ENG-92 code boundaries. These rules intentionally protect code ownership only:
# they do not assign database write ownership or change the shared schema.

bounded_contexts = [:accounts, :workspaces, :platform, :projects, :sheets, :flows, :scenes, :localization]

boundaries = %{
  accounts: [
    "lib/storyarn/accounts.ex",
    "lib/storyarn/accounts/",
    "lib/storyarn_web/controllers/user_session_controller.ex",
    "lib/storyarn_web/live/user_live/",
    "lib/storyarn_web/live/settings_live/profile.ex",
    "lib/storyarn_web/live/settings_live/security.ex",
    "lib/storyarn_web/live/settings_live/sudo.ex"
  ],
  workspaces: [
    "lib/storyarn/workspaces.ex",
    "lib/storyarn/workspaces/",
    "lib/storyarn_web/live/workspace_live/",
    "lib/storyarn_web/live/settings_live/workspace_deleted_projects.ex",
    "lib/storyarn_web/live/settings_live/workspace_general.ex",
    "lib/storyarn_web/live/settings_live/workspace_imports.ex",
    "lib/storyarn_web/live/settings_live/workspace_members.ex"
  ],
  platform: [
    "lib/storyarn/platform.ex",
    "lib/storyarn/platform/",

    # Transitional locations owned by the Platform control plane. Moving them
    # under `Storyarn.Platform` is a separate migration; listing them here does
    # not turn their consumers into part of Platform.
    "lib/storyarn/billing.ex",
    "lib/storyarn/billing/",
    "lib/storyarn/emails/",
    "lib/storyarn/notifications.ex",
    "lib/storyarn/notifications/"
  ],
  sheets: [
    "lib/storyarn/sheets.ex",
    "lib/storyarn/sheets/",
    "lib/storyarn_web/live/sheet_live/",
    "lib/storyarn_web/live/sheets_sidebar_live.ex"
  ],
  flows: [
    "lib/storyarn/flows.ex",
    "lib/storyarn/flows/",
    "lib/storyarn_web/live/flow_live/",
    "lib/storyarn_web/live/flow_sidebar_live.ex"
  ],
  scenes: [
    "lib/storyarn/scenes.ex",
    "lib/storyarn/scenes/",
    "lib/storyarn_web/live/scene_live/",
    "lib/storyarn_web/live/scene_sidebar_live.ex"
  ],
  projects: [
    "lib/storyarn/projects.ex",
    "lib/storyarn/projects/",
    "lib/storyarn/assets.ex",
    "lib/storyarn/assets/",
    "lib/storyarn/references.ex",
    "lib/storyarn/references/",
    "lib/storyarn/shared/invitation_notifier.ex",
    "lib/storyarn/shared/invitation_operations.ex",
    "lib/storyarn/shared/invitation_schema.ex",
    "lib/storyarn/shared/membership_operations.ex",
    "lib/storyarn/versioning.ex",
    "lib/storyarn/versioning/",
    "lib/storyarn/exports.ex",
    "lib/storyarn/exports/",
    "lib/storyarn/imports.ex",
    "lib/storyarn/imports/",
    "lib/storyarn/project_templates.ex",
    "lib/storyarn/project_templates/",
    "lib/storyarn/workers/trash_retention_worker.ex",
    "lib/storyarn/shared/name_normalizer.ex",
    "lib/storyarn/shared/validations.ex",
    "lib/storyarn/shared/word_count.ex",
    "lib/storyarn/workers/build_project_snapshot_worker.ex",
    "lib/storyarn/workers/cleanup_project_snapshot_worker.ex",
    "lib/storyarn/workers/delete_project_template_artifacts_worker.ex",
    "lib/storyarn/workers/delete_storage_objects_worker.ex",
    "lib/storyarn/workers/expire_project_imports_worker.ex",
    "lib/storyarn/workers/import_project_snapshot_worker.ex",
    "lib/storyarn/workers/import_project_worker.ex",
    "lib/storyarn/workers/inspect_project_snapshots_worker.ex",
    "lib/storyarn/workers/install_project_template_worker.ex",
    "lib/storyarn/workers/project_snapshot_retention_worker.ex",
    "lib/storyarn/workers/publish_project_template_worker.ex",
    "lib/storyarn/workers/reconcile_project_snapshot_cleanup_worker.ex",
    "lib/storyarn/workers/reconcile_project_snapshot_repair_worker.ex",
    "lib/storyarn/workers/repair_project_snapshot_finding_worker.ex",
    "lib/storyarn/workers/restore_project_snapshot_worker.ex",
    "lib/storyarn/workers/retry_storage_cleanup_requests_worker.ex",
    "lib/storyarn_web/controllers/export_controller.ex",
    "lib/storyarn_web/controllers/private_media_controller.ex",
    "lib/storyarn_web/controllers/snapshot_download_controller.ex",
    "lib/storyarn_web/controllers/upload_controller.ex",
    "lib/storyarn_web/live/asset_live/",
    "lib/storyarn_web/live/asset_sidebar_live.ex",
    "lib/storyarn_web/live/project_live/",
    "lib/storyarn_web/live/project_settings_live/",
    "lib/storyarn_web/live/project_sidebar_live.ex",
    "lib/storyarn_web/live/compare_live/",
    "lib/storyarn_web/live/version_viewer_live.ex",
    "lib/storyarn_web/live/export_import_live/",
    "lib/storyarn_web/live/template_live/"
  ],
  localization: [
    "lib/storyarn/localization.ex",
    "lib/storyarn/localization/",
    "lib/storyarn_web/controllers/localization_export_controller.ex",
    "lib/storyarn_web/live/localization_live/",
    "lib/storyarn_web/live/localization_sidebar_live.ex",
    "lib/storyarn_web/live/localization_toolbar_live.ex",
    "lib/storyarn_web/live/project_settings_live/localization.ex"
  ],

  # Outermost Web adapters, not bounded contexts. The router and protocol
  # implementations may name context-owned modules because dependencies point
  # into the application. Every bounded context is forbidden from importing
  # these adapters, keeping Phoenix and LiveVue out of business code.
  presentation_adapters: [
    "lib/storyarn_web/router.ex",
    "lib/storyarn_web/live_vue_encoders.ex",
    "lib/storyarn_web/live_vue_encoder/"
  ],

  # Explicit technical/application namespaces, not a bounded context. There is
  # deliberately no `lib/storyarn/` catch-all: an unlisted namespace must fail
  # the checker until its ownership is reviewed. AI and global search remain
  # visible here as migration debt; they are not shared domain kernels.
  infrastructure: [
    "lib/storyarn.ex",
    "lib/storyarn/ai.ex",
    "lib/storyarn/ai/alerts.ex",
    "lib/storyarn/ai/allowance.ex",
    "lib/storyarn/ai/allowance_account.ex",
    "lib/storyarn/ai/allowance_allocation.ex",
    "lib/storyarn/ai/allowance_grant.ex",
    "lib/storyarn/ai/allowance_ledger_entry.ex",
    "lib/storyarn/ai/allowance_reservation.ex",
    "lib/storyarn/ai/audit.ex",
    "lib/storyarn/ai/audit_entry.ex",
    "lib/storyarn/ai/config_map.ex",
    "lib/storyarn/ai/context.ex",
    "lib/storyarn/ai/context/contract.ex",
    "lib/storyarn/ai/context/entity.ex",
    "lib/storyarn/ai/context/finalizer.ex",
    "lib/storyarn/ai/context/model_limits.ex",
    "lib/storyarn/ai/context/package.ex",
    "lib/storyarn/ai/context/persistence_contract.ex",
    "lib/storyarn/ai/context/policy.ex",
    "lib/storyarn/ai/context/subject_ref.ex",
    "lib/storyarn/ai/credential_ref.ex",
    "lib/storyarn/ai/credential_resolver.ex",
    "lib/storyarn/ai/credential_resolver/composite.ex",
    "lib/storyarn/ai/credential_resolver/managed.ex",
    "lib/storyarn/ai/credential_resolver/personal.ex",
    "lib/storyarn/ai/credential_resolver/unavailable.ex",
    "lib/storyarn/ai/execution.ex",
    "lib/storyarn/ai/execution_intent.ex",
    "lib/storyarn/ai/execution_route.ex",
    "lib/storyarn/ai/executor.ex",
    "lib/storyarn/ai/inference_provider.ex",
    "lib/storyarn/ai/inference_providers.ex",
    "lib/storyarn/ai/inference_providers/fake.ex",
    "lib/storyarn/ai/inference_providers/fireworks.ex",
    "lib/storyarn/ai/inference_providers/open_ai_compatible.ex",
    "lib/storyarn/ai/inference_providers/personal/anthropic.ex",
    "lib/storyarn/ai/inference_providers/personal/deep_seek.ex",
    "lib/storyarn/ai/inference_providers/personal/google.ex",
    "lib/storyarn/ai/inference_providers/personal/mistral.ex",
    "lib/storyarn/ai/inference_providers/personal/moonshot.ex",
    "lib/storyarn/ai/inference_providers/personal/open_ai.ex",
    "lib/storyarn/ai/inference_providers/together.ex",
    "lib/storyarn/ai/integration.ex",
    "lib/storyarn/ai/integration_assignments.ex",
    "lib/storyarn/ai/integration_crud.ex",
    "lib/storyarn/ai/integration_workspace_assignment.ex",
    "lib/storyarn/ai/model_catalog.ex",
    "lib/storyarn/ai/model_catalog/defaults.ex",
    "lib/storyarn/ai/model_catalog/entry.ex",
    "lib/storyarn/ai/operation.ex",
    "lib/storyarn/ai/operations.ex",
    "lib/storyarn/ai/operator_alert.ex",
    "lib/storyarn/ai/persistence/project_membership_record.ex",
    "lib/storyarn/ai/persistence/project_record.ex",
    "lib/storyarn/ai/persistence/user_record.ex",
    "lib/storyarn/ai/persistence/workspace_membership_record.ex",
    "lib/storyarn/ai/persistence/workspace_record.ex",
    "lib/storyarn/ai/personal_consent.ex",
    "lib/storyarn/ai/personal_consents.ex",
    "lib/storyarn/ai/personal_preference.ex",
    "lib/storyarn/ai/personal_preferences.ex",
    "lib/storyarn/ai/personal_providers.ex",
    "lib/storyarn/ai/personal_roles.ex",
    "lib/storyarn/ai/policy.ex",
    "lib/storyarn/ai/policy_decision.ex",
    "lib/storyarn/ai/project_access.ex",
    "lib/storyarn/ai/provider.ex",
    "lib/storyarn/ai/provider_budget.ex",
    "lib/storyarn/ai/provider_budget_reservation.ex",
    "lib/storyarn/ai/providers.ex",
    "lib/storyarn/ai/providers/anthropic.ex",
    "lib/storyarn/ai/providers/deep_l.ex",
    "lib/storyarn/ai/providers/deep_seek.ex",
    "lib/storyarn/ai/providers/google.ex",
    "lib/storyarn/ai/providers/key_validation.ex",
    "lib/storyarn/ai/providers/mistral.ex",
    "lib/storyarn/ai/providers/moonshot.ex",
    "lib/storyarn/ai/providers/open_ai.ex",
    "lib/storyarn/ai/resolved_credential.ex",
    "lib/storyarn/ai/result.ex",
    "lib/storyarn/ai/results.ex",
    "lib/storyarn/ai/route_option.ex",
    "lib/storyarn/ai/route_options.ex",
    "lib/storyarn/ai/route_resolver.ex",
    "lib/storyarn/ai/runtime.ex",
    "lib/storyarn/ai/settlement.ex",
    "lib/storyarn/ai/settlement/managed.ex",
    "lib/storyarn/ai/settlement/unavailable.ex",
    "lib/storyarn/ai/settlement_adapter.ex",
    "lib/storyarn/ai/task.ex",
    "lib/storyarn/ai/task_definition.ex",
    "lib/storyarn/ai/task_registry.ex",
    "lib/storyarn/ai/tasks/managed_diagnostic.ex",
    "lib/storyarn/ai/telemetry.ex",
    "lib/storyarn/ai/usage_event.ex",
    "lib/storyarn/ai/workspace_access.ex",
    "lib/storyarn/ai/workspace_policy.ex",
    "lib/storyarn/ai/workspace_policy_audit.ex",
    "lib/storyarn/analytics.ex",
    "lib/storyarn/analytics/",
    "lib/storyarn/application.ex",
    "lib/storyarn/architecture/",
    "lib/storyarn/assets/storage.ex",
    "lib/storyarn/assets/storage/",
    "lib/storyarn/assets/storage_hash.ex",
    "lib/storyarn/assets/storage_key_lock.ex",
    "lib/storyarn/blog.ex",
    "lib/storyarn/blog/post.ex",
    "lib/storyarn/blog/post_builder.ex",
    "lib/storyarn/collaboration.ex",
    "lib/storyarn/collaboration/",
    "lib/storyarn/command_palette.ex",
    "lib/storyarn/command_palette/definition.ex",
    "lib/storyarn/command_palette/operation.ex",
    "lib/storyarn/command_palette/persistence/user_record.ex",
    "lib/storyarn/command_palette/registry.ex",
    "lib/storyarn/dashboards/cache.ex",
    "lib/storyarn/docs.ex",
    "lib/storyarn/docs/guide.ex",
    "lib/storyarn/docs/guide_builder.ex",
    "lib/storyarn/feature_flags.ex",
    "lib/storyarn/gettext.ex",
    "lib/storyarn/global_search.ex",
    "lib/storyarn/global_search/advanced_search.ex",
    "lib/storyarn/global_search/destinations.ex",
    "lib/storyarn/global_search/flow_search.ex",
    "lib/storyarn/global_search/persistence/block_gallery_image_record.ex",
    "lib/storyarn/global_search/persistence/block_record.ex",
    "lib/storyarn/global_search/persistence/flow_connection_record.ex",
    "lib/storyarn/global_search/persistence/flow_node_record.ex",
    "lib/storyarn/global_search/persistence/flow_record.ex",
    "lib/storyarn/global_search/persistence/scene_annotation_record.ex",
    "lib/storyarn/global_search/persistence/sheet_record.ex",
    "lib/storyarn/global_search/persistence/table_column_record.ex",
    "lib/storyarn/global_search/persistence/table_row_record.ex",
    "lib/storyarn/global_search/persistence/scene_connection_record.ex",
    "lib/storyarn/global_search/persistence/scene_layer_record.ex",
    "lib/storyarn/global_search/persistence/scene_pin_record.ex",
    "lib/storyarn/global_search/persistence/scene_record.ex",
    "lib/storyarn/global_search/persistence/scene_zone_record.ex",
    "lib/storyarn/global_search/scene_search.ex",
    "lib/storyarn/global_search/sheet_search.ex",
    "lib/storyarn/global_search/variable_query.ex",
    "lib/storyarn/global_search/variable_search.ex",
    "lib/storyarn/mailer.ex",
    "lib/storyarn/onboarding.ex",
    "lib/storyarn/onboarding/persistence/user_record.ex",
    "lib/storyarn/onboarding/tutorial_progress.ex",
    "lib/storyarn/publication/html_link_localizer.ex",
    "lib/storyarn/publication/locales.ex",
    "lib/storyarn/publication/path_localizer.ex",
    "lib/storyarn/rate_limiter.ex",
    "lib/storyarn/rate_limiter/",
    "lib/storyarn/release.ex",
    "lib/storyarn/repo.ex",
    "lib/storyarn/shared/canonical_json.ex",
    "lib/storyarn/shared/color_utils.ex",
    "lib/storyarn/shared/encrypted_binary.ex",
    "lib/storyarn/shared/formula_engine.ex",
    "lib/storyarn/shared/formula_runtime.ex",
    "lib/storyarn/shared/hierarchical_schema.ex",
    "lib/storyarn/shared/hierarchy_search.ex",
    "lib/storyarn/shared/html_sanitizer.ex",
    "lib/storyarn/shared/html_utils.ex",
    "lib/storyarn/shared/import_helpers.ex",
    "lib/storyarn/shared/map_utils.ex",
    "lib/storyarn/shared/search_helpers.ex",
    "lib/storyarn/shared/severity.ex",
    "lib/storyarn/shared/shortcut_helpers.ex",
    "lib/storyarn/shared/string_utils.ex",
    "lib/storyarn/shared/time_helpers.ex",
    "lib/storyarn/shared/token_generator.ex",
    "lib/storyarn/shared/tree_operations.ex",
    "lib/storyarn/urls.ex",
    "lib/storyarn/vault.ex",
    "lib/storyarn/workers/"
  ],

  # Explicit Web coordination outside concrete bounded-context surfaces. The
  # listed Phoenix layers are technical roots; there is deliberately no
  # `lib/storyarn_web/` catch-all.
  web_infrastructure: [
    "lib/storyarn_web.ex",
    "lib/storyarn_web/blog_formatting.ex",
    "lib/storyarn_web/blog_urls.ex",
    "lib/storyarn_web/client_ip.ex",
    "lib/storyarn_web/components/",
    "lib/storyarn_web/controllers/",
    "lib/storyarn_web/endpoint.ex",
    "lib/storyarn_web/feature_flag_helpers.ex",
    "lib/storyarn_web/helpers/",
    "lib/storyarn_web/language_picker_option.ex",
    "lib/storyarn_web/live/blog_live/",
    "lib/storyarn_web/live/docs_live/",
    "lib/storyarn_web/live/hooks/",
    "lib/storyarn_web/live/landing_live/",
    "lib/storyarn_web/live/legal_live/",
    "lib/storyarn_web/live/presence_live.ex",
    "lib/storyarn_web/live/settings_live/ai_team.ex",
    "lib/storyarn_web/live/settings_live/ai_team_overview.ex",
    "lib/storyarn_web/live/settings_live/integration_detail.ex",
    "lib/storyarn_web/live/settings_live/integrations.ex",
    "lib/storyarn_web/live/settings_live/tutorials.ex",
    "lib/storyarn_web/live/shared/",
    "lib/storyarn_web/live/tree_sidebar_actions.ex",
    "lib/storyarn_web/live_sandbox.ex",
    "lib/storyarn_web/plugs/",
    "lib/storyarn_web/private_download.ex",
    "lib/storyarn_web/private_download/",
    "lib/storyarn_web/private_media.ex",
    "lib/storyarn_web/public_locale.ex",
    "lib/storyarn_web/public_language_metadata.ex",
    "lib/storyarn_web/public_seo.ex",
    "lib/storyarn_web/public_urls.ex",
    "lib/storyarn_web/telemetry.ex",
    "lib/storyarn_web/user_auth.ex",
    "lib/storyarn_web/user_login_token.ex"
  ]
}

# Every bounded context is isolated from every other bounded context. Contexts
# may reach only explicitly allowlisted technical leaves in infrastructure. Infrastructure
# and shared Web code cannot bridge back into a bounded context.
context_dependencies =
  Map.new(bounded_contexts, fn context ->
    {context, (bounded_contexts -- [context]) ++ [:infrastructure, :presentation_adapters]}
  end)

forbidden_dependencies =
  Map.merge(context_dependencies, %{
    infrastructure: bounded_contexts ++ [:presentation_adapters],
    web_infrastructure: bounded_contexts
  })

%{
  version: 1,
  bounded_contexts: bounded_contexts,

  # Every xref source or target beneath these application roots must match one
  # boundary above. These roots define enforcement scope, not ownership.
  classification_roots: [
    "lib/storyarn.ex",
    "lib/storyarn/",
    "lib/storyarn_web.ex",
    "lib/storyarn_web/"
  ],
  boundaries: boundaries,
  forbidden_dependencies: forbidden_dependencies,

  # Code below `Storyarn` is the domain/application side of the system. Even
  # when a StoryarnWeb adapter is classified with the same owning context, the
  # dependency direction must stay domain -> application boundary <- Web.
  path_denials: [
    %{
      source_root: "lib/storyarn/",
      target_root: "lib/storyarn_web.ex",
      kinds: ["runtime", "export", "compile"],
      reason: "domain and application code cannot depend on the Web entry point"
    },
    %{
      source_root: "lib/storyarn/",
      target_root: "lib/storyarn_web/",
      kinds: ["runtime", "export", "compile"],
      reason: "domain and application code cannot depend on Phoenix or LiveVue adapters"
    }
  ],

  # Once a consumer reaches zero forbidden dependencies, its baseline is
  # sealed permanently. The checker rejects any edge in that partition even
  # when the current xref graph contains the exact same edge. Every partition
  # is sealed: the ENG-92 debt baseline is empty and can only stay empty.
  zero_debt_consumers: [
    :accounts,
    :flows,
    :infrastructure,
    :localization,
    :platform,
    :projects,
    :scenes,
    :sheets,
    :web_infrastructure,
    :workspaces
  ],

  # Every bounded context is sealed in both directions. Durable cross-boundary
  # access to a public facade must use an exact exception; it cannot be
  # accepted by adding an inbound edge to another consumer's debt baseline.
  isolated_contexts: [:accounts, :flows, :localization, :platform, :projects, :scenes, :sheets, :workspaces],

  # Repo is deliberately shared during ENG-92. Ecto and other external
  # dependencies do not appear as repository paths in the xref JSON graph.
  always_allowed_targets: [
    "lib/storyarn/repo.ex",
    "lib/storyarn/gettext.ex",
    "lib/storyarn/ai/context/contract.ex",
    "lib/storyarn/ai/context/policy.ex",
    "lib/storyarn/ai/context/subject_ref.ex",
    "lib/storyarn/assets/storage.ex",
    "lib/storyarn/assets/storage_hash.ex",
    "lib/storyarn/assets/storage_key_lock.ex",
    "lib/storyarn/dashboards/cache.ex",
    "lib/storyarn/collaboration.ex",
    "lib/storyarn/feature_flags.ex",
    "lib/storyarn/rate_limiter.ex",
    "lib/storyarn/urls.ex",
    "lib/storyarn/shared/color_utils.ex",
    "lib/storyarn/shared/encrypted_binary.ex",
    "lib/storyarn/shared/html_sanitizer.ex",
    "lib/storyarn/shared/html_utils.ex",
    "lib/storyarn/shared/map_utils.ex",
    "lib/storyarn/shared/search_helpers.ex",
    "lib/storyarn/shared/string_utils.ex",
    "lib/storyarn/shared/time_helpers.ex",
    "lib/storyarn/shared/token_generator.ex"
  ],

  # Phoenix Web adapters need VerifiedRoutes, while domain modules must remain
  # unable to import the router. This directional allowance is deliberately
  # source-scoped instead of making the router a globally allowed target.
  directional_allowances: [
    %{
      source_root: "lib/storyarn_web/",
      target: "lib/storyarn_web/router.ex",
      kinds: ["runtime"],
      reason: "Phoenix Web adapters use the application router for verified routes"
    }
  ],

  # Exceptions must identify one exact edge and dependency kind, and explain
  # why it is a durable architectural contract. Temporary debt belongs only in
  # the baseline files, never here.
  exceptions: [
    %{
      source: "lib/storyarn_web/live/hooks/notifications.ex",
      target: "lib/storyarn/notifications.ex",
      kinds: ["runtime"],
      reason: "The notifications hook subscribes and marks read state through the public Notifications facade"
    },
    %{
      source: "lib/storyarn_web/live/hooks/palette.ex",
      target: "lib/storyarn/notifications.ex",
      kinds: ["runtime"],
      reason: "Palette operations publish committed notification outcomes through the public Notifications facade"
    },
    %{
      source: "lib/storyarn_web/live/shared/notification_helpers.ex",
      target: "lib/storyarn/notifications.ex",
      kinds: ["runtime"],
      reason: "The shared notification helpers list and count through the public Notifications facade"
    },
    %{
      source: "lib/storyarn/workers/deliver_invitation_worker.ex",
      target: "lib/storyarn/projects.ex",
      kinds: ["runtime"],
      reason: "The durable invitation delivery worker calls back into the public Projects facade to render and send"
    },
    %{
      source: "lib/storyarn/application.ex",
      target: "lib/storyarn/imports/error_deduplicator.ex",
      kinds: ["runtime"],
      reason: "OTP composition root starts the import error deduplicator process"
    },
    %{
      source: "lib/storyarn/billing/storage_accounting.ex",
      target: "lib/storyarn/assets/asset.ex",
      kinds: ["runtime"],
      reason:
        "Storage accounting reconciles billed usage against the snapshot storage protocol owned by the Project boundary"
    },
    %{
      source: "lib/storyarn/billing/storage_accounting.ex",
      target: "lib/storyarn/assets/storage_cleanup_ownership_receipt.ex",
      kinds: ["runtime"],
      reason:
        "Storage accounting reconciles billed usage against the snapshot storage protocol owned by the Project boundary"
    },
    %{
      source: "lib/storyarn/billing/storage_accounting.ex",
      target: "lib/storyarn/projects/project.ex",
      kinds: ["export"],
      reason:
        "Storage accounting reconciles billed usage against the snapshot storage protocol owned by the Project boundary"
    },
    %{
      source: "lib/storyarn/billing/storage_accounting.ex",
      target: "lib/storyarn/versioning/project_snapshot.ex",
      kinds: ["export"],
      reason:
        "Storage accounting reconciles billed usage against the snapshot storage protocol owned by the Project boundary"
    },
    %{
      source: "lib/storyarn/billing/storage_accounting.ex",
      target: "lib/storyarn/versioning/project_snapshot_lease_policy.ex",
      kinds: ["runtime"],
      reason:
        "Storage accounting reconciles billed usage against the snapshot storage protocol owned by the Project boundary"
    },
    %{
      source: "lib/storyarn/billing/storage_accounting.ex",
      target: "lib/storyarn/versioning/project_snapshot_restore.ex",
      kinds: ["export"],
      reason:
        "Storage accounting reconciles billed usage against the snapshot storage protocol owned by the Project boundary"
    },
    %{
      source: "lib/storyarn/billing/storage_accounting.ex",
      target: "lib/storyarn/versioning/snapshot_archive_storage.ex",
      kinds: ["runtime"],
      reason:
        "Storage accounting reconciles billed usage against the snapshot storage protocol owned by the Project boundary"
    },
    %{
      source: "lib/storyarn/billing/storage_accounting.ex",
      target: "lib/storyarn/versioning/snapshot_object_format.ex",
      kinds: ["runtime"],
      reason:
        "Storage accounting reconciles billed usage against the snapshot storage protocol owned by the Project boundary"
    },
    %{
      source: "lib/storyarn/billing/storage_accounting.ex",
      target: "lib/storyarn/versioning/snapshot_object_publication_claim.ex",
      kinds: ["export"],
      reason:
        "Storage accounting reconciles billed usage against the snapshot storage protocol owned by the Project boundary"
    },
    %{
      source: "lib/storyarn/billing/storage_accounting.ex",
      target: "lib/storyarn/versioning/workspace_snapshot_import.ex",
      kinds: ["runtime"],
      reason:
        "Storage accounting reconciles billed usage against the snapshot storage protocol owned by the Project boundary"
    },
    %{
      source: "lib/storyarn/billing/storage_reservation.ex",
      target: "lib/storyarn/projects/project.ex",
      kinds: ["runtime"],
      reason: "Storage reservations validate their project and snapshot targets in the shared storage protocol"
    },
    %{
      source: "lib/storyarn/billing/storage_reservation.ex",
      target: "lib/storyarn/versioning/project_snapshot.ex",
      kinds: ["runtime"],
      reason: "Storage reservations validate their project and snapshot targets in the shared storage protocol"
    },
    %{
      source: "lib/storyarn/global_search/destinations.ex",
      target: "lib/storyarn/projects.ex",
      kinds: ["runtime"],
      reason: "Global search resolves reachable projects through the public Projects access reads"
    },
    %{
      source: "lib/storyarn/global_search/variable_search.ex",
      target: "lib/storyarn/references.ex",
      kinds: ["runtime"],
      reason: "Global variable search reads usage through the public References facade"
    },
    %{
      source: "lib/storyarn/release.ex",
      target: "lib/storyarn/project_templates.ex",
      kinds: ["runtime"],
      reason: "Release CLI tasks operate on templates through the public ProjectTemplates facade"
    },
    %{
      source: "lib/storyarn/release.ex",
      target: "lib/storyarn/projects.ex",
      kinds: ["runtime"],
      reason: "Release CLI tasks operate on projects through the public Projects facade"
    },
    %{
      source: "lib/storyarn/release.ex",
      target: "lib/storyarn/versioning.ex",
      kinds: ["runtime"],
      reason: "Release CLI tasks operate on snapshots through the public Versioning facade"
    },
    %{
      source: "lib/storyarn_web/components/project_layout.ex",
      target: "lib/storyarn/projects.ex",
      kinds: ["runtime"],
      reason: "The project shell resolves navigation state through the public Projects facade"
    },
    %{
      source: "lib/storyarn_web/endpoint.ex",
      target: "lib/storyarn/assets/upload_policy.ex",
      kinds: ["compile"],
      reason: "The endpoint compiles upload limits from the asset upload policy"
    },
    %{
      source: "lib/storyarn_web/helpers/authorize.ex",
      target: "lib/storyarn/projects.ex",
      kinds: ["runtime"],
      reason: "LiveView authorization resolves effective project roles through the public Projects facade"
    },
    %{
      source: "lib/storyarn_web/live/hooks/project_scope.ex",
      target: "lib/storyarn/projects.ex",
      kinds: ["runtime"],
      reason: "The project scope hook loads the current project through the public Projects facade"
    },
    %{
      source: "lib/storyarn/assets.ex",
      target: "lib/storyarn/billing.ex",
      kinds: ["runtime"],
      reason: "Asset lifecycle accounts storage usage through the public Billing facade"
    },
    %{
      source: "lib/storyarn/assets/asset_trash.ex",
      target: "lib/storyarn/billing.ex",
      kinds: ["runtime"],
      reason: "Asset lifecycle accounts storage usage through the public Billing facade"
    },
    %{
      source: "lib/storyarn/assets/blob_store.ex",
      target: "lib/storyarn/billing.ex",
      kinds: ["runtime"],
      reason: "Asset lifecycle accounts storage usage through the public Billing facade"
    },
    %{
      source: "lib/storyarn/assets/storage_compensation.ex",
      target: "lib/storyarn/billing/storage_reservation.ex",
      kinds: ["export"],
      reason:
        "The snapshot storage lifecycle holds and releases Billing storage reservations as the durable cross-boundary receipt"
    },
    %{
      source: "lib/storyarn/imports/execution.ex",
      target: "lib/storyarn/billing.ex",
      kinds: ["runtime"],
      reason: "Project imports enforce plan and storage entitlements through the public Billing facade"
    },
    %{
      source: "lib/storyarn/imports/execution.ex",
      target: "lib/storyarn/notifications.ex",
      kinds: ["runtime"],
      reason: "Project coordination delivers durable user notifications through the public Notifications facade"
    },
    %{
      source: "lib/storyarn/imports/expiration.ex",
      target: "lib/storyarn/notifications.ex",
      kinds: ["runtime"],
      reason: "Project coordination delivers durable user notifications through the public Notifications facade"
    },
    %{
      source: "lib/storyarn/imports/materializer.ex",
      target: "lib/storyarn/billing.ex",
      kinds: ["runtime"],
      reason: "Project imports enforce plan and storage entitlements through the public Billing facade"
    },
    %{
      source: "lib/storyarn/imports/notification_delivery.ex",
      target: "lib/storyarn/notifications.ex",
      kinds: ["runtime"],
      reason: "Project coordination delivers durable user notifications through the public Notifications facade"
    },
    %{
      source: "lib/storyarn/imports/plan_storage.ex",
      target: "lib/storyarn/vault.ex",
      kinds: ["runtime"],
      reason: "Import plan storage encrypts payloads with the application vault"
    },
    %{
      source: "lib/storyarn/imports/replacement.ex",
      target: "lib/storyarn/billing.ex",
      kinds: ["runtime"],
      reason: "Project imports enforce plan and storage entitlements through the public Billing facade"
    },
    %{
      source: "lib/storyarn/imports/resume.ex",
      target: "lib/storyarn/notifications.ex",
      kinds: ["runtime"],
      reason: "Project coordination delivers durable user notifications through the public Notifications facade"
    },
    %{
      source: "lib/storyarn/project_templates/installation.ex",
      target: "lib/storyarn/billing.ex",
      kinds: ["runtime"],
      reason: "Template installation and publication enforce plan entitlements through the public Billing facade"
    },
    %{
      source: "lib/storyarn/project_templates/installation.ex",
      target: "lib/storyarn/notifications.ex",
      kinds: ["runtime"],
      reason: "Project coordination delivers durable user notifications through the public Notifications facade"
    },
    %{
      source: "lib/storyarn/project_templates/publication_runner.ex",
      target: "lib/storyarn/billing.ex",
      kinds: ["runtime"],
      reason: "Template installation and publication enforce plan entitlements through the public Billing facade"
    },
    %{
      source: "lib/storyarn/projects/project_crud.ex",
      target: "lib/storyarn/billing.ex",
      kinds: ["runtime"],
      reason: "Project lifecycle enforces plan entitlements through the public Billing facade"
    },
    %{
      source: "lib/storyarn/projects/project_trash.ex",
      target: "lib/storyarn/billing.ex",
      kinds: ["runtime"],
      reason: "Project lifecycle enforces plan entitlements through the public Billing facade"
    },
    %{
      source: "lib/storyarn/shared/invitation_notifier.ex",
      target: "lib/storyarn/emails/templates.ex",
      kinds: ["runtime"],
      reason: "Project invitation email rendering uses the shared transactional email templates"
    },
    %{
      source: "lib/storyarn/shared/invitation_notifier.ex",
      target: "lib/storyarn/mailer.ex",
      kinds: ["runtime"],
      reason: "Project invitation delivery goes through the application mailer"
    },
    %{
      source: "lib/storyarn/shared/invitation_operations.ex",
      target: "lib/storyarn/billing.ex",
      kinds: ["runtime"],
      reason: "Project invitations enforce seat entitlements through the public Billing facade"
    },
    %{
      source: "lib/storyarn/shared/invitation_operations.ex",
      target: "lib/storyarn/workers/deliver_invitation_worker.ex",
      kinds: ["runtime"],
      reason: "Project invitations enqueue the durable delivery worker shared with Workspace invitations"
    },
    %{
      source: "lib/storyarn/versioning.ex",
      target: "lib/storyarn/billing.ex",
      kinds: ["runtime"],
      reason: "Snapshot storage lifecycle accounts usage and locks through the public Billing facade"
    },
    %{
      source: "lib/storyarn/versioning/materialization_helpers.ex",
      target: "lib/storyarn/billing.ex",
      kinds: ["runtime"],
      reason: "Snapshot storage lifecycle accounts usage and locks through the public Billing facade"
    },
    %{
      source: "lib/storyarn/versioning/project_recovery.ex",
      target: "lib/storyarn/billing.ex",
      kinds: ["runtime"],
      reason: "Snapshot storage lifecycle accounts usage and locks through the public Billing facade"
    },
    %{
      source: "lib/storyarn/versioning/project_snapshot.ex",
      target: "lib/storyarn/billing/storage_reservation.ex",
      kinds: ["runtime"],
      reason:
        "The snapshot storage lifecycle holds and releases Billing storage reservations as the durable cross-boundary receipt"
    },
    %{
      source: "lib/storyarn/versioning/project_snapshot_asset_materializer.ex",
      target: "lib/storyarn/billing.ex",
      kinds: ["runtime"],
      reason: "Snapshot storage lifecycle accounts usage and locks through the public Billing facade"
    },
    %{
      source: "lib/storyarn/versioning/project_snapshot_build.ex",
      target: "lib/storyarn/billing.ex",
      kinds: ["runtime"],
      reason: "Snapshot storage lifecycle accounts usage and locks through the public Billing facade"
    },
    %{
      source: "lib/storyarn/versioning/project_snapshot_build.ex",
      target: "lib/storyarn/billing/storage_reservation.ex",
      kinds: ["export"],
      reason:
        "The snapshot storage lifecycle holds and releases Billing storage reservations as the durable cross-boundary receipt"
    },
    %{
      source: "lib/storyarn/versioning/project_snapshot_build.ex",
      target: "lib/storyarn/notifications.ex",
      kinds: ["runtime"],
      reason: "Project coordination delivers durable user notifications through the public Notifications facade"
    },
    %{
      source: "lib/storyarn/versioning/project_snapshot_crud.ex",
      target: "lib/storyarn/billing.ex",
      kinds: ["runtime"],
      reason: "Snapshot storage lifecycle accounts usage and locks through the public Billing facade"
    },
    %{
      source: "lib/storyarn/versioning/project_snapshot_download.ex",
      target: "lib/storyarn/billing.ex",
      kinds: ["runtime"],
      reason: "Snapshot storage lifecycle accounts usage and locks through the public Billing facade"
    },
    %{
      source: "lib/storyarn/versioning/project_snapshot_lifecycle.ex",
      target: "lib/storyarn/billing.ex",
      kinds: ["runtime"],
      reason: "Snapshot storage lifecycle accounts usage and locks through the public Billing facade"
    },
    %{
      source: "lib/storyarn/versioning/project_snapshot_lifecycle.ex",
      target: "lib/storyarn/billing/storage_reservation.ex",
      kinds: ["export"],
      reason:
        "The snapshot storage lifecycle holds and releases Billing storage reservations as the durable cross-boundary receipt"
    },
    %{
      source: "lib/storyarn/versioning/project_snapshot_reconciliation.ex",
      target: "lib/storyarn/billing.ex",
      kinds: ["runtime"],
      reason: "Snapshot storage lifecycle accounts usage and locks through the public Billing facade"
    },
    %{
      source: "lib/storyarn/versioning/project_snapshot_reconciliation.ex",
      target: "lib/storyarn/billing/storage_reservation.ex",
      kinds: ["export"],
      reason:
        "The snapshot storage lifecycle holds and releases Billing storage reservations as the durable cross-boundary receipt"
    },
    %{
      source: "lib/storyarn/versioning/project_snapshot_reconciliation_repair.ex",
      target: "lib/storyarn/billing.ex",
      kinds: ["runtime"],
      reason: "Snapshot storage lifecycle accounts usage and locks through the public Billing facade"
    },
    %{
      source: "lib/storyarn/versioning/project_snapshot_reconciliation_repair.ex",
      target: "lib/storyarn/billing/storage_reservation.ex",
      kinds: ["export"],
      reason:
        "The snapshot storage lifecycle holds and releases Billing storage reservations as the durable cross-boundary receipt"
    },
    %{
      source: "lib/storyarn/versioning/project_snapshot_restore.ex",
      target: "lib/storyarn/billing/storage_reservation.ex",
      kinds: ["export"],
      reason:
        "The snapshot storage lifecycle holds and releases Billing storage reservations as the durable cross-boundary receipt"
    },
    %{
      source: "lib/storyarn/versioning/project_snapshot_restore_executor.ex",
      target: "lib/storyarn/billing.ex",
      kinds: ["runtime"],
      reason: "Snapshot storage lifecycle accounts usage and locks through the public Billing facade"
    },
    %{
      source: "lib/storyarn/versioning/project_snapshot_restore_executor.ex",
      target: "lib/storyarn/billing/storage_cleanup_inventory.ex",
      kinds: ["runtime"],
      reason: "Snapshot storage cleanup reconciles against the Billing storage cleanup inventory protocol"
    },
    %{
      source: "lib/storyarn/versioning/project_snapshot_restore_executor.ex",
      target: "lib/storyarn/billing/storage_reservation.ex",
      kinds: ["export"],
      reason:
        "The snapshot storage lifecycle holds and releases Billing storage reservations as the durable cross-boundary receipt"
    },
    %{
      source: "lib/storyarn/versioning/project_snapshot_restore_lifecycle.ex",
      target: "lib/storyarn/billing.ex",
      kinds: ["runtime"],
      reason: "Snapshot storage lifecycle accounts usage and locks through the public Billing facade"
    },
    %{
      source: "lib/storyarn/versioning/project_snapshot_restore_lifecycle.ex",
      target: "lib/storyarn/billing/storage_reservation.ex",
      kinds: ["export"],
      reason:
        "The snapshot storage lifecycle holds and releases Billing storage reservations as the durable cross-boundary receipt"
    },
    %{
      source: "lib/storyarn/versioning/snapshot_archive_smoke.ex",
      target: "lib/storyarn/assets/storage/r2.ex",
      kinds: ["runtime"],
      reason: "The archive smoke check branches on the configured storage adapter"
    },
    %{
      source: "lib/storyarn/versioning/snapshot_archive_storage.ex",
      target: "lib/storyarn/billing/storage_cleanup_inventory.ex",
      kinds: ["runtime"],
      reason: "Snapshot storage cleanup reconciles against the Billing storage cleanup inventory protocol"
    },
    %{
      source: "lib/storyarn/versioning/snapshot_archive_storage.ex",
      target: "lib/storyarn/billing/storage_reservation.ex",
      kinds: ["export"],
      reason:
        "The snapshot storage lifecycle holds and releases Billing storage reservations as the durable cross-boundary receipt"
    },
    %{
      source: "lib/storyarn/versioning/workspace_snapshot_imports.ex",
      target: "lib/storyarn/billing.ex",
      kinds: ["runtime"],
      reason: "Snapshot storage lifecycle accounts usage and locks through the public Billing facade"
    },
    %{
      source: "lib/storyarn/versioning/workspace_snapshot_imports.ex",
      target: "lib/storyarn/notifications.ex",
      kinds: ["runtime"],
      reason: "Project coordination delivers durable user notifications through the public Notifications facade"
    },
    %{
      source: "lib/storyarn_web/live/project_live/components/settings_components.ex",
      target: "lib/storyarn/billing.ex",
      kinds: ["runtime"],
      reason: "Project settings pages show plan usage through the public Billing facade"
    },
    %{
      source: "lib/storyarn_web/live/project_live/invitation.ex",
      target: "lib/storyarn/publication/locales.ex",
      kinds: ["runtime"],
      reason: "Invitation pages normalize the public locale like the other public-facing pages"
    },
    %{
      source: "lib/storyarn_web/live/project_settings_live/usage_limits.ex",
      target: "lib/storyarn/billing.ex",
      kinds: ["runtime"],
      reason: "Project settings pages show plan usage through the public Billing facade"
    },
    %{
      source: "lib/storyarn_web/live/project_settings_live/version_control.ex",
      target: "lib/storyarn/billing.ex",
      kinds: ["runtime"],
      reason: "Project settings pages show plan usage through the public Billing facade"
    },
    %{
      source: "lib/storyarn/application.ex",
      target: "lib/storyarn_web/endpoint.ex",
      kinds: ["runtime"],
      reason: "OTP composition root starts and reconfigures the Phoenix endpoint"
    },
    %{
      source: "lib/storyarn/application.ex",
      target: "lib/storyarn_web/telemetry.ex",
      kinds: ["runtime"],
      reason: "OTP composition root starts the Web telemetry supervisor"
    },
    %{
      source: "lib/storyarn/application.ex",
      target: "lib/storyarn/flows.ex",
      kinds: ["runtime"],
      reason: "OTP composition root starts the public Flows supervisor"
    },
    %{
      source: "lib/storyarn/projects/events.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "The Project boundary publishes owned business facts through the public Platform reaction contract"
    },
    %{
      source: "lib/storyarn/flows/events.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Flows publishes owned business facts through the public Platform reaction contract"
    },
    %{
      source: "lib/storyarn/flows/flow_crud.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Flow mutations request durable notification delivery through the public Platform contract"
    },
    %{
      source: "lib/storyarn/flows/limits.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Flows applies Platform-owned commercial entitlements to Flow operations"
    },
    %{
      source: "lib/storyarn/flows/versioning/asset_catalog.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Flow snapshot materialization applies the Platform-owned storage entitlement"
    },
    %{
      source: "lib/storyarn/localization/notification_delivery.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Localization requests durable cross-cutting delivery through the public Platform contract"
    },
    %{
      source: "lib/storyarn/scenes/asset_commands.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Scenes applies the Platform-owned storage entitlement to Scene asset writes and restores"
    },
    %{
      source: "lib/storyarn/scenes/events.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Scenes publishes owned business facts through the public Platform reaction contract"
    },
    %{
      source: "lib/storyarn/scenes/limits.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Scenes applies Platform-owned commercial entitlements to Scene operations"
    },
    %{
      source: "lib/storyarn/sheets/asset_commands.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Sheets applies the Platform-owned storage entitlement to Sheet asset writes and restores"
    },
    %{
      source: "lib/storyarn/sheets/events.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Sheets publishes owned business facts through the public Platform reaction contract"
    },
    %{
      source: "lib/storyarn/sheets/limits.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Sheets applies Platform-owned commercial entitlements to Sheet operations"
    },
    %{
      source: "lib/storyarn/sheets/sheet_crud.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Sheet mutations request durable notification delivery through the public Platform contract"
    },
    %{
      source: "lib/storyarn/sheets/versioning/sheet_snapshot.ex",
      target: "lib/storyarn/references.ex",
      kinds: ["runtime"],
      reason: "Sheet restore triggers the Project-owned project-wide variable reference rebuild through its public facade"
    },
    %{
      source: "lib/storyarn/workspaces/workspace_crud.ex",
      target: "lib/storyarn/billing.ex",
      kinds: ["runtime"],
      reason:
        "Workspace lifecycle applies Platform-owned commercial limits and subscriptions through the public Billing facade"
    },
    %{
      source: "lib/storyarn/workspaces/workspace_crud.ex",
      target: "lib/storyarn/versioning.ex",
      kinds: ["runtime"],
      reason: "Workspace hard-delete coordinates snapshot cleanup through the public Versioning facade"
    },
    %{
      source: "lib/storyarn/workspaces/workspace_crud.ex",
      target: "lib/storyarn/assets.ex",
      kinds: ["runtime"],
      reason: "Workspace hard-delete coordinates asset cleanup through the public Assets facade"
    },
    %{
      source: "lib/storyarn/accounts/events.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Accounts publishes owned business facts through the public Platform reaction contract"
    },
    %{
      source: "lib/storyarn/workers/deliver_reset_password_instructions_worker.ex",
      target: "lib/storyarn/accounts.ex",
      kinds: ["runtime"],
      reason: "The durable reset-password delivery worker calls back into the public Accounts facade to render and send"
    },
    %{
      source: "lib/storyarn/workers/request_reset_password_instructions_worker.ex",
      target: "lib/storyarn/accounts.ex",
      kinds: ["runtime"],
      reason: "The durable reset-password request worker processes the request through the public Accounts facade"
    },
    %{
      source: "lib/storyarn_web/user_auth.ex",
      target: "lib/storyarn/accounts.ex",
      kinds: ["runtime"],
      reason: "Session authentication resolves users and tokens through the public Accounts facade"
    },
    %{
      source: "lib/storyarn_web/user_auth.ex",
      target: "lib/storyarn/accounts/scope.ex",
      kinds: ["export"],
      reason: "The session plug constructs the Accounts scope that every LiveView receives as current_scope"
    },
    %{
      source: "lib/storyarn_web/user_auth.ex",
      target: "lib/storyarn/accounts/user.ex",
      kinds: ["export"],
      reason: "The session plug pattern-matches the authenticated user struct returned by the public Accounts facade"
    },
    %{
      source: "lib/storyarn_web/live/project_live/invitation.ex",
      target: "lib/storyarn/accounts.ex",
      kinds: ["runtime"],
      reason: "Invitation acceptance prepares the invited account through the public Accounts facade"
    },
    %{
      source: "lib/storyarn_web/live/settings_live/ai_team.ex",
      target: "lib/storyarn_web/live/settings_live/sudo.ex",
      kinds: ["runtime"],
      reason: "AI team settings gate sensitive actions behind the account sudo re-authentication flow"
    },
    %{
      source: "lib/storyarn_web/live/settings_live/integration_detail.ex",
      target: "lib/storyarn_web/live/settings_live/sudo.ex",
      kinds: ["runtime"],
      reason: "Integration credential actions gate behind the account sudo re-authentication flow"
    },
    %{
      source: "lib/storyarn/accounts/passwords.ex",
      target: "lib/storyarn/workers/deliver_reset_password_instructions_worker.ex",
      kinds: ["runtime"],
      reason: "Password reset enqueues its durable delivery worker"
    },
    %{
      source: "lib/storyarn/accounts/passwords.ex",
      target: "lib/storyarn/workers/request_reset_password_instructions_worker.ex",
      kinds: ["runtime"],
      reason: "Password reset requests enqueue their durable delivery worker"
    },
    %{
      source: "lib/storyarn/accounts/user_notifier.ex",
      target: "lib/storyarn/emails/templates.ex",
      kinds: ["runtime"],
      reason: "Account email rendering uses the shared transactional email templates"
    },
    %{
      source: "lib/storyarn/accounts/user_notifier.ex",
      target: "lib/storyarn/mailer.ex",
      kinds: ["runtime"],
      reason: "Account email delivery goes through the application mailer"
    },
    %{
      source: "lib/storyarn_web/live/user_live/login.ex",
      target: "lib/storyarn/mailer.ex",
      kinds: ["runtime"],
      reason: "The login page offers the local dev mailbox link by inspecting the configured mailer adapter"
    },
    %{
      source: "lib/storyarn/workspaces/events.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Workspaces publishes owned business facts through the public Platform reaction contract"
    },
    %{
      source: "lib/storyarn/workspaces/invitations.ex",
      target: "lib/storyarn/billing.ex",
      kinds: ["runtime"],
      reason: "Workspace invitations apply the Platform-owned member seat limits through the public Billing facade"
    },
    %{
      source: "lib/storyarn/workspaces/invitations.ex",
      target: "lib/storyarn/workers/deliver_invitation_worker.ex",
      kinds: ["runtime"],
      reason: "Workspace invitations enqueue the durable delivery worker shared with Project invitations"
    },
    %{
      source: "lib/storyarn/workspaces/invitation_notifier.ex",
      target: "lib/storyarn/emails/templates.ex",
      kinds: ["runtime"],
      reason: "Workspace invitation email rendering uses the shared transactional email templates"
    },
    %{
      source: "lib/storyarn/workspaces/invitation_notifier.ex",
      target: "lib/storyarn/mailer.ex",
      kinds: ["runtime"],
      reason: "Workspace invitation delivery goes through the application mailer"
    },
    %{
      source: "lib/storyarn_web/live/settings_live/workspace_deleted_projects.ex",
      target: "lib/storyarn/projects.ex",
      kinds: ["runtime"],
      reason: "The workspace trash settings page lists and restores deleted projects through the public Projects facade"
    },
    %{
      source: "lib/storyarn_web/live/settings_live/workspace_general.ex",
      target: "lib/storyarn/ai.ex",
      kinds: ["runtime"],
      reason: "Workspace general settings surfaces the AI policy controls through the public AI facade"
    },
    %{
      source: "lib/storyarn_web/live/settings_live/workspace_general.ex",
      target: "lib/storyarn/assets.ex",
      kinds: ["runtime"],
      reason: "Workspace banner upload goes through the public Assets facade"
    },
    %{
      source: "lib/storyarn_web/live/settings_live/workspace_general.ex",
      target: "lib/storyarn/assets/image_processor.ex",
      kinds: ["runtime"],
      reason:
        "Workspace banner upload validates image binaries with the Assets image primitives, like the upload controller"
    },
    %{
      source: "lib/storyarn_web/live/settings_live/workspace_general.ex",
      target: "lib/storyarn/assets/upload_policy.ex",
      kinds: ["runtime"],
      reason: "Workspace banner upload enforces the Assets upload profile, like the upload controller"
    },
    %{
      source: "lib/storyarn_web/live/settings_live/workspace_imports.ex",
      target: "lib/storyarn/versioning.ex",
      kinds: ["runtime"],
      reason: "Workspace snapshot imports are requested and tracked through the public Versioning facade"
    },
    %{
      source: "lib/storyarn_web/live/settings_live/workspace_imports.ex",
      target: "lib/storyarn/versioning/project_snapshot_archive_reader.ex",
      kinds: ["runtime"],
      reason: "The import page shows the archive size limit owned by the Versioning archive reader"
    },
    %{
      source: "lib/storyarn_web/live/settings_live/workspace_imports.ex",
      target: "lib/storyarn/assets/storage/r2.ex",
      kinds: ["runtime"],
      reason: "The import page branches on the configured storage adapter to offer external uploads"
    },
    %{
      source: "lib/storyarn_web/live/workspace_live/invitation.ex",
      target: "lib/storyarn/accounts.ex",
      kinds: ["runtime"],
      reason: "Invitation acceptance prepares the invited account through the public Accounts facade"
    },
    %{
      source: "lib/storyarn_web/live/workspace_live/invitation.ex",
      target: "lib/storyarn/publication/locales.ex",
      kinds: ["runtime"],
      reason: "Invitation pages normalize the public locale like the other public-facing pages"
    },
    %{
      source: "lib/storyarn_web/live/workspace_live/show.ex",
      target: "lib/storyarn/billing.ex",
      kinds: ["runtime"],
      reason: "The workspace home shows plan usage through the public Billing facade"
    },
    %{
      source: "lib/storyarn_web/live/workspace_live/show.ex",
      target: "lib/storyarn/project_templates.ex",
      kinds: ["runtime"],
      reason: "The workspace home offers template installation through the public ProjectTemplates facade"
    },
    %{
      source: "lib/storyarn_web/live/workspace_live/show.ex",
      target: "lib/storyarn/projects.ex",
      kinds: ["runtime"],
      reason: "The workspace home lists and creates projects through the public Projects facade"
    },
    %{
      source: "lib/storyarn/accounts/registration.ex",
      target: "lib/storyarn/workspaces.ex",
      kinds: ["runtime"],
      reason: "Registration provisions each new account's default workspace through the public Workspaces facade"
    },
    %{
      source: "lib/storyarn/global_search/destinations.ex",
      target: "lib/storyarn/workspaces.ex",
      kinds: ["runtime"],
      reason: "Global search resolves reachable workspaces through the public Workspaces access reads"
    },
    %{
      source: "lib/storyarn/release.ex",
      target: "lib/storyarn/workspaces.ex",
      kinds: ["runtime"],
      reason: "Release CLI tasks operate on workspaces through the public Workspaces facade"
    },
    %{
      source: "lib/storyarn/workers/deliver_invitation_worker.ex",
      target: "lib/storyarn/workspaces.ex",
      kinds: ["runtime"],
      reason: "The durable invitation delivery worker calls back into the public Workspaces facade to render and send"
    },
    %{
      source: "lib/storyarn_web/controllers/private_media_controller.ex",
      target: "lib/storyarn/workspaces.ex",
      kinds: ["runtime"],
      reason: "Private media authorizes workspace access through the public Workspaces facade"
    },
    %{
      source: "lib/storyarn_web/live/template_live/show.ex",
      target: "lib/storyarn/workspaces.ex",
      kinds: ["runtime"],
      reason: "Template installation pages list the user's workspaces through the public Workspaces facade"
    },
    %{
      source: "lib/storyarn_web/helpers/authorize.ex",
      target: "lib/storyarn/workspaces.ex",
      kinds: ["runtime"],
      reason: "The shared Web authorization helper checks workspace permissions through the public Workspaces facade"
    },
    %{
      source: "lib/storyarn_web/live/hooks/palette.ex",
      target: "lib/storyarn/workspaces.ex",
      kinds: ["runtime"],
      reason: "The global command palette resolves workspace scope through the public Workspaces facade"
    },
    %{
      source: "lib/storyarn_web/live/hooks/workspace_scope.ex",
      target: "lib/storyarn/workspaces.ex",
      kinds: ["runtime"],
      reason: "The workspace-scope mount hook loads the active workspace through the public Workspaces facade"
    },
    %{
      source: "lib/storyarn_web/live/landing_live/index.ex",
      target: "lib/storyarn/workspaces.ex",
      kinds: ["runtime"],
      reason: "The landing page routes signed-in users to their default workspace through the public Workspaces facade"
    },
    %{
      source: "lib/storyarn_web/live/landing_live/index.ex",
      target: "lib/storyarn/workspaces/workspace.ex",
      kinds: ["export"],
      reason: "The landing page pattern-matches the Workspace struct returned by the public facade"
    },
    %{
      source: "lib/storyarn_web/user_auth.ex",
      target: "lib/storyarn/workspaces.ex",
      kinds: ["runtime"],
      reason: "Session plumbing resolves the user's workspaces through the public Workspaces facade"
    },
    %{
      source: "lib/storyarn_web/user_auth.ex",
      target: "lib/storyarn/workspaces/workspace.ex",
      kinds: ["export"],
      reason: "Session plumbing pattern-matches the Workspace struct returned by the public facade"
    },
    %{
      source: "lib/storyarn/global_search/variable_search.ex",
      target: "lib/storyarn/sheets.ex",
      kinds: ["runtime"],
      reason:
        "Global variable search is technical infrastructure over the Sheet-owned variable catalog; the predicate engine reads through the public Sheets facade rather than duplicating the 1000-line catalog"
    },
    %{
      source: "lib/storyarn_web/live/hooks/palette.ex",
      target: "lib/storyarn/sheets.ex",
      kinds: ["runtime"],
      reason:
        "The global command palette creates, deletes, and localizes entities of every tool through each tool's public facade"
    },
    %{
      source: "lib/storyarn/scenes/scene_crud.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Scene mutations request durable notification delivery through the public Platform contract"
    },
    %{
      source: "lib/storyarn/projects/project.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Projects validates the Platform-owned product metric taxonomy through its public facade"
    },
    %{
      source: "lib/storyarn/projects/localization_settings.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Project-owned localization settings request durable delivery through the public Platform contract"
    },
    %{
      source: "lib/storyarn/platform/product_metrics.ex",
      target: "lib/storyarn/analytics.ex",
      kinds: ["runtime"],
      reason: "Platform product metrics owns the only new product-context access to the analytics transport"
    },
    %{
      source: "lib/storyarn/platform/product_metrics.ex",
      target: "lib/storyarn/analytics/event_contract.ex",
      kinds: ["runtime"],
      reason: "Platform product metrics implements the fail-closed analytics transport contract"
    },
    %{
      source: "lib/storyarn_web/live/hooks/palette.ex",
      target: "lib/storyarn/flows.ex",
      kinds: ["runtime"],
      reason: "Authenticated command palette coordinates Flow creation and deletion through the public facade"
    },
    %{
      source: "lib/storyarn_web/live/hooks/palette.ex",
      target: "lib/storyarn/scenes.ex",
      kinds: ["runtime"],
      reason: "Authenticated command palette coordinates Scene creation and deletion through the public facade"
    },
    %{
      source: "lib/storyarn_web/live/project_live/form.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Project creation presents the Platform-owned product metric taxonomy through its public facade"
    },
    %{
      source: "lib/storyarn_web/live/project_settings_live/general.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Project settings presents the Platform-owned product metric taxonomy through its public facade"
    },
    %{
      source: "lib/storyarn_web/live/workspace_live/show.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Workspace project creation presents the Platform-owned product metric taxonomy through its public facade"
    },
    %{
      source: "lib/storyarn/workers/localization_batch_translation_worker.ex",
      target: "lib/storyarn/localization.ex",
      kinds: ["runtime"],
      reason: "The Oban adapter delegates batch translation execution to the public Localization facade"
    },
    %{
      source: "lib/storyarn/urls.ex",
      target: "lib/storyarn_web/endpoint.ex",
      kinds: ["runtime"],
      reason: "Technical URL resolution reads the configured Phoenix endpoint without calling Web behavior"
    }
  ]
}
