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
    "lib/storyarn/versioning.ex",
    "lib/storyarn/versioning/",
    "lib/storyarn/exports.ex",
    "lib/storyarn/exports/",
    "lib/storyarn/imports.ex",
    "lib/storyarn/imports/",
    "lib/storyarn/project_templates.ex",
    "lib/storyarn/project_templates/",
    "lib/storyarn/shortcuts.ex",
    "lib/storyarn/workers/trash_retention_worker.ex",
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
    "lib/storyarn/ai/personal_consent.ex",
    "lib/storyarn/ai/personal_consents.ex",
    "lib/storyarn/ai/personal_preference.ex",
    "lib/storyarn/ai/personal_preferences.ex",
    "lib/storyarn/ai/personal_providers.ex",
    "lib/storyarn/ai/personal_roles.ex",
    "lib/storyarn/ai/policy.ex",
    "lib/storyarn/ai/policy_decision.ex",
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
    "lib/storyarn/global_search/persistence/flow_connection_record.ex",
    "lib/storyarn/global_search/persistence/flow_node_record.ex",
    "lib/storyarn/global_search/persistence/flow_record.ex",
    "lib/storyarn/global_search/persistence/scene_annotation_record.ex",
    "lib/storyarn/global_search/persistence/scene_connection_record.ex",
    "lib/storyarn/global_search/persistence/scene_layer_record.ex",
    "lib/storyarn/global_search/persistence/scene_pin_record.ex",
    "lib/storyarn/global_search/persistence/scene_record.ex",
    "lib/storyarn/global_search/persistence/scene_zone_record.ex",
    "lib/storyarn/global_search/scene_search.ex",
    "lib/storyarn/global_search/variable_query.ex",
    "lib/storyarn/global_search/variable_search.ex",
    "lib/storyarn/mailer.ex",
    "lib/storyarn/onboarding.ex",
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
    "lib/storyarn/shared/invitation_notifier.ex",
    "lib/storyarn/shared/invitation_operations.ex",
    "lib/storyarn/shared/invitation_schema.ex",
    "lib/storyarn/shared/map_utils.ex",
    "lib/storyarn/shared/membership_operations.ex",
    "lib/storyarn/shared/name_normalizer.ex",
    "lib/storyarn/shared/search_helpers.ex",
    "lib/storyarn/shared/severity.ex",
    "lib/storyarn/shared/shortcut_helpers.ex",
    "lib/storyarn/shared/string_utils.ex",
    "lib/storyarn/shared/time_helpers.ex",
    "lib/storyarn/shared/token_generator.ex",
    "lib/storyarn/shared/tree_operations.ex",
    "lib/storyarn/shared/validations.ex",
    "lib/storyarn/shared/word_count.ex",
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
  # when the current xref graph contains the exact same edge.
  zero_debt_consumers: [:flows, :scenes, :localization],

  # Flows, Scenes and Localization are sealed in both directions. Durable coordinator
  # access to their public facades must use an exact exception; it cannot be
  # accepted by adding an inbound edge to another consumer's debt baseline.
  isolated_contexts: [:flows, :scenes, :localization],

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
