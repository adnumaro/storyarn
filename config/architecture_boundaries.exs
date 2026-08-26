# ENG-92 code boundaries. These rules intentionally protect code ownership only:
# they do not assign database write ownership or change the shared schema.

# These are the bounded contexts sealed by the current ENG-92 ratchet. AI is
# also a product bounded context, but this pass deliberately leaves its existing
# dependency classification unchanged instead of claiming that it is isolated.
bounded_contexts = [:accounts, :workspaces, :platform, :projects, :sheets, :flows, :scenes, :localization]

boundaries = %{
  accounts: [
    "lib/storyarn/accounts.ex",
    "lib/storyarn/accounts/",
    "lib/storyarn/workers/accounts/",
    "lib/storyarn_web/controllers/user_session_controller.ex",
    "lib/storyarn_web/live/user_live/",
    "lib/storyarn_web/live/settings_live/profile.ex",
    "lib/storyarn_web/live/settings_live/security.ex"
  ],
  workspaces: [
    "lib/storyarn/workspaces.ex",
    "lib/storyarn/workspaces/",
    "lib/storyarn/workers/workspaces/",
    "lib/storyarn_web/live/workspace_live/",
    "lib/storyarn_web/live/settings_live/workspace_deleted_projects.ex",
    "lib/storyarn_web/live/settings_live/workspace_general.ex",
    "lib/storyarn_web/live/settings_live/workspace_imports.ex",
    "lib/storyarn_web/live/settings_live/workspace_members.ex"
  ],
  platform: [
    "lib/storyarn/platform.ex",
    "lib/storyarn/platform/",
    "lib/storyarn/workers/platform/",

    # Transitional locations owned by the Platform control plane. Moving them
    # under `Storyarn.Platform` is a separate migration; listing them here does
    # not turn their consumers into part of Platform.
    "lib/storyarn/platform/billing.ex",
    "lib/storyarn/platform/billing/",
    "lib/storyarn/platform/emails/",
    "lib/storyarn/platform/notifications.ex",
    "lib/storyarn/platform/notifications/"
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
    "lib/storyarn/workers/projects/",
    "lib/storyarn/projects/assets.ex",
    "lib/storyarn/projects/assets/",
    "lib/storyarn/projects/references.ex",
    "lib/storyarn/projects/references/",
    "lib/storyarn/projects/invitation_notifier.ex",
    "lib/storyarn/projects/invitation_operations.ex",
    "lib/storyarn/projects/invitation_schema.ex",
    "lib/storyarn/projects/membership_operations.ex",
    "lib/storyarn/projects/versioning.ex",
    "lib/storyarn/projects/versioning/",
    "lib/storyarn/projects/exports.ex",
    "lib/storyarn/projects/exports/",
    "lib/storyarn/projects/imports.ex",
    "lib/storyarn/projects/imports/",
    "lib/storyarn/projects/project_templates.ex",
    "lib/storyarn/projects/project_templates/",
    "lib/storyarn/projects/name_normalizer.ex",
    "lib/storyarn/projects/validations.ex",
    "lib/storyarn/projects/word_count.ex",
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
    "lib/storyarn/workers/localization/",
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

  # Explicit technical/application namespaces and namespaces whose boundary is
  # not sealed by this ratchet yet. There is deliberately no `lib/storyarn/`
  # catch-all: an unlisted namespace must fail until its ownership is reviewed.
  # AI is a recognized product bounded context, but remains transitionally
  # classified here for this pass; that does not make it a shared domain kernel.
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
    "lib/storyarn/platform/analytics.ex",
    "lib/storyarn/platform/analytics/",
    "lib/storyarn/application.ex",
    "lib/storyarn/architecture/",
    "lib/storyarn/projects/assets/storage.ex",
    "lib/storyarn/projects/assets/storage/",
    "lib/storyarn/projects/assets/storage_hash.ex",
    "lib/storyarn/projects/assets/storage_key_lock.ex",
    "lib/storyarn/public/blog.ex",
    "lib/storyarn/public/blog/post.ex",
    "lib/storyarn/public/blog/post_builder.ex",
    "lib/storyarn/platform/collaboration.ex",
    "lib/storyarn/platform/collaboration/",
    "lib/storyarn/platform/command_palette.ex",
    "lib/storyarn/platform/command_palette/definition.ex",
    "lib/storyarn/platform/command_palette/operation.ex",
    "lib/storyarn/platform/command_palette/persistence/user_record.ex",
    "lib/storyarn/platform/command_palette/registry.ex",
    "lib/storyarn/platform/dashboards/cache.ex",
    "lib/storyarn/public/docs.ex",
    "lib/storyarn/public/docs/guide.ex",
    "lib/storyarn/public/docs/guide_builder.ex",
    "lib/storyarn/platform/feature_flags.ex",
    "lib/storyarn/gettext.ex",
    "lib/storyarn/platform/global_search.ex",
    "lib/storyarn/platform/global_search/advanced_search.ex",
    "lib/storyarn/platform/global_search/destinations.ex",
    "lib/storyarn/platform/global_search/flow_search.ex",
    "lib/storyarn/platform/global_search/persistence/block_gallery_image_record.ex",
    "lib/storyarn/platform/global_search/persistence/block_record.ex",
    "lib/storyarn/platform/global_search/persistence/flow_connection_record.ex",
    "lib/storyarn/platform/global_search/persistence/flow_node_record.ex",
    "lib/storyarn/platform/global_search/persistence/flow_record.ex",
    "lib/storyarn/platform/global_search/persistence/scene_annotation_record.ex",
    "lib/storyarn/platform/global_search/persistence/sheet_record.ex",
    "lib/storyarn/platform/global_search/persistence/table_column_record.ex",
    "lib/storyarn/platform/global_search/persistence/table_row_record.ex",
    "lib/storyarn/platform/global_search/persistence/scene_connection_record.ex",
    "lib/storyarn/platform/global_search/persistence/scene_layer_record.ex",
    "lib/storyarn/platform/global_search/persistence/scene_pin_record.ex",
    "lib/storyarn/platform/global_search/persistence/scene_record.ex",
    "lib/storyarn/platform/global_search/persistence/scene_zone_record.ex",
    "lib/storyarn/platform/global_search/scene_search.ex",
    "lib/storyarn/platform/global_search/sheet_search.ex",
    "lib/storyarn/platform/global_search/variable_query.ex",
    "lib/storyarn/platform/global_search/variable_search.ex",
    "lib/storyarn/platform/emails/layout.ex",
    "lib/storyarn/platform/mailer.ex",
    "lib/storyarn/platform/onboarding.ex",
    "lib/storyarn/platform/onboarding/persistence/user_record.ex",
    "lib/storyarn/platform/onboarding/tutorial_progress.ex",
    "lib/storyarn/public/publication/html_link_localizer.ex",
    "lib/storyarn/public/publication/locales.ex",
    "lib/storyarn/public/publication/path_localizer.ex",
    "lib/storyarn/platform/rate_limiter.ex",
    "lib/storyarn/platform/rate_limiter/",
    "lib/storyarn/platform/release.ex",
    "lib/storyarn/repo.ex",
    "lib/storyarn/platform/shared/canonical_json.ex",
    "lib/storyarn/platform/shared/color_utils.ex",
    "lib/storyarn/platform/shared/encrypted_binary.ex",
    "lib/storyarn/shared/formula_engine.ex",
    "lib/storyarn/shared/formula_runtime.ex",
    "lib/storyarn/shared/hierarchical_schema.ex",
    "lib/storyarn/platform/shared/hierarchy_search.ex",
    "lib/storyarn/platform/shared/html_sanitizer.ex",
    "lib/storyarn/platform/shared/html_utils.ex",
    "lib/storyarn/platform/shared/import_helpers.ex",
    "lib/storyarn/platform/shared/map_utils.ex",
    "lib/storyarn/platform/shared/search_helpers.ex",
    "lib/storyarn/platform/shared/severity.ex",
    "lib/storyarn/shared/shortcut_helpers.ex",
    "lib/storyarn/platform/shared/string_utils.ex",
    "lib/storyarn/platform/shared/time_helpers.ex",
    "lib/storyarn/platform/shared/token_generator.ex",
    "lib/storyarn/shared/tree_operations.ex",
    "lib/storyarn/platform/urls.ex",
    "lib/storyarn/platform/vault.ex",
    # Worker folders are assigned to their sealed owner above. AI remains
    # transitional, so its worker slice and any future unclassified slice fall
    # back to infrastructure instead of becoming a shared business boundary.
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
    "lib/storyarn_web/live/settings_live/sudo.ex",
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

# A Web surface may belong to the same bounded context for ownership and route
# classification, but that must not make the context internals public. Derive
# one denial for every context-owned Web root so future files under those roots
# can call only the root facade. `presentation_adapters` is deliberately absent:
# the router and LiveVue encoders are technical adapters that must name modules
# at compile time and are protected in the opposite direction instead.
web_to_context_internal_denials =
  for context <- bounded_contexts,
      source_root <- Map.fetch!(boundaries, context),
      String.starts_with?(source_root, "lib/storyarn_web/") do
    %{
      source_root: source_root,
      target_root: "lib/storyarn/#{context}/",
      kinds: ["runtime", "export", "compile"],
      reason: "context-owned Web surfaces must enter through the #{context} root facade"
    }
  end

# Accounts capabilities are implementation slices inside one bounded context,
# not independent contexts. `User`, `UserToken`, and `Scope` deliberately keep
# their stable module identities and may be shared inside Accounts; commands,
# queries, rules, adapters, delivery, tokens, and events remain capability-local.
account_capabilities = ~w(identity authentication registration)
account_private_roles = ~w(adapters commands queries rules delivery tokens events)

account_internal_path_denials =
  for source_capability <- account_capabilities,
      target_capability <- account_capabilities -- [source_capability],
      private_role <- account_private_roles do
    %{
      source_root: "lib/storyarn/accounts/#{source_capability}/",
      target_root: "lib/storyarn/accounts/#{target_capability}/#{private_role}/",
      kinds: ["runtime", "export", "compile"],
      reason: "Account capabilities may consume another capability only through its facade or stable contracts"
    }
  end

# These denials protect concrete responsibilities without pretending that every
# module needs a port. Queries remain read-only, rules remain persistence-free,
# tokens cannot trigger workflows, and technical adapters do not orchestrate
# application behavior.
account_role_dependency_denials =
  for capability <- account_capabilities,
      {source_role, target_role} <- [
        {"queries", "commands"},
        {"queries", "delivery"},
        {"queries", "events"},
        {"queries", "adapters"},
        {"rules", "commands"},
        {"rules", "queries"},
        {"rules", "delivery"},
        {"rules", "events"},
        {"rules", "adapters"},
        {"entities", "commands"},
        {"entities", "queries"},
        {"entities", "delivery"},
        {"entities", "events"},
        {"entities", "adapters"},
        {"contracts", "commands"},
        {"contracts", "queries"},
        {"contracts", "delivery"},
        {"contracts", "events"},
        {"contracts", "adapters"},
        {"tokens", "commands"},
        {"tokens", "delivery"},
        {"tokens", "events"},
        {"tokens", "adapters"},
        {"adapters", "commands"},
        {"adapters", "queries"},
        {"adapters", "delivery"},
        {"adapters", "events"},
        {"adapters", "rules"},
        {"adapters", "tokens"}
      ] do
    %{
      source_root: "lib/storyarn/accounts/#{capability}/#{source_role}/",
      target_root: "lib/storyarn/accounts/#{capability}/#{target_role}/",
      kinds: ["runtime", "export", "compile"],
      reason: "Account role folders must preserve read, policy, token, and effect direction"
    }
  end

accounts_worker_facade_denial = %{
  source_root: "lib/storyarn/workers/accounts/",
  target_root: "lib/storyarn/accounts/",
  kinds: ["runtime", "export", "compile"],
  reason: "Account workers must orchestrate through the Storyarn.Accounts facade"
}

# Workspaces capabilities are implementation slices inside one bounded context,
# not independent contexts. They may share owned entities and call one another's
# capability facade, but they must not reach directly into another capability's
# private commands, queries, rules, adapters, or data projections.
workspace_capabilities = ~w(lifecycle memberships invitations banner)
workspace_private_roles = ~w(adapters commands queries rules data delivery tokens events)

workspace_internal_path_denials =
  for source_capability <- workspace_capabilities,
      target_capability <- workspace_capabilities -- [source_capability],
      private_role <- workspace_private_roles do
    %{
      source_root: "lib/storyarn/workspaces/#{source_capability}/",
      target_root: "lib/storyarn/workspaces/#{target_capability}/#{private_role}/",
      kinds: ["runtime", "export", "compile"],
      reason: "Workspace capabilities may share owned entities and consume another capability only through its facade"
    }
  end

# Folder names are directional responsibilities, not labels. Read models and
# passive domain/data modules cannot reach the application operations that
# mutate state or trigger effects inside their own capability.
workspace_role_dependency_denials =
  for capability <- workspace_capabilities,
      {source_role, target_role} <- [
        {"queries", "commands"},
        {"queries", "delivery"},
        {"queries", "events"},
        {"rules", "commands"},
        {"rules", "queries"},
        {"rules", "delivery"},
        {"rules", "events"},
        {"rules", "adapters"},
        {"data", "commands"},
        {"data", "queries"},
        {"data", "delivery"},
        {"data", "events"},
        {"data", "adapters"},
        {"entities", "commands"},
        {"entities", "queries"},
        {"entities", "delivery"},
        {"entities", "events"},
        {"entities", "adapters"},
        {"adapters", "commands"},
        {"adapters", "queries"},
        {"adapters", "data"},
        {"adapters", "entities"},
        {"adapters", "delivery"},
        {"adapters", "events"},
        {"adapters", "rules"},
        {"adapters", "tokens"}
      ] do
    %{
      source_root: "lib/storyarn/workspaces/#{capability}/#{source_role}/",
      target_root: "lib/storyarn/workspaces/#{capability}/#{target_role}/",
      kinds: ["runtime", "export", "compile"],
      reason: "Workspace role folders must preserve read, policy, data, and effect direction"
    }
  end

# Banner has one read adapter: resolving a private storage key. Other queries
# cannot depend on technical adapters, and Banner reads cannot enqueue cleanup.
workspace_query_adapter_denials =
  for capability <- workspace_capabilities -- ["banner"] do
    %{
      source_root: "lib/storyarn/workspaces/#{capability}/queries/",
      target_root: "lib/storyarn/workspaces/#{capability}/adapters/",
      kinds: ["runtime", "export", "compile"],
      reason: "Workspace queries may not trigger technical adapters"
    }
  end ++
    [
      %{
        source_root: "lib/storyarn/workspaces/banner/queries/",
        target_root: "lib/storyarn/workspaces/banner/adapters/cleanup/",
        kinds: ["runtime", "export", "compile"],
        reason: "Workspace banner queries may resolve storage but cannot enqueue cleanup"
      }
    ]

workspace_worker_facade_denial = %{
  source_root: "lib/storyarn/workers/workspaces/",
  target_root: "lib/storyarn/workspaces/",
  kinds: ["runtime", "export", "compile"],
  reason: "Workspace workers must orchestrate through the Storyarn.Workspaces facade"
}

# Localization is one bounded context split into cohesive internal capabilities.
# A capability may consume another capability's facade or a deliberately stable
# entity/contract identity, but its data projections and operational roles stay
# private to the capability that owns them.
localization_capabilities = ~w(access languages texts providers glossary translation exchange reporting)
localization_private_roles = ~w(adapters commands queries rules data execution)

localization_internal_path_denials =
  for source_capability <- localization_capabilities,
      target_capability <- localization_capabilities -- [source_capability],
      private_role <- localization_private_roles do
    %{
      source_root: "lib/storyarn/localization/#{source_capability}/",
      target_root: "lib/storyarn/localization/#{target_capability}/#{private_role}/",
      kinds: ["runtime", "export", "compile"],
      reason: "Localization capabilities may consume another capability only through its facade or stable contracts"
    }
  end

# Role folders express direction without imposing ports on every module. Reads,
# pure rules, passive data, entities, contracts, and technical adapters cannot
# become hidden application orchestrators.
localization_role_dependency_denials =
  for capability <- localization_capabilities,
      {source_role, target_role} <- [
        {"queries", "commands"},
        {"queries", "execution"},
        {"queries", "adapters"},
        {"rules", "commands"},
        {"rules", "queries"},
        {"rules", "execution"},
        {"rules", "adapters"},
        {"data", "commands"},
        {"data", "queries"},
        {"data", "execution"},
        {"data", "adapters"},
        {"data", "rules"},
        {"entities", "commands"},
        {"entities", "queries"},
        {"entities", "execution"},
        {"entities", "adapters"},
        {"contracts", "commands"},
        {"contracts", "queries"},
        {"contracts", "execution"},
        {"contracts", "adapters"},
        {"adapters", "commands"},
        {"adapters", "queries"},
        {"adapters", "execution"}
      ] do
    %{
      source_root: "lib/storyarn/localization/#{capability}/#{source_role}/",
      target_root: "lib/storyarn/localization/#{capability}/#{target_role}/",
      kinds: ["runtime", "export", "compile"],
      reason: "Localization role folders must preserve read, policy, data, and effect direction"
    }
  end

localization_worker_facade_denial = %{
  source_root: "lib/storyarn/workers/localization/",
  target_root: "lib/storyarn/localization/",
  kinds: ["runtime", "export", "compile"],
  reason: "Localization workers must orchestrate through the Storyarn.Localization facade"
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

policy = %{
  version: 2,
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
  path_denials:
    [
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
    ] ++
      web_to_context_internal_denials ++
      account_internal_path_denials ++
      account_role_dependency_denials ++
      [accounts_worker_facade_denial] ++
      workspace_internal_path_denials ++
      workspace_role_dependency_denials ++
      workspace_query_adapter_denials ++
      [workspace_worker_facade_denial] ++
      localization_internal_path_denials ++
      localization_role_dependency_denials ++ [localization_worker_facade_denial],

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

  # These exact leaves are globally consumable technical infrastructure, not
  # bounded-context APIs. They deliberately cover no directory: Repo remains
  # shared during ENG-92; the other entries are stable primitives, adapters or
  # execution plumbing with no consumer-specific business policy. Adding a
  # target here is an architecture decision because it grants every boundary
  # access without registering each source edge.
  globally_allowed_technical_targets: [
    "lib/storyarn/repo.ex",
    "lib/storyarn/gettext.ex",
    "lib/storyarn/projects/assets/storage.ex",
    "lib/storyarn/projects/assets/storage_hash.ex",
    "lib/storyarn/projects/assets/storage_key_lock.ex",
    "lib/storyarn/platform/dashboards/cache.ex",
    "lib/storyarn/platform/collaboration.ex",
    "lib/storyarn/platform/emails/layout.ex",
    "lib/storyarn/platform/feature_flags.ex",
    "lib/storyarn/platform/mailer.ex",
    "lib/storyarn/platform/rate_limiter.ex",
    "lib/storyarn/platform/urls.ex",
    "lib/storyarn/platform/shared/color_utils.ex",
    "lib/storyarn/platform/shared/encrypted_binary.ex",
    "lib/storyarn/platform/shared/html_sanitizer.ex",
    "lib/storyarn/platform/shared/html_utils.ex",
    "lib/storyarn/platform/shared/map_utils.ex",
    "lib/storyarn/platform/shared/search_helpers.ex",
    "lib/storyarn/platform/shared/string_utils.ex",
    "lib/storyarn/platform/shared/time_helpers.ex",
    "lib/storyarn/platform/shared/token_generator.ex"
  ],

  # Durable cross-boundary contracts normally terminate at one of the eight
  # bounded-context root facades. These are the only additional exact targets
  # that may terminate a reviewed durable edge. Unlike the global technical
  # leaves above, listing a target here grants no access by itself. This also
  # models AI's current public SPI honestly while AI remains an unsealed product
  # context during this pass.
  additional_durable_contract_targets: [
    %{
      target: "lib/storyarn/ai.ex",
      reason: "AI remains an unsealed bounded context, but consumers still enter through its public root facade"
    },
    %{
      target: "lib/storyarn/ai/context/contract.ex",
      reason: "consumer-owned AI context builders implement the shared AI context contract"
    },
    %{
      target: "lib/storyarn/ai/context/policy.ex",
      reason: "consumer-owned AI context builders export the AI policy value"
    },
    %{
      target: "lib/storyarn/ai/context/subject_ref.ex",
      reason: "consumer-owned AI context builders export AI subject references"
    },
    %{
      target: "lib/storyarn/platform/vault.ex",
      reason: "Encrypted import payloads use the application-owned cryptographic adapter"
    },
    %{
      target: "lib/storyarn/platform/analytics.ex",
      reason: "Platform product metrics alone may enter the exact analytics transport contract"
    },
    %{
      target: "lib/storyarn/platform/analytics/event_contract.ex",
      reason: "Platform product metrics implements the exact fail-closed analytics transport contract"
    },
    %{
      target: "lib/storyarn/public/publication/locales.ex",
      reason: "Invitation presentation adapters consume the exact read-only public locale policy"
    },
    %{
      target: "lib/storyarn_web/endpoint.ex",
      reason: "The OTP composition root and URL adapter consume the configured Phoenix endpoint"
    },
    %{
      target: "lib/storyarn_web/telemetry.ex",
      reason: "The OTP composition root starts the Web telemetry supervisor"
    }
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

  # Each edge below is exact and reviewed. Policy v2 partitions the list after
  # construction: a dependency terminating at a root facade or explicit
  # technical contract is durable; every dependency terminating at an internal
  # module remains visible as migration debt. The checker rejects stale entries
  # in both groups, so deleting an edge must also repay its policy entry.
  reviewed_cross_boundary_edges: [
    %{
      source: "lib/storyarn/flows/ai/context_contract.ex",
      target: "lib/storyarn/ai/context/contract.ex",
      kinds: ["runtime"],
      reason: "Flows implements the exact public AI context-builder contract"
    },
    %{
      source: "lib/storyarn/flows/ai/context_contract.ex",
      target: "lib/storyarn/ai/context/policy.ex",
      kinds: ["export"],
      reason: "Flows exports the public AI context policy value in its implementation"
    },
    %{
      source: "lib/storyarn/flows/ai/context_contract.ex",
      target: "lib/storyarn/ai/context/subject_ref.ex",
      kinds: ["export"],
      reason: "Flows exports the public AI subject reference in its implementation"
    },
    %{
      source: "lib/storyarn/sheets/ai/context_contract.ex",
      target: "lib/storyarn/ai/context/contract.ex",
      kinds: ["runtime"],
      reason: "Sheets implements the exact public AI context-builder contract"
    },
    %{
      source: "lib/storyarn/sheets/ai/context_contract.ex",
      target: "lib/storyarn/ai/context/policy.ex",
      kinds: ["export"],
      reason: "Sheets exports the public AI context policy value in its implementation"
    },
    %{
      source: "lib/storyarn/sheets/ai/context_contract.ex",
      target: "lib/storyarn/ai/context/subject_ref.ex",
      kinds: ["export"],
      reason: "Sheets exports the public AI subject reference in its implementation"
    },
    %{
      source: "lib/storyarn_web/live/hooks/notifications.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "The notifications hook subscribes and marks read state through the public Platform facade"
    },
    %{
      source: "lib/storyarn_web/live/hooks/palette.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Palette operations publish committed notification outcomes through the public Platform facade"
    },
    %{
      source: "lib/storyarn_web/live/shared/notification_helpers.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "The shared notification helpers list and count through the public Platform facade"
    },
    %{
      source: "lib/storyarn/workers/platform/deliver_invitation_worker.ex",
      target: "lib/storyarn/projects.ex",
      kinds: ["runtime"],
      reason: "The durable invitation delivery worker calls back into the public Projects facade to render and send"
    },
    %{
      source: "lib/storyarn/application.ex",
      target: "lib/storyarn/projects.ex",
      kinds: ["runtime"],
      reason: "OTP composition root obtains the import error deduplicator child spec through the public Projects facade"
    },
    %{
      source: "lib/storyarn/platform/global_search/destinations.ex",
      target: "lib/storyarn/projects.ex",
      kinds: ["runtime"],
      reason: "Global search resolves reachable projects through the public Projects access reads"
    },
    %{
      source: "lib/storyarn/platform/global_search/variable_search.ex",
      target: "lib/storyarn/projects.ex",
      kinds: ["runtime"],
      reason: "Global variable search reads Project-owned occurrences through the public Projects facade"
    },
    %{
      source: "lib/storyarn/platform/release.ex",
      target: "lib/storyarn/projects.ex",
      kinds: ["runtime"],
      reason: "Release CLI tasks operate on projects through the public Projects facade"
    },
    %{
      source: "lib/storyarn_web/components/project_layout.ex",
      target: "lib/storyarn/projects.ex",
      kinds: ["runtime"],
      reason: "The project shell resolves navigation state through the public Projects facade"
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
      source: "lib/storyarn/projects/assets.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Asset lifecycle accounts storage usage through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/assets/asset_trash.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Asset lifecycle accounts storage usage through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/assets/blob_store.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Asset lifecycle accounts storage usage through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/imports/execution.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason:
        "Project imports enforce storage policy and publish committed notifications through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/imports/expiration.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Project imports publish committed notification outcomes through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/imports/materializer.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Project imports enforce storage policy through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/imports/notification_delivery.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Project imports prepare durable notification delivery through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/imports/plan_storage.ex",
      target: "lib/storyarn/platform/vault.ex",
      kinds: ["runtime"],
      reason: "Import plan storage encrypts payloads with the application vault"
    },
    %{
      source: "lib/storyarn/projects/imports/replacement.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Project replacement imports coordinate storage locks through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/imports/resume.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Project imports publish committed notification outcomes through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/project_templates/installation.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason:
        "Template installation enforces commercial policy and publishes notification outcomes through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/project_templates/publication_runner.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Template publication enforces commercial policy through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/project_crud.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Project lifecycle enforces commercial policy through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/platform_storage_reservations.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason:
        "The Projects anti-corruption layer exchanges transport-neutral storage receipts through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/project_trash.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Project lifecycle enforces commercial policy through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/invitation_email.ex",
      target: "lib/storyarn/platform/emails/layout.ex",
      kinds: ["runtime"],
      reason: "Project-owned invitation content uses the shared technical email layout"
    },
    %{
      source: "lib/storyarn/projects/invitation_notifier.ex",
      target: "lib/storyarn/platform/mailer.ex",
      kinds: ["runtime"],
      reason: "Project invitation delivery goes through the application mailer"
    },
    %{
      source: "lib/storyarn/projects/invitation_operations.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Project invitations enforce seat policy and request durable delivery through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/versioning.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Snapshot storage lifecycle accounts usage and locks through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/versioning/materialization_helpers.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Snapshot materialization accounts storage through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/versioning/project_recovery.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Project recovery coordinates storage locks through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/versioning/project_snapshot_lease_policy.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Project snapshot grants consume the lease policy through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/versioning/project_snapshot_asset_materializer.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Snapshot asset materialization accounts storage through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/versioning/project_snapshot_build.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Snapshot builds coordinate storage and publish notification outcomes through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/versioning/project_snapshot_crud.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Snapshot lifecycle accounts storage and locks through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/versioning/project_snapshot_download.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Snapshot downloads acquire storage leases through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/versioning/project_snapshot_lifecycle.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Snapshot lifecycle accounts storage and locks through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/versioning/project_snapshot_reconciliation_repair.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Snapshot reconciliation repairs storage accounting through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/versioning/project_snapshot_restore_lifecycle.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Snapshot restore lifecycle accounts storage and locks through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/versioning/workspace_snapshot_imports.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason:
        "Workspace snapshot imports coordinate storage and publish notification outcomes through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/snapshot_accounting.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason:
        "Projects consumes neutral storage usage, reservation totals and entitlements through the public Platform facade"
    },
    %{
      source: "lib/storyarn_web/live/project_live/invitation.ex",
      target: "lib/storyarn/public/publication/locales.ex",
      kinds: ["runtime"],
      reason: "Invitation pages normalize the public locale like the other public-facing pages"
    },
    %{
      source: "lib/storyarn_web/live/project_settings_live/usage_limits.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Project settings pages show plan usage through the public Platform facade"
    },
    %{
      source: "lib/storyarn_web/live/project_settings_live/version_control.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Project settings pages show plan usage through the public Platform facade"
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
      source: "lib/storyarn/localization/languages/adapters/notifications/delivery.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Localization language changes request durable cross-cutting delivery through the public Platform contract"
    },
    %{
      source: "lib/storyarn/localization/translation/adapters/notifications/delivery.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Localization translation runs request durable cross-cutting delivery through the public Platform contract"
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
      source: "lib/storyarn/workspaces/lifecycle/commands/create_workspace.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Workspace creation applies commercial limits and subscriptions through the public Platform facade"
    },
    %{
      source: "lib/storyarn/workspaces/lifecycle/commands/delete_workspace.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Workspace hard-delete executes under the Platform-owned workspace lifecycle lock"
    },
    %{
      source: "lib/storyarn/workspaces/lifecycle/commands/delete_workspace.ex",
      target: "lib/storyarn/projects.ex",
      kinds: ["runtime"],
      reason:
        "Workspace hard-delete asks the public Projects facade to prepare all Project-owned dependent data under the caller-held workspace lock"
    },
    %{
      source: "lib/storyarn/accounts/authentication/events/user_logged_in.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Authentication publishes the Account-owned login fact through the public Platform reaction contract"
    },
    %{
      source: "lib/storyarn/accounts/registration/events/user_signed_up.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Registration publishes the Account-owned sign-up fact through the public Platform reaction contract"
    },
    %{
      source: "lib/storyarn_web/user_auth.ex",
      target: "lib/storyarn/accounts.ex",
      kinds: ["runtime"],
      reason: "Session authentication resolves users and tokens through the public Accounts facade"
    },
    %{
      source: "lib/storyarn_web/live/project_live/invitation.ex",
      target: "lib/storyarn/accounts.ex",
      kinds: ["runtime"],
      reason: "Invitation acceptance prepares the invited account through the public Accounts facade"
    },
    %{
      source: "lib/storyarn/accounts/authentication/delivery/email_change/content.ex",
      target: "lib/storyarn/platform/emails/layout.ex",
      kinds: ["runtime"],
      reason: "Account-owned email-change content uses the shared technical email layout"
    },
    %{
      source: "lib/storyarn/accounts/authentication/delivery/password_reset/content.ex",
      target: "lib/storyarn/platform/emails/layout.ex",
      kinds: ["runtime"],
      reason: "Account-owned password-reset content uses the shared technical email layout"
    },
    %{
      source: "lib/storyarn/accounts/authentication/adapters/email/mailer.ex",
      target: "lib/storyarn/platform/mailer.ex",
      kinds: ["runtime"],
      reason: "The Account email adapter hands rendered messages to the application mailer"
    },
    %{
      source: "lib/storyarn_web/live/user_live/login.ex",
      target: "lib/storyarn/platform/mailer.ex",
      kinds: ["runtime"],
      reason: "The login page offers the local dev mailbox link by inspecting the configured mailer adapter"
    },
    %{
      source: "lib/storyarn/workspaces/lifecycle/events/workspace_created.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Workspaces publishes the typed workspace-created fact through the public Platform reaction contract"
    },
    %{
      source: "lib/storyarn/workspaces/invitations/commands/create.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Workspace invitation creation applies Platform-owned member seat policy"
    },
    %{
      source: "lib/storyarn/workspaces/invitations/commands/accept.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Workspace invitation acceptance applies Platform-owned member seat policy"
    },
    %{
      source: "lib/storyarn/workspaces/invitations/adapters/delivery/request.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Workspace invitations request durable delivery through the public Platform facade"
    },
    %{
      source: "lib/storyarn/workspaces/invitations/delivery/content.ex",
      target: "lib/storyarn/platform/emails/layout.ex",
      kinds: ["runtime"],
      reason: "Workspace-owned invitation content uses the shared technical email layout"
    },
    %{
      source: "lib/storyarn/workspaces/invitations/adapters/email/mailer.ex",
      target: "lib/storyarn/platform/mailer.ex",
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
      source: "lib/storyarn_web/live/settings_live/workspace_imports.ex",
      target: "lib/storyarn/projects.ex",
      kinds: ["runtime"],
      reason: "Workspace snapshot imports are requested and tracked through the public Projects facade"
    },
    %{
      source: "lib/storyarn_web/live/workspace_live/invitation.ex",
      target: "lib/storyarn/accounts.ex",
      kinds: ["runtime"],
      reason: "Invitation acceptance prepares the invited account through the public Accounts facade"
    },
    %{
      source: "lib/storyarn_web/live/workspace_live/invitation.ex",
      target: "lib/storyarn/public/publication/locales.ex",
      kinds: ["runtime"],
      reason: "Invitation pages normalize the public locale like the other public-facing pages"
    },
    %{
      source: "lib/storyarn_web/live/workspace_live/show.ex",
      target: "lib/storyarn/projects.ex",
      kinds: ["runtime"],
      reason: "The workspace home lists and creates projects through the public Projects facade"
    },
    %{
      source: "lib/storyarn/accounts/registration/commands/register.ex",
      target: "lib/storyarn/workspaces.ex",
      kinds: ["runtime"],
      reason: "Registration provisions each new account's default workspace through the public Workspaces facade"
    },
    %{
      source: "lib/storyarn/platform/global_search/destinations.ex",
      target: "lib/storyarn/workspaces.ex",
      kinds: ["runtime"],
      reason: "Global search resolves reachable workspaces through the public Workspaces access reads"
    },
    %{
      source: "lib/storyarn/platform/release.ex",
      target: "lib/storyarn/workspaces.ex",
      kinds: ["runtime"],
      reason: "Release CLI tasks operate on workspaces through the public Workspaces facade"
    },
    %{
      source: "lib/storyarn/workers/platform/deliver_invitation_worker.ex",
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
      source: "lib/storyarn_web/user_auth.ex",
      target: "lib/storyarn/workspaces.ex",
      kinds: ["runtime"],
      reason: "Session plumbing resolves the user's workspaces through the public Workspaces facade"
    },
    %{
      source: "lib/storyarn/platform/global_search/variable_search.ex",
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
      target: "lib/storyarn/platform/analytics.ex",
      kinds: ["runtime"],
      reason: "Platform product metrics owns the only new product-context access to the analytics transport"
    },
    %{
      source: "lib/storyarn/platform/product_metrics.ex",
      target: "lib/storyarn/platform/analytics/event_contract.ex",
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
      reason:
        "The workspace home reads plan policy and presents product metric taxonomy through the public Platform facade"
    },
    %{
      source: "lib/storyarn/platform/urls.ex",
      target: "lib/storyarn_web/endpoint.ex",
      kinds: ["runtime"],
      reason: "Technical URL resolution reads the configured Phoenix endpoint without calling Web behavior"
    }
  ]
}

durable_targets =
  Enum.map(bounded_contexts, &"lib/storyarn/#{&1}.ex") ++
    policy.globally_allowed_technical_targets ++
    Enum.map(policy.additional_durable_contract_targets, & &1.target)

{durable_contracts, migration_exceptions} =
  Enum.split_with(policy.reviewed_cross_boundary_edges, &(&1.target in durable_targets))

policy
|> Map.delete(:reviewed_cross_boundary_edges)
|> Map.put(:durable_contracts, durable_contracts)
|> Map.put(:migration_exceptions, migration_exceptions)
