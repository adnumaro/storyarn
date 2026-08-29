# ENG-92 code boundaries plus incremental ENG-103 persistence ownership. The
# shared schema remains intentional; semantic write authority is added one
# reviewed table/workflow at a time instead of inferred from Ecto module names.

# These are the bounded contexts sealed by the current ENG-92 ratchet.
bounded_contexts = [:accounts, :workspaces, :platform, :projects, :sheets, :flows, :scenes, :localization, :ai]

# ENG-110 is the first persistence-ownership slice under ENG-103. Localization
# owns every ordinary write to `project_languages`. Projects keeps an independent
# record because template materialization, exact import/reconstitution and
# snapshot recovery still need to materialize the shared SQL state without
# importing Localization internals.
# Every statically identifiable foreign schema, alias consumer and direct SQL
# reference is classified explicitly. Raw SQL that reaches an ownership-sensitive
# path but cannot be resolved statically fails closed in the architecture test;
# this remains a source-level ratchet rather than a database security boundary.
project_language_persistence_ownership = %{
  table: "project_languages",
  ordinary_owner: :localization,
  owner_paths: ["lib/storyarn/localization.ex", "lib/storyarn/localization/"],
  ordinary_writers: [
    %{
      path: "lib/storyarn/localization/languages/commands/add.ex",
      role: :command,
      reason: "adds or reactivates a Project language and reconciles its localized-text inventory",
      transaction: "runs inside the command's Repo.transaction",
      locks_or_preconditions: "locks the project and localization inventory before mutation"
    },
    %{
      path: "lib/storyarn/localization/languages/commands/change_source.ex",
      role: :command,
      reason: "owns ordinary source-language promotion and optional translation reset",
      transaction: "runs inside the command's Repo.transaction",
      locks_or_preconditions: "locks the project and localization inventory before mutation"
    },
    %{
      path: "lib/storyarn/localization/languages/commands/remove.ex",
      role: :command,
      reason: "archives an ordinary target language and its localized-text inventory",
      transaction: "runs inside the command's Repo.transaction",
      locks_or_preconditions: "locks the project, localization inventory and selected language before mutation"
    },
    %{
      path: "lib/storyarn/localization/languages/commands/reorder.ex",
      role: :command_orchestrator,
      reason: "owns ordinary language ordering and delegates the set-based write to the declared adapter",
      transaction: "runs inside the command's Repo.transaction",
      locks_or_preconditions: "locks the project and every active language row before delegating the position update"
    },
    %{
      path: "lib/storyarn/localization/languages/commands/update.ex",
      role: :command,
      reason: "updates ordinary language metadata",
      transaction: "runs inside the command's Repo.transaction",
      locks_or_preconditions: "locks the project, localization inventory and selected language before mutation"
    },
    %{
      path: "lib/storyarn/localization/languages/adapters/positions/postgres.ex",
      role: :persistence_adapter,
      reason: "the reorder command delegates its set-based position update to one PostgreSQL adapter",
      transaction: "called inside Languages.Commands.Reorder's Repo.transaction",
      locks_or_preconditions:
        "the reorder command locks the project and every active language row before calling the adapter"
    }
  ],
  foreign_schema_mappings: %{
    flows: [
      "lib/storyarn/flows/localization/projections/project_language_record.ex",
      "lib/storyarn/flows/versioning/projections/project_language_record.ex"
    ],
    sheets: [
      "lib/storyarn/sheets/localization/projections/project_language_record.ex",
      "lib/storyarn/sheets/versioning/projections/project_language_record.ex"
    ]
  },
  privileged_project_schema_mappings: [
    "lib/storyarn/projects/content/localization/records/project_language_record.ex"
  ],
  foreign_readers: %{
    projects: [
      "lib/storyarn/projects/content/localization/queries/read_model.ex",
      "lib/storyarn/projects/interchange/exports/queries/data_collector.ex",
      "lib/storyarn/projects/templates/execution/audit.ex"
    ]
  },
  # These consumers read project_languages but also contain already-reviewed
  # writes to other shared tables. They are not labelled read-only: their
  # remaining write ownership is explicit ENG-103 debt rather than permission
  # to write project_languages.
  reviewed_mixed_foreign_consumers: [
    %{
      path: "lib/storyarn/flows/localization/commands/projection.ex",
      owner: :flows,
      reason: "reads target locales while maintaining the existing localized_texts projection",
      reviewed_sha256: "1a7511c20d0aa250eb8bae25ecae999ff1e9edbf18efe04456142be63d0320c4"
    },
    %{
      path: "lib/storyarn/flows/versioning/execution/localization_codec.ex",
      owner: :flows,
      reason: "reads the locale inventory while restoring Flow-owned localized_texts",
      reviewed_sha256: "be39d949a298e3b65e962b424272c349ab6b01279be486fdf8147cbf6b7fc5c5"
    },
    %{
      path: "lib/storyarn/projects/content/localization/commands/flow_projection.ex",
      owner: :projects,
      reason: "reads target locales while maintaining Project's derived localized_text inventory",
      reviewed_sha256: "0d19c72cc1cdc8d8301de010c6ee4267f9f08d256d6fc1a21ecbc491881ab466"
    },
    %{
      path: "lib/storyarn/projects/content/localization/commands/projection.ex",
      owner: :projects,
      reason: "reads target locales while maintaining Project's derived localized_text inventory",
      reviewed_sha256: "a3aff62f8f7437269be0581509d25aa68887e8b5f1f9256eb21552a76661199f"
    },
    %{
      path: "lib/storyarn/projects/versioning/execution/localization_snapshot_codec.ex",
      owner: :projects,
      reason: "reads locale identity while restoring snapshot-local localized_text records",
      reviewed_sha256: "b8bab630fd112d6654900bfb52ae0f91698d52bde7e2f82a10e414e6e616446a"
    },
    %{
      path: "lib/storyarn/sheets/localization/commands/projection.ex",
      owner: :sheets,
      reason: "reads target locales while maintaining the existing localized_texts projection",
      reviewed_sha256: "7ff2b55117e1257853b558162d2feedd4b6358debb280f7502537531c1b99b26"
    },
    %{
      path: "lib/storyarn/sheets/versioning/execution/localization_codec.ex",
      owner: :sheets,
      reason: "reads the locale inventory while restoring Sheet-owned localized_texts",
      reviewed_sha256: "0bb7786786415f529dd947e716052d866c25ba1daea42355b0bb11f6337b292a"
    }
  ],
  restricted_entrypoints: [
    %{
      module: "Storyarn.Localization.Languages.Adapters.Positions.Postgres",
      path: "lib/storyarn/localization/languages/adapters/positions/postgres.ex",
      allowed_callers: [
        "lib/storyarn/localization/languages/commands/reorder.ex"
      ],
      reason: "only the locked Localization reorder command may invoke the raw set-based position writer"
    },
    %{
      module: "Storyarn.Projects.LocalizationReconstitution",
      path: "lib/storyarn/projects/interchange/imports/commands/localization_reconstitution.ex",
      allowed_callers: [
        "lib/storyarn/projects/interchange/imports/execution/materializer.ex"
      ],
      reason: "only the validated Project import materializer may invoke exact Localization reconstitution"
    }
  ],
  privileged_project_writers: %{
    import_reconstitution: %{
      operation: "exact Project import/reconstitution, including replacement import",
      writers: [
        %{
          path: "lib/storyarn/projects/interchange/imports/commands/localization_reconstitution.ex",
          functions: [{:def, :import_language, 2}]
        },
        %{
          path: "lib/storyarn/projects/interchange/imports/commands/replacement.ex",
          functions: [{:defp, :archive_active_localization, 1}]
        }
      ],
      reason: "a Project import must materialize the imported language rows without importing Localization internals",
      transaction: "runs inside the enclosing validated Project import transaction",
      locks_or_preconditions:
        "validated import/project identity; materialization requires the workspace lock and an active project row locked FOR UPDATE; replacement also validates and locks its recovery snapshot state"
    },
    project_materialization_and_recovery: %{
      operation: "template materialization, exact snapshot import, full-project snapshot restore and recovery",
      writers: [
        %{
          path: "lib/storyarn/projects/versioning/execution/project_recovery.ex",
          functions: [{:defp, :restore_languages, 4}]
        },
        %{
          path: "lib/storyarn/projects/versioning/execution/project_snapshot_restore_executor.ex",
          functions: [{:defp, :reconcile_localization_before_materialization, 2}]
        }
      ],
      reason:
        "Project materialization must create or replace the closed Project graph, including its captured language rows",
      transaction:
        "ProjectRecovery uses the workspace storage-accounting transaction; snapshot restore uses its enclosing restore transaction",
      locks_or_preconditions:
        "ProjectRecovery validates the portable or exact snapshot under the workspace lock; restore validates project/snapshot identity and holds its project, snapshot and materialization locks"
    },
    # No current repair writes `project_languages`. A future repair must name its
    # exact source here and prove its privileged, non-ordinary contract in tests.
    repair: %{
      operation: "reserved Project repair exception",
      writers: [],
      reason: "no current Project repair is authorized to mutate project_languages",
      transaction: "must be declared before the first repair path is added",
      locks_or_preconditions: "must be declared before the first repair path is added"
    }
  }
}

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
    "lib/storyarn/platform/commercial/",
    "lib/storyarn/platform/notifications/",
    "lib/storyarn/platform/onboarding/",
    "lib/storyarn/platform/object_storage.ex",
    "lib/storyarn/platform/object_storage/",
    "lib/storyarn/platform/reactions/reactions.ex",
    "lib/storyarn/platform/reactions/contracts/event_reaction.ex",
    "lib/storyarn/platform/reactions/reference_data/",
    "lib/storyarn/platform/reactions/events/",
    "lib/storyarn/platform/reactions/execution/"
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
    "lib/storyarn_web/controllers/export_controller.ex",
    "lib/storyarn_web/controllers/private_media_controller.ex",
    "lib/storyarn_web/controllers/snapshot_download_controller.ex",
    "lib/storyarn_web/controllers/upload_controller.ex",
    "lib/storyarn_web/live/asset_live/",
    "lib/storyarn_web/live/asset_sidebar_live.ex",
    "lib/storyarn_web/live/project_live/",
    "lib/storyarn_web/live/project_settings_live/",
    "lib/storyarn_web/live/project_sidebar_live.ex",
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
  ai: [
    "lib/storyarn/ai.ex",
    "lib/storyarn/ai/",
    "lib/storyarn/workers/ai/",
    "lib/storyarn_web/live/settings_live/ai_team.ex",
    "lib/storyarn_web/live/settings_live/ai_team_overview.ex",
    "lib/storyarn_web/live/settings_live/integration_detail.ex",
    "lib/storyarn_web/live/settings_live/integrations.ex"
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

  # Explicit technical/application namespaces. There is deliberately no
  # `lib/storyarn/` catch-all: an unlisted namespace must fail until its ownership
  # is reviewed.
  infrastructure: [
    "lib/mix/tasks/architecture_check.ex",
    "lib/mix/tasks/convention_check.ex",
    "lib/mix/tasks/storyarn.ai.diagnose.ex",
    "lib/mix/tasks/storyarn.ai.grant.ex",
    "lib/mix/tasks/storyarn.snapshot_archive_smoke.ex",
    "lib/mix/tasks/storyarn.templates.export.ex",
    "lib/mix/tasks/storyarn.templates.import.ex",
    "lib/storyarn.ex",
    "lib/storyarn/application.ex",
    "lib/storyarn/architecture/",
    "lib/storyarn/public/blog.ex",
    "lib/storyarn/public/blog/post.ex",
    "lib/storyarn/public/blog/post_builder.ex",
    "lib/storyarn/platform/collaboration/",
    "lib/storyarn/platform/discovery/",
    "lib/storyarn/public/docs.ex",
    "lib/storyarn/public/docs/guide.ex",
    "lib/storyarn/public/docs/guide_builder.ex",
    "lib/storyarn/gettext.ex",
    "lib/storyarn/platform/adapters/",
    "lib/storyarn/platform/kernel/",
    "lib/storyarn/platform/reactions/adapters/",
    "lib/storyarn/platform/reactions/contracts/analytics_event_contract.ex",
    "lib/storyarn/public/publication/html_link_localizer.ex",
    "lib/storyarn/public/publication/locales.ex",
    "lib/storyarn/public/publication/path_localizer.ex",
    "lib/storyarn/repo.ex",
    "lib/storyarn/release.ex"
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

workspace_private_roles =
  ~w(adapters commands queries rules projections reference_data delivery tokens events)

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
        {"projections", "commands"},
        {"projections", "queries"},
        {"projections", "delivery"},
        {"projections", "events"},
        {"projections", "adapters"},
        {"reference_data", "commands"},
        {"reference_data", "queries"},
        {"reference_data", "delivery"},
        {"reference_data", "events"},
        {"reference_data", "adapters"},
        {"entities", "commands"},
        {"entities", "queries"},
        {"entities", "delivery"},
        {"entities", "events"},
        {"entities", "adapters"},
        {"adapters", "commands"},
        {"adapters", "queries"},
        {"adapters", "projections"},
        {"adapters", "reference_data"},
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

# Projects is one bounded context with nine business capabilities. `content/`
# is deliberately not a tenth capability: it is a closed, Project-owned model
# shared only by Projects internals for whole-project workflows. Stable
# entities and contracts may cross capability lines;
# operational role folders remain private unless an existing workflow requires
# one of the explicit seams below.
project_capabilities = ~w(lifecycle access assets overview trash references interchange templates versioning)

project_private_role_roots = %{
  "lifecycle" => ~w(commands events projections queries reference_data rules),
  "access" => ~w(adapters commands delivery queries),
  "assets" => ~w(adapters commands execution projections queries rules),
  "overview" => ~w(execution queries rules),
  "trash" => ~w(execution),
  "references" => ~w(commands execution projections queries records reference_data rules),
  "interchange" => ~w(
    imports/adapters imports/commands imports/execution imports/queries imports/rules
    exports/adapters exports/queries exports/rules
  ),
  "templates" => ~w(adapters commands execution queries rules),
  "versioning" => ~w(adapters commands execution projections queries rules)
}

# These are the inherited, currently exercised capability-to-role seams. The
# checker still rejects every new private role dependency outside this matrix.
# Removing a seam from code should be followed by removing its tuple here.
project_private_role_compatibility =
  MapSet.new([
    {"access", "lifecycle", "projections"},
    {"access", "lifecycle", "rules"},
    {"assets", "lifecycle", "projections"},
    {"assets", "lifecycle", "events"},
    {"assets", "references", "commands"},
    {"assets", "versioning", "projections"},
    {"assets", "versioning", "execution"},
    {"interchange", "assets", "adapters"},
    {"interchange", "lifecycle", "projections"},
    {"interchange", "lifecycle", "rules"},
    {"interchange", "overview", "queries"},
    {"interchange", "references", "commands"},
    {"interchange", "trash", "execution"},
    {"interchange", "versioning", "adapters"},
    {"interchange", "versioning", "execution"},
    {"lifecycle", "access", "queries"},
    {"overview", "references", "records"},
    {"overview", "references", "queries"},
    {"templates", "access", "queries"},
    {"templates", "assets", "adapters"},
    {"templates", "assets", "execution"},
    {"templates", "lifecycle", "projections"},
    {"templates", "lifecycle", "events"},
    {"templates", "lifecycle", "rules"},
    {"templates", "versioning", "adapters"},
    {"templates", "versioning", "execution"},
    {"trash", "references", "commands"},
    {"trash", "references", "records"},
    {"trash", "references", "execution"},
    {"trash", "versioning", "projections"},
    {"versioning", "access", "queries"},
    {"versioning", "assets", "adapters"},
    {"versioning", "assets", "execution"},
    {"versioning", "assets", "queries"},
    {"versioning", "lifecycle", "projections"},
    {"versioning", "lifecycle", "rules"},
    {"versioning", "overview", "queries"},
    {"versioning", "references", "commands"},
    {"versioning", "references", "queries"},
    {"versioning", "references", "rules"},
    {"versioning", "trash", "execution"}
  ])

project_internal_path_denials =
  for source_capability <- project_capabilities,
      target_capability <- project_capabilities -- [source_capability],
      private_role_root <- Map.fetch!(project_private_role_roots, target_capability),
      not MapSet.member?(
        project_private_role_compatibility,
        {source_capability, target_capability, private_role_root}
      ) do
    %{
      source_root: "lib/storyarn/projects/#{source_capability}/",
      target_root: "lib/storyarn/projects/#{target_capability}/#{private_role_root}/",
      kinds: ["runtime", "export", "compile"],
      reason:
        "Project capabilities may consume another capability only through its facade, stable types, or an explicitly retained seam"
    }
  end

# The root facade is declarative. ProjectTrash and SnapshotAccounting remain
# exact public type identities in specs, so their containing role roots are
# protected by the exact dependency test rather than a directory-wide denial.
project_root_private_role_exceptions =
  MapSet.new([{"trash", "execution"}, {"versioning", "queries"}])

project_root_facade_path_denials =
  for capability <- project_capabilities,
      private_role_root <- Map.fetch!(project_private_role_roots, capability),
      not MapSet.member?(project_root_private_role_exceptions, {capability, private_role_root}) do
    %{
      source_root: "lib/storyarn/projects.ex",
      target_root: "lib/storyarn/projects/#{capability}/#{private_role_root}/",
      kinds: ["runtime", "compile"],
      reason:
        "The Storyarn.Projects facade executes through capability facades; stable exported types retain their historical identities"
    }
  end

project_content_root_facade_denial = %{
  source_root: "lib/storyarn/projects.ex",
  target_root: "lib/storyarn/projects/content/",
  kinds: ["runtime", "export", "compile"],
  reason: "Project-owned content models are internal and never part of the root facade contract"
}

# Project lifecycle previously implemented the ordinary source-language writer.
# The local record remains available to the explicitly classified Project
# reconstitution workflows above, but lifecycle must not recreate that writer;
# the Project settings composition point enters Localization through its facade.
project_lifecycle_language_record_denial = %{
  source_root: "lib/storyarn/projects/lifecycle/",
  target_root: "lib/storyarn/projects/content/localization/records/project_language_record.ex",
  kinds: ["runtime", "export", "compile"],
  reason: "Project lifecycle cannot recreate Localization's ordinary project-language writer"
}

# The roles here are directional responsibilities, not a hexagonal purity
# exercise. The matrix protects only directions that are already true; legacy
# snapshot entities and queries keep their observed orchestration until a
# separate behavioral migration can remove it safely.
project_role_scopes =
  ~w(lifecycle access assets overview trash references templates versioning) ++
    ~w(interchange/imports interchange/exports)

# Consumer-local overview schemas use their capability's deterministic naming
# and changeset rules. A few physically stable interchange identities also
# dispatch to format or telemetry adapters. The role ratchet records only these
# established scopes instead of asserting a direction the code does not satisfy.
project_role_compatibility =
  MapSet.new([
    {"interchange/exports", "contracts", "adapters"},
    {"interchange/exports", "rules", "adapters"},
    {"interchange/imports", "rules", "adapters"}
  ])

project_role_dependency_denials =
  for scope <- project_role_scopes,
      {source_role, target_role} <- [
        {"queries", "commands"},
        {"queries", "events"},
        {"queries", "adapters"},
        {"rules", "commands"},
        {"rules", "queries"},
        {"rules", "execution"},
        {"rules", "events"},
        {"rules", "adapters"},
        {"projections", "commands"},
        {"projections", "queries"},
        {"projections", "execution"},
        {"projections", "events"},
        {"projections", "adapters"},
        {"projections", "rules"},
        {"reference_data", "commands"},
        {"reference_data", "queries"},
        {"reference_data", "execution"},
        {"reference_data", "events"},
        {"reference_data", "adapters"},
        {"reference_data", "rules"},
        {"records", "commands"},
        {"records", "queries"},
        {"records", "execution"},
        {"records", "events"},
        {"records", "adapters"},
        {"records", "rules"},
        {"entities", "commands"},
        {"entities", "queries"},
        {"entities", "events"},
        {"contracts", "commands"},
        {"contracts", "queries"},
        {"contracts", "events"},
        {"contracts", "adapters"},
        {"events", "commands"},
        {"events", "queries"},
        {"events", "execution"},
        {"events", "adapters"},
        {"events", "rules"},
        {"adapters", "commands"},
        {"adapters", "queries"},
        {"adapters", "events"}
      ],
      not MapSet.member?(project_role_compatibility, {scope, source_role, target_role}) do
    %{
      source_root: "lib/storyarn/projects/#{scope}/#{source_role}/",
      target_root: "lib/storyarn/projects/#{scope}/#{target_role}/",
      kinds: ["runtime", "export", "compile"],
      reason:
        "Project role folders must preserve the already established read, policy, data, event, and adapter direction"
    }
  end

projects_worker_facade_denial = %{
  source_root: "lib/storyarn/workers/projects/",
  target_root: "lib/storyarn/projects/",
  kinds: ["runtime", "export", "compile"],
  reason: "Project workers must orchestrate through the Storyarn.Projects facade"
}

# Localization is one bounded context split into cohesive internal capabilities.
# A capability may consume another capability's facade or a deliberately stable
# entity/contract identity, but its data projections and operational roles stay
# private to the capability that owns them.
localization_capabilities =
  ~w(project_access languages texts providers glossary translation exchange reporting)

localization_private_roles =
  ~w(adapters commands queries rules projections reference_data execution)

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
        {"projections", "commands"},
        {"projections", "queries"},
        {"projections", "execution"},
        {"projections", "adapters"},
        {"projections", "rules"},
        {"reference_data", "commands"},
        {"reference_data", "queries"},
        {"reference_data", "execution"},
        {"reference_data", "adapters"},
        {"reference_data", "rules"},
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

# Sheets is one bounded context split by business capability. Stable Sheet
# entities and value contracts may cross capability lines; operational roles
# and consumer-owned SQL projections and records remain private to their owner.
sheet_capabilities = ~w(access ai assets editor health localization expressions references versioning)
sheet_private_roles = ~w(adapters commands queries rules projections records compatibility execution events)

sheet_internal_path_denials =
  for source_capability <- sheet_capabilities,
      target_capability <- sheet_capabilities -- [source_capability],
      private_role <- sheet_private_roles do
    %{
      source_root: "lib/storyarn/sheets/#{source_capability}/",
      target_root: "lib/storyarn/sheets/#{target_capability}/#{private_role}/",
      kinds: ["runtime", "export", "compile"],
      reason: "Sheet capabilities may consume another capability only through its facade or stable entities and contracts"
    }
  end

sheet_root_facade_path_denials =
  for capability <- sheet_capabilities,
      private_role <- sheet_private_roles do
    %{
      source_root: "lib/storyarn/sheets.ex",
      target_root: "lib/storyarn/sheets/#{capability}/#{private_role}/",
      kinds: ["runtime", "export", "compile"],
      reason:
        "The Storyarn.Sheets facade composes capability facades, stable entities, and contracts rather than private implementation roles"
    }
  end

# Folder roles express useful dependency direction without imposing a port for
# every function. Commands may coordinate local queries and adapters, while
# passive models and reads cannot become hidden effectful orchestrators.
sheet_role_dependency_denials =
  for capability <- sheet_capabilities,
      {source_role, target_role} <- [
        {"queries", "commands"},
        {"queries", "execution"},
        {"queries", "events"},
        {"queries", "adapters"},
        {"rules", "commands"},
        {"rules", "queries"},
        {"rules", "execution"},
        {"rules", "events"},
        {"rules", "adapters"},
        {"projections", "commands"},
        {"projections", "queries"},
        {"projections", "execution"},
        {"projections", "events"},
        {"projections", "adapters"},
        {"projections", "rules"},
        {"records", "commands"},
        {"records", "queries"},
        {"records", "execution"},
        {"records", "events"},
        {"records", "adapters"},
        {"records", "rules"},
        {"entities", "commands"},
        {"entities", "queries"},
        {"entities", "execution"},
        {"entities", "events"},
        {"entities", "adapters"},
        {"contracts", "commands"},
        {"contracts", "queries"},
        {"contracts", "execution"},
        {"contracts", "events"},
        {"contracts", "adapters"},
        {"events", "commands"},
        {"events", "queries"},
        {"events", "execution"},
        {"events", "adapters"},
        {"events", "rules"},
        {"adapters", "commands"},
        {"adapters", "queries"},
        {"adapters", "execution"},
        {"adapters", "events"},
        {"adapters", "rules"}
      ] do
    %{
      source_root: "lib/storyarn/sheets/#{capability}/#{source_role}/",
      target_root: "lib/storyarn/sheets/#{capability}/#{target_role}/",
      kinds: ["runtime", "export", "compile"],
      reason: "Sheet role folders must preserve read, policy, data, event, execution, and adapter direction"
    }
  end

# Scenes is one bounded context split by business capability. Stable Scene
# entities and value contracts may cross capability lines; operational roles
# and consumer-owned SQL projections and records remain private to their owner.
scene_capabilities = ~w(access assets editor exploration health expressions references versioning)
scene_private_roles = ~w(adapters commands queries rules projections records compatibility execution events)

scene_internal_path_denials =
  for source_capability <- scene_capabilities,
      target_capability <- scene_capabilities -- [source_capability],
      private_role <- scene_private_roles do
    %{
      source_root: "lib/storyarn/scenes/#{source_capability}/",
      target_root: "lib/storyarn/scenes/#{target_capability}/#{private_role}/",
      kinds: ["runtime", "export", "compile"],
      reason: "Scene capabilities may consume another capability only through its facade or stable entities and contracts"
    }
  end

scene_root_facade_path_denials =
  for capability <- scene_capabilities,
      private_role <- scene_private_roles do
    %{
      source_root: "lib/storyarn/scenes.ex",
      target_root: "lib/storyarn/scenes/#{capability}/#{private_role}/",
      kinds: ["runtime", "export", "compile"],
      reason:
        "The Storyarn.Scenes facade composes capability facades, stable entities, and contracts rather than private implementation roles"
    }
  end

# Folder roles express useful dependency direction without imposing a port for
# every function. Commands may coordinate local queries and adapters, while
# passive models and reads cannot become hidden effectful orchestrators.
scene_role_dependency_denials =
  for capability <- scene_capabilities,
      {source_role, target_role} <- [
        {"queries", "commands"},
        {"queries", "execution"},
        {"queries", "events"},
        {"queries", "adapters"},
        {"rules", "commands"},
        {"rules", "queries"},
        {"rules", "execution"},
        {"rules", "events"},
        {"rules", "adapters"},
        {"projections", "commands"},
        {"projections", "queries"},
        {"projections", "execution"},
        {"projections", "events"},
        {"projections", "adapters"},
        {"projections", "rules"},
        {"records", "commands"},
        {"records", "queries"},
        {"records", "execution"},
        {"records", "events"},
        {"records", "adapters"},
        {"records", "rules"},
        {"entities", "commands"},
        {"entities", "queries"},
        {"entities", "execution"},
        {"entities", "events"},
        {"entities", "adapters"},
        {"contracts", "commands"},
        {"contracts", "queries"},
        {"contracts", "execution"},
        {"contracts", "events"},
        {"contracts", "adapters"},
        {"events", "commands"},
        {"events", "queries"},
        {"events", "execution"},
        {"events", "adapters"},
        {"events", "rules"},
        {"adapters", "commands"},
        {"adapters", "queries"},
        {"adapters", "execution"},
        {"adapters", "events"},
        {"adapters", "rules"}
      ] do
    %{
      source_root: "lib/storyarn/scenes/#{capability}/#{source_role}/",
      target_root: "lib/storyarn/scenes/#{capability}/#{target_role}/",
      kinds: ["runtime", "export", "compile"],
      reason: "Scene role folders must preserve read, policy, data, event, execution, and adapter direction"
    }
  end

# Flows is one bounded context split by business capability. Flow, node,
# connection, and sequence authoring remains one Editor aggregate; the other
# capabilities own their consumer-specific runtime, projections, records, and policies.
flow_capabilities = ~w(ai editor health localization expressions references runtime versioning)
flow_private_roles = ~w(adapters commands queries rules projections records compatibility execution events)

flow_internal_path_denials =
  for source_capability <- flow_capabilities,
      target_capability <- flow_capabilities -- [source_capability],
      private_role <- flow_private_roles do
    %{
      source_root: "lib/storyarn/flows/#{source_capability}/",
      target_root: "lib/storyarn/flows/#{target_capability}/#{private_role}/",
      kinds: ["runtime", "export", "compile"],
      reason: "Flow capabilities may consume another capability only through its facade or stable entities and contracts"
    }
  end

flow_root_facade_path_denials =
  for capability <- flow_capabilities,
      private_role <- flow_private_roles do
    %{
      source_root: "lib/storyarn/flows.ex",
      target_root: "lib/storyarn/flows/#{capability}/#{private_role}/",
      kinds: ["runtime", "compile"],
      reason:
        "The Storyarn.Flows facade executes only through capability facades; established public types may still name stable value shapes"
    }
  end

# Reads remain read-only, while passive models and pure rules cannot become
# hidden effectful orchestrators. Commands and execution workflows may keep an
# indivisible transaction together when a graph or restore invariant requires it.
flow_role_dependency_denials =
  for capability <- flow_capabilities,
      {source_role, target_role} <- [
        {"queries", "commands"},
        {"queries", "execution"},
        {"queries", "events"},
        {"queries", "adapters"},
        {"rules", "commands"},
        {"rules", "queries"},
        {"rules", "execution"},
        {"rules", "events"},
        {"rules", "adapters"},
        {"projections", "commands"},
        {"projections", "queries"},
        {"projections", "execution"},
        {"projections", "events"},
        {"projections", "adapters"},
        {"projections", "rules"},
        {"records", "commands"},
        {"records", "queries"},
        {"records", "execution"},
        {"records", "events"},
        {"records", "adapters"},
        {"records", "rules"},
        {"entities", "commands"},
        {"entities", "queries"},
        {"entities", "execution"},
        {"entities", "events"},
        {"entities", "adapters"},
        {"contracts", "commands"},
        {"contracts", "queries"},
        {"contracts", "execution"},
        {"contracts", "events"},
        {"contracts", "adapters"},
        {"events", "commands"},
        {"events", "queries"},
        {"events", "execution"},
        {"events", "adapters"},
        {"events", "rules"},
        {"adapters", "commands"},
        {"adapters", "queries"},
        {"adapters", "execution"},
        {"adapters", "events"},
        {"adapters", "rules"}
      ] do
    %{
      source_root: "lib/storyarn/flows/#{capability}/#{source_role}/",
      target_root: "lib/storyarn/flows/#{capability}/#{target_role}/",
      kinds: ["runtime", "export", "compile"],
      reason: "Flow role folders must preserve read, policy, data, event, execution, and adapter direction"
    }
  end

# AI is one bounded context split into product capabilities, not six smaller
# contexts. Capability facades and stable entities/contracts may be shared
# internally; operational roles and consumer-owned projections stay private.
ai_capabilities =
  ~w(context_building governance integrations managed_spend operations routing)

ai_private_roles =
  ~w(adapters commands queries rules projections reference_data compatibility tasks execution events)

ai_internal_path_denials =
  for source_capability <- ai_capabilities,
      target_capability <- ai_capabilities -- [source_capability],
      private_role <- ai_private_roles do
    %{
      source_root: "lib/storyarn/ai/#{source_capability}/",
      target_root: "lib/storyarn/ai/#{target_capability}/#{private_role}/",
      kinds: ["runtime", "export", "compile"],
      reason: "AI capabilities may consume another capability only through its facade or stable entities and contracts"
    }
  end

ai_root_facade_path_denials =
  for capability <- ai_capabilities,
      private_role <- ai_private_roles do
    %{
      source_root: "lib/storyarn/ai.ex",
      target_root: "lib/storyarn/ai/#{capability}/#{private_role}/",
      kinds: ["runtime", "export", "compile"],
      reason:
        "The Storyarn.AI facade composes capability facades, stable entities, and contracts rather than private implementation roles"
    }
  end

# These directions capture meaningful responsibilities without requiring ports
# for every pure function. Reads remain read-only; rules, data, and entities
# cannot become hidden effectful orchestrators. Event modules may persist their
# owned facts, and adapters may execute commands only as configured contract
# implementations.
ai_forbidden_role_edges = [
  {"queries", "commands"},
  {"queries", "execution"},
  {"queries", "events"},
  {"queries", "adapters"},
  {"rules", "commands"},
  {"rules", "queries"},
  {"rules", "execution"},
  {"rules", "events"},
  {"rules", "adapters"},
  {"projections", "commands"},
  {"projections", "queries"},
  {"projections", "execution"},
  {"projections", "events"},
  {"projections", "adapters"},
  {"projections", "rules"},
  {"reference_data", "commands"},
  {"reference_data", "queries"},
  {"reference_data", "execution"},
  {"reference_data", "events"},
  {"reference_data", "adapters"},
  {"reference_data", "rules"},
  {"entities", "commands"},
  {"entities", "queries"},
  {"entities", "execution"},
  {"entities", "events"},
  {"entities", "adapters"},
  {"contracts", "commands"},
  {"contracts", "queries"},
  {"contracts", "execution"},
  {"contracts", "events"},
  {"contracts", "projections"},
  {"contracts", "reference_data"},
  {"events", "commands"},
  {"events", "queries"},
  {"events", "execution"},
  {"events", "adapters"},
  {"events", "rules"},
  {"adapters", "queries"},
  {"adapters", "execution"},
  {"adapters", "events"}
]

ai_role_dependency_denials =
  for capability <- ai_capabilities,
      {source_role, target_role} <- ai_forbidden_role_edges do
    %{
      source_root: "lib/storyarn/ai/#{capability}/#{source_role}/",
      target_root: "lib/storyarn/ai/#{capability}/#{target_role}/",
      kinds: ["runtime", "export", "compile"],
      reason: "AI role folders must preserve read, policy, data, event, execution, and adapter direction"
    }
  end

ai_worker_facade_denial = %{
  source_root: "lib/storyarn/workers/ai/",
  target_root: "lib/storyarn/ai/",
  kinds: ["runtime", "export", "compile"],
  reason: "AI workers must orchestrate through the Storyarn.AI facade"
}

# Platform is one control-plane context split into cohesive capabilities. A
# capability may consume another capability's facade, but its operational code,
# data projections, entities, and rules remain private to their owner.
# Reaction contracts and analytics adapters stay outside this private set: the
# former are stable event contracts and the latter are technical infrastructure.
platform_capability_private_targets = %{
  "commercial" => [
    "billing.ex",
    "project_storage_reservations.ex",
    "subscription_crud.ex",
    "commands/",
    "entities/",
    "execution/",
    "projections/",
    "queries/",
    "reference_data/",
    "rules/"
  ],
  "notifications" => ["adapters/", "entities/", "execution/", "projections/", "queries/"],
  "object_storage" => ["adapters/", "hashing.ex", "key_lock.ex"],
  "onboarding" => ["commands/", "entities/", "projections/", "queries/"],
  "reactions" => ["events/", "execution/", "reference_data/"]
}

platform_query_role_denials =
  for capability <- Map.keys(platform_capability_private_targets),
      target_role <- ["adapters", "commands", "events", "execution"] do
    %{
      source_root: "lib/storyarn/platform/#{capability}/queries/",
      target_root: "lib/storyarn/platform/#{capability}/#{target_role}/",
      kinds: ["runtime", "export", "compile"],
      reason: "Platform queries may read data and rules but cannot invoke effectful capability roles"
    }
  end

platform_internal_path_denials =
  for {source_capability, _private_targets} <- platform_capability_private_targets,
      {target_capability, private_targets} <- platform_capability_private_targets,
      source_capability != target_capability,
      private_target <- private_targets do
    %{
      source_root: "lib/storyarn/platform/#{source_capability}/",
      target_root: "lib/storyarn/platform/#{target_capability}/#{private_target}",
      kinds: ["runtime", "export", "compile"],
      reason: "Platform capabilities may consume another capability only through its facade or stable contracts"
    }
  end

# ObjectStorage has a standalone technical facade rather than entering through
# Storyarn.Platform. Keep that exact facade isolated from the private roles of
# every other Platform capability just as capability directories are. Its own
# provider, hashing and lock modules are its implementation and remain allowed.
object_storage_public_facades = [
  "lib/storyarn/platform/object_storage.ex"
]

object_storage_facade_path_denials =
  for source_root <- object_storage_public_facades,
      {target_capability, private_targets} <- platform_capability_private_targets,
      target_capability != "object_storage",
      private_target <- private_targets do
    %{
      source_root: source_root,
      target_root: "lib/storyarn/platform/#{target_capability}/#{private_target}",
      kinds: ["runtime", "export", "compile"],
      reason: "ObjectStorage is an isolated technical capability and cannot enter another Platform capability's internals"
    }
  end

# The root facade composes capability facades. Its sole private-facet
# dependency is the exported receipt/error type contract still owned by the
# stable ProjectStorageReservations compatibility facet; runtime and
# compile-time use remain forbidden, as does every kind of dependency on other
# private capability targets.
platform_root_facade_path_denials =
  for {capability, private_targets} <- platform_capability_private_targets,
      private_target <- private_targets do
    kinds =
      if capability == "commercial" and
           private_target == "project_storage_reservations.ex" do
        ["runtime", "compile"]
      else
        ["runtime", "export", "compile"]
      end

    %{
      source_root: "lib/storyarn/platform.ex",
      target_root: "lib/storyarn/platform/#{capability}/#{private_target}",
      kinds: kinds,
      reason: "The Storyarn.Platform facade composes capability facades rather than private implementation roles"
    }
  end

# Collaboration and Discovery are application/technical areas rather than
# independent bounded contexts. Web may use their stable public facets, but it
# must not learn their adapters, commands, projections, entities, or queries.
platform_web_application_private_targets = %{
  "collaboration" => ["adapters/", "rules/"],
  "discovery" => ["adapters/", "commands/", "entities/", "projections/", "queries/", "reference_data/"]
}

platform_web_application_private_denials =
  for {area, private_targets} <- platform_web_application_private_targets,
      private_target <- private_targets do
    %{
      source_root: "lib/storyarn_web/",
      target_root: "lib/storyarn/platform/#{area}/#{private_target}",
      kinds: ["runtime", "export", "compile"],
      reason: "Web adapters must enter Platform application areas through their stable public facets"
    }
  end

analytics_transport_target = "lib/storyarn/platform/reactions/adapters/analytics.ex"

analytics_transport_allowed_source_roots =
  MapSet.new([
    "lib/storyarn/platform/reactions/reactions.ex",
    "lib/storyarn/platform/reactions/events/"
  ])

# Analytics keeps its stable technical module identity, but it is not a general
# infrastructure entry point. Every classified source root is denied explicitly
# except the Reactions facade and Platform-owned reaction event handlers.
analytics_transport_caller_denials =
  boundaries
  |> Map.values()
  |> List.flatten()
  |> Enum.reject(&MapSet.member?(analytics_transport_allowed_source_roots, &1))
  |> Enum.map(fn source_root ->
    %{
      source_root: source_root,
      target_root: analytics_transport_target,
      kinds: ["runtime", "export", "compile"],
      reason: "Only Platform Reactions may enter the exact analytics transport facade"
    }
  end)

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
    "lib/mix/tasks/",
    "lib/storyarn.ex",
    "lib/storyarn/",
    "lib/storyarn_web.ex",
    "lib/storyarn_web/"
  ],
  boundaries: boundaries,
  forbidden_dependencies: forbidden_dependencies,

  # Unlike xref import edges, persistence authority is semantic. Architecture
  # tests consume this exact allowlist and reject new Project record consumers
  # or writers until their ownership is reviewed deliberately.
  persistence_ownership: %{
    project_languages: project_language_persistence_ownership
  },

  # Code below `Storyarn` is the domain/application side of the system. Even
  # when a StoryarnWeb adapter is classified with the same owning context, the
  # dependency direction must stay domain -> application boundary <- Web.
  path_denials:
    [
      %{
        source_root: "lib/storyarn.ex",
        target_root: "lib/storyarn_web.ex",
        kinds: ["runtime", "export", "compile"],
        reason: "the Storyarn entry point cannot depend on the Web entry point"
      },
      %{
        source_root: "lib/storyarn.ex",
        target_root: "lib/storyarn_web/",
        kinds: ["runtime", "export", "compile"],
        reason: "the Storyarn entry point cannot depend on Phoenix or LiveVue adapters"
      },
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
      project_internal_path_denials ++
      project_root_facade_path_denials ++
      [project_content_root_facade_denial, project_lifecycle_language_record_denial] ++
      project_role_dependency_denials ++
      [projects_worker_facade_denial] ++
      localization_internal_path_denials ++
      localization_role_dependency_denials ++
      [localization_worker_facade_denial] ++
      sheet_internal_path_denials ++
      sheet_root_facade_path_denials ++
      sheet_role_dependency_denials ++
      scene_internal_path_denials ++
      scene_root_facade_path_denials ++
      scene_role_dependency_denials ++
      flow_internal_path_denials ++
      flow_root_facade_path_denials ++
      flow_role_dependency_denials ++
      ai_internal_path_denials ++
      ai_root_facade_path_denials ++
      ai_role_dependency_denials ++
      [ai_worker_facade_denial] ++
      platform_internal_path_denials ++
      object_storage_facade_path_denials ++
      platform_query_role_denials ++
      platform_root_facade_path_denials ++
      platform_web_application_private_denials ++
      analytics_transport_caller_denials,

  # Once a consumer reaches zero forbidden dependencies, its baseline is
  # sealed permanently. The checker rejects any edge in that partition even
  # when the current xref graph contains the exact same edge. Every partition
  # is sealed: the ENG-92 debt baseline is empty and can only stay empty.
  zero_debt_consumers: [
    :accounts,
    :ai,
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
  isolated_contexts: [:accounts, :ai, :flows, :localization, :platform, :projects, :scenes, :sheets, :workspaces],

  # These exact leaves are globally consumable technical infrastructure, not
  # bounded-context APIs. They deliberately cover no directory: Repo remains
  # shared during ENG-92; the other entries are stable primitives, adapters or
  # execution plumbing with no consumer-specific business policy. Adding a
  # target here is an architecture decision because it grants every boundary
  # access without registering each source edge, unless an explicit path-denial
  # matrix narrows that access as it does for the Analytics transport facade.
  globally_allowed_technical_targets: [
    "lib/storyarn/repo.ex",
    "lib/storyarn/gettext.ex",
    "lib/storyarn/platform/discovery/dashboard_cache.ex",
    "lib/storyarn/platform/collaboration/collaboration.ex",
    "lib/storyarn/platform/adapters/email/layout.ex",
    "lib/storyarn/platform/adapters/configuration/feature_flags.ex",
    "lib/storyarn/platform/adapters/email/mailer.ex",
    "lib/storyarn/platform/adapters/rate_limiter.ex",
    "lib/storyarn/platform/adapters/configuration/urls.ex",
    "lib/storyarn/platform/adapters/security/encrypted_binary.ex",
    "lib/storyarn/platform/adapters/security/html_sanitizer.ex",
    analytics_transport_target,
    "lib/storyarn/platform/kernel/html_utils.ex",
    "lib/storyarn/platform/kernel/integer_parser.ex",
    "lib/storyarn/platform/kernel/map_access.ex",
    "lib/storyarn/platform/kernel/search_helpers.ex",
    "lib/storyarn/platform/kernel/string_utils.ex",
    "lib/storyarn/platform/adapters/clock.ex",
    "lib/storyarn/platform/adapters/security/token_generator.ex"
  ],

  # Durable cross-boundary contracts normally terminate at bounded-context root
  # facades. These are the only additional exact targets
  # that may terminate a reviewed durable edge. Unlike the global technical
  # leaves above, listing a target here grants no access by itself. AI's Context
  # SPI is deliberately public because consumer contexts own their builders.
  additional_durable_contract_targets: [
    %{
      target: "lib/storyarn/platform/object_storage.ex",
      reason: "bounded contexts consume the exact public Platform object-storage contract"
    },
    %{
      target: "lib/storyarn/ai/context_building/contracts/contract.ex",
      reason: "consumer-owned AI context builders implement the shared AI context contract"
    },
    %{
      target: "lib/storyarn/ai/context_building/contracts/policy.ex",
      reason: "consumer-owned AI context builders export the AI policy value"
    },
    %{
      target: "lib/storyarn/ai/context_building/contracts/subject_ref.ex",
      reason: "consumer-owned AI context builders export AI subject references"
    },
    %{
      target: "lib/storyarn/platform/adapters/security/vault.ex",
      reason: "Encrypted import payloads use the application-owned cryptographic adapter"
    },
    %{
      target: "lib/storyarn/platform/reactions/contracts/analytics_event_contract.ex",
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
      source: "lib/storyarn/application.ex",
      target: "lib/storyarn/platform/object_storage.ex",
      kinds: ["runtime"],
      reason: "The OTP composition root starts ObjectStorage's technical child specifications through its public facade"
    },
    %{
      source: "lib/storyarn/flows/versioning/adapters/storage/hashing.ex",
      target: "lib/storyarn/platform/object_storage.ex",
      kinds: ["runtime"],
      reason: "Flows implements its storage hashing port through the public Platform ObjectStorage facade"
    },
    %{
      source: "lib/storyarn/flows/versioning/adapters/storage/locks.ex",
      target: "lib/storyarn/platform/object_storage.ex",
      kinds: ["runtime"],
      reason: "Flows implements its storage lock port through the public Platform ObjectStorage facade"
    },
    %{
      source: "lib/storyarn/flows/versioning/adapters/storage/objects.ex",
      target: "lib/storyarn/platform/object_storage.ex",
      kinds: ["runtime"],
      reason: "Flows implements its object operations port through the public Platform ObjectStorage facade"
    },
    %{
      source: "lib/storyarn/projects/assets/adapters/storage/hash.ex",
      target: "lib/storyarn/platform/object_storage.ex",
      kinds: ["runtime"],
      reason: "Projects implements its asset hashing adapter through the public Platform ObjectStorage facade"
    },
    %{
      source: "lib/storyarn/projects/assets/adapters/storage/key_lock.ex",
      target: "lib/storyarn/platform/object_storage.ex",
      kinds: ["runtime"],
      reason: "Projects keeps Project blob identity policy while delegating generic locks through Platform ObjectStorage"
    },
    %{
      source: "lib/storyarn/projects/assets/adapters/storage/storage.ex",
      target: "lib/storyarn/platform/object_storage.ex",
      kinds: ["runtime"],
      reason: "Projects keeps deletion and multipart policy while delegating provider I/O through Platform ObjectStorage"
    },
    %{
      source: "lib/storyarn/scenes/assets/adapters/storage/hashing.ex",
      target: "lib/storyarn/platform/object_storage.ex",
      kinds: ["runtime"],
      reason: "Scenes implements its asset hashing port through the public Platform ObjectStorage facade"
    },
    %{
      source: "lib/storyarn/scenes/assets/adapters/storage/locks.ex",
      target: "lib/storyarn/platform/object_storage.ex",
      kinds: ["runtime"],
      reason: "Scenes implements its asset lock port through the public Platform ObjectStorage facade"
    },
    %{
      source: "lib/storyarn/scenes/assets/adapters/storage/objects.ex",
      target: "lib/storyarn/platform/object_storage.ex",
      kinds: ["runtime"],
      reason: "Scenes implements its asset object port through the public Platform ObjectStorage facade"
    },
    %{
      source: "lib/storyarn/scenes/versioning/adapters/storage/objects.ex",
      target: "lib/storyarn/platform/object_storage.ex",
      kinds: ["runtime"],
      reason: "Scenes implements its versioning object port through the public Platform ObjectStorage facade"
    },
    %{
      source: "lib/storyarn/sheets/assets/adapters/storage/hashing.ex",
      target: "lib/storyarn/platform/object_storage.ex",
      kinds: ["runtime"],
      reason: "Sheets implements its asset hashing port through the public Platform ObjectStorage facade"
    },
    %{
      source: "lib/storyarn/sheets/assets/adapters/storage/locks.ex",
      target: "lib/storyarn/platform/object_storage.ex",
      kinds: ["runtime"],
      reason: "Sheets implements its asset lock port through the public Platform ObjectStorage facade"
    },
    %{
      source: "lib/storyarn/sheets/assets/adapters/storage/objects.ex",
      target: "lib/storyarn/platform/object_storage.ex",
      kinds: ["runtime"],
      reason: "Sheets implements its asset object port through the public Platform ObjectStorage facade"
    },
    %{
      source: "lib/storyarn/sheets/versioning/adapters/storage/objects.ex",
      target: "lib/storyarn/platform/object_storage.ex",
      kinds: ["runtime"],
      reason: "Sheets implements its versioning object port through the public Platform ObjectStorage facade"
    },
    %{
      source: "lib/storyarn_web/private_download.ex",
      target: "lib/storyarn/platform/object_storage.ex",
      kinds: ["runtime"],
      reason: "The authenticated download adapter streams already-authorized objects through Platform ObjectStorage"
    },
    %{
      source: "lib/storyarn_web/private_media.ex",
      target: "lib/storyarn/platform/object_storage.ex",
      kinds: ["runtime"],
      reason: "The authenticated media adapter resolves already-authorized objects through Platform ObjectStorage"
    },
    %{
      source: "lib/storyarn_web/private_media.ex",
      target: "lib/storyarn/projects.ex",
      kinds: ["runtime"],
      reason: "Private media asks the public Projects facade to classify Project-owned media keys"
    },
    %{
      source: "lib/mix/tasks/storyarn.ai.diagnose.ex",
      target: "lib/storyarn/accounts.ex",
      kinds: ["runtime"],
      reason: "The operator AI diagnostic resolves its actor through the public Accounts facade"
    },
    %{
      source: "lib/mix/tasks/storyarn.ai.diagnose.ex",
      target: "lib/storyarn/ai.ex",
      kinds: ["runtime"],
      reason: "The operator AI diagnostic exercises the public AI facade"
    },
    %{
      source: "lib/mix/tasks/storyarn.ai.grant.ex",
      target: "lib/storyarn/ai.ex",
      kinds: ["runtime"],
      reason: "The operator allowance task enters AI through its public facade"
    },
    %{
      source: "lib/mix/tasks/storyarn.snapshot_archive_smoke.ex",
      target: "lib/storyarn/projects.ex",
      kinds: ["runtime"],
      reason: "The operator snapshot smoke enters Projects through its public facade"
    },
    %{
      source: "lib/mix/tasks/storyarn.templates.export.ex",
      target: "lib/storyarn/projects.ex",
      kinds: ["runtime"],
      reason: "The operator template export enters Projects through its public facade"
    },
    %{
      source: "lib/mix/tasks/storyarn.templates.import.ex",
      target: "lib/storyarn/projects.ex",
      kinds: ["runtime"],
      reason: "The operator template import enters Projects through its public facade"
    },
    %{
      source: "lib/storyarn/flows/ai/contracts/context_contract.ex",
      target: "lib/storyarn/ai/context_building/contracts/contract.ex",
      kinds: ["runtime"],
      reason: "Flows implements the exact public AI context-builder contract"
    },
    %{
      source: "lib/storyarn/flows/ai/contracts/context_contract.ex",
      target: "lib/storyarn/ai/context_building/contracts/policy.ex",
      kinds: ["export"],
      reason: "Flows exports the public AI context policy value in its implementation"
    },
    %{
      source: "lib/storyarn/flows/ai/contracts/context_contract.ex",
      target: "lib/storyarn/ai/context_building/contracts/subject_ref.ex",
      kinds: ["export"],
      reason: "Flows exports the public AI subject reference in its implementation"
    },
    %{
      source: "lib/storyarn/sheets/ai/contracts/context_contract.ex",
      target: "lib/storyarn/ai/context_building/contracts/contract.ex",
      kinds: ["runtime"],
      reason: "Sheets implements the exact public AI context-builder contract"
    },
    %{
      source: "lib/storyarn/sheets/ai/contracts/context_contract.ex",
      target: "lib/storyarn/ai/context_building/contracts/policy.ex",
      kinds: ["export"],
      reason: "Sheets exports the public AI context policy value in its implementation"
    },
    %{
      source: "lib/storyarn/sheets/ai/contracts/context_contract.ex",
      target: "lib/storyarn/ai/context_building/contracts/subject_ref.ex",
      kinds: ["export"],
      reason: "Sheets exports the public AI subject reference in its implementation"
    },
    %{
      source: "lib/storyarn_web/live/hooks/palette.ex",
      target: "lib/storyarn/ai.ex",
      kinds: ["runtime"],
      reason: "The shared command palette recognizes AI-owned commands through the public AI facade"
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
      reason:
        "Palette operations publish committed notification outcomes and privacy-safe analytics through the public Platform facade"
    },
    %{
      source: "lib/storyarn_web/components/layouts.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "The root presentation layout obtains frontend-safe analytics configuration through Platform"
    },
    %{
      source: "lib/storyarn_web/live/hooks/onboarding.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "The authenticated hook reads and mutates Platform-owned onboarding through its root facade"
    },
    %{
      source: "lib/storyarn_web/live/shared/onboarding_helpers.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Presentation serialization consumes only Platform's onboarding summary contract"
    },
    %{
      source: "lib/storyarn_web/live/settings_live/tutorials.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Tutorial settings restart Platform-owned onboarding through the public facade"
    },
    %{
      source: "lib/storyarn_web/live/shared/notification_helpers.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "The shared notification helpers list and count through the public Platform facade"
    },
    %{
      source: "lib/storyarn/application.ex",
      target: "lib/storyarn/projects.ex",
      kinds: ["runtime"],
      reason: "OTP composition root obtains the import error deduplicator child spec through the public Projects facade"
    },
    %{
      source: "lib/storyarn/platform/discovery/queries/global_search/destinations.ex",
      target: "lib/storyarn/projects.ex",
      kinds: ["runtime"],
      reason: "Global search resolves reachable projects through the public Projects access reads"
    },
    %{
      source: "lib/storyarn/platform/discovery/queries/global_search/variable_search.ex",
      target: "lib/storyarn/projects.ex",
      kinds: ["runtime"],
      reason: "Global variable search reads Project-owned occurrences through the public Projects facade"
    },
    %{
      source: "lib/storyarn/release.ex",
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
      source: "lib/storyarn/projects/assets/execution/asset_operations.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Asset lifecycle accounts storage usage through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/assets/execution/asset_trash.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Asset lifecycle accounts storage usage through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/assets/execution/blob_store.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Asset lifecycle accounts storage usage through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/interchange/imports/execution/execution.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason:
        "Project imports enforce storage policy and publish committed notifications through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/interchange/imports/commands/expiration.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Project imports publish committed notification outcomes through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/interchange/imports/execution/materializer.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Project imports enforce storage policy through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/interchange/imports/adapters/notifications/notification_delivery.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Project imports prepare durable notification delivery through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/interchange/imports/adapters/storage/plan_storage.ex",
      target: "lib/storyarn/platform/adapters/security/vault.ex",
      kinds: ["runtime"],
      reason: "Import plan storage encrypts payloads with the application vault"
    },
    %{
      source: "lib/storyarn/projects/interchange/imports/commands/replacement.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Project replacement imports coordinate storage locks through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/interchange/imports/commands/resume.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Project imports publish committed notification outcomes through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/templates/execution/installation.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason:
        "Template installation enforces commercial policy and publishes notification outcomes through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/templates/execution/publication_runner.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Template publication enforces commercial policy through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/lifecycle/commands/project_commands.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Project lifecycle enforces commercial policy through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/versioning/adapters/platform/storage_reservations.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason:
        "The Projects anti-corruption layer exchanges transport-neutral storage receipts through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/trash/execution/project_trash.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Project lifecycle enforces commercial policy through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/access/delivery/invitation_email.ex",
      target: "lib/storyarn/platform/adapters/email/layout.ex",
      kinds: ["runtime"],
      reason: "Project-owned invitation content uses the shared technical email layout"
    },
    %{
      source: "lib/storyarn/projects/access/delivery/invitation_notifier.ex",
      target: "lib/storyarn/platform/adapters/email/mailer.ex",
      kinds: ["runtime"],
      reason: "Project invitation delivery goes through the application mailer"
    },
    %{
      source: "lib/storyarn/projects/access/commands/invitation_operations.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Project invitations enforce Platform-owned member seat policy"
    },
    %{
      source: "lib/storyarn/projects/versioning/versioning.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Snapshot storage lifecycle accounts usage and locks through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/versioning/execution/materialization_helpers.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Snapshot materialization accounts storage through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/versioning/execution/project_recovery.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Project recovery coordinates storage locks through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/versioning/rules/project_snapshot_lease_policy.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Project snapshot grants consume the lease policy through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/versioning/execution/project_snapshot_asset_materializer.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Snapshot asset materialization accounts storage through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/versioning/execution/project_snapshot_build.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Snapshot builds coordinate storage and publish notification outcomes through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/versioning/commands/project_snapshot_crud.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Snapshot lifecycle accounts storage and locks through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/versioning/execution/project_snapshot_download.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Snapshot downloads acquire storage leases through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/versioning/commands/project_snapshot_lifecycle.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Snapshot lifecycle accounts storage and locks through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/versioning/execution/project_snapshot_reconciliation_repair.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Snapshot reconciliation repairs storage accounting through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/versioning/commands/project_snapshot_restore_lifecycle.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Snapshot restore lifecycle accounts storage and locks through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/versioning/commands/workspace_snapshot_imports.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason:
        "Workspace snapshot imports coordinate storage and publish notification outcomes through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/versioning/queries/snapshot_accounting.ex",
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
      source: "lib/storyarn/projects/lifecycle/events/project_events.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "The Project boundary publishes owned business facts through the public Platform reaction contract"
    },
    %{
      source: "lib/storyarn/flows/editor/events/editor_events.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Flow editor operations publish their owned facts through the public Platform reaction contract"
    },
    %{
      source: "lib/storyarn/flows/runtime/events/runtime_events.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Flow runtime operations publish their owned facts through the public Platform reaction contract"
    },
    %{
      source: "lib/storyarn/flows/versioning/events/version_events.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Flow versioning operations publish their owned facts through the public Platform reaction contract"
    },
    %{
      source: "lib/storyarn/flows/editor/commands/flow_crud.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Flow mutations request durable notification delivery through the public Platform contract"
    },
    %{
      source: "lib/storyarn/flows/editor/commands/item_capacity.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Flow authoring applies Platform-owned item entitlements"
    },
    %{
      source: "lib/storyarn/flows/versioning/commands/named_version_capacity.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Flow versioning applies Platform-owned named-version entitlements"
    },
    %{
      source: "lib/storyarn/flows/versioning/execution/asset_catalog.ex",
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
      source: "lib/storyarn/scenes/assets/commands/assets.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Scene asset writes apply the Platform-owned storage entitlement"
    },
    %{
      source: "lib/storyarn/scenes/assets/events/assets.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Scene Assets publishes its owned business facts through the Platform reaction contract"
    },
    %{
      source: "lib/storyarn/scenes/editor/commands/item_capacity.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "The Scene editor applies the Platform-owned project item entitlement"
    },
    %{
      source: "lib/storyarn/scenes/exploration/events/exploration_events.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Scene Exploration publishes its owned business facts through the Platform reaction contract"
    },
    %{
      source: "lib/storyarn/scenes/versioning/commands/named_version_capacity.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Scene Versioning applies the Platform-owned named-version entitlement"
    },
    %{
      source: "lib/storyarn/scenes/versioning/events/versions.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Scene Versioning publishes its owned business facts through the Platform reaction contract"
    },
    %{
      source: "lib/storyarn/sheets/assets/commands/assets.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Sheet asset writes apply the Platform-owned storage entitlement"
    },
    %{
      source: "lib/storyarn/sheets/assets/events/assets.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Sheet Assets publishes its owned business facts through the Platform reaction contract"
    },
    %{
      source: "lib/storyarn/sheets/editor/commands/item_capacity.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "The Sheet editor applies the Platform-owned project item entitlement"
    },
    %{
      source: "lib/storyarn/sheets/editor/commands/sheets.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Sheet mutations request durable notification delivery through the public Platform contract"
    },
    %{
      source: "lib/storyarn/sheets/editor/events/blocks.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "The Sheet editor publishes its owned block facts through the Platform reaction contract"
    },
    %{
      source: "lib/storyarn/sheets/versioning/commands/named_version_capacity.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Sheet Versioning applies the Platform-owned named-version entitlement"
    },
    %{
      source: "lib/storyarn/sheets/versioning/events/versions.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Sheet Versioning publishes its owned business facts through the Platform reaction contract"
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
      source: "lib/storyarn_web/live/project_settings_live/general.ex",
      target: "lib/storyarn/localization.ex",
      kinds: ["runtime"],
      reason: "Project settings delegates ordinary source-language reads and writes to the public Localization facade"
    },
    %{
      source: "lib/storyarn/accounts/authentication/delivery/email_change/content.ex",
      target: "lib/storyarn/platform/adapters/email/layout.ex",
      kinds: ["runtime"],
      reason: "Account-owned email-change content uses the shared technical email layout"
    },
    %{
      source: "lib/storyarn/accounts/authentication/delivery/password_reset/content.ex",
      target: "lib/storyarn/platform/adapters/email/layout.ex",
      kinds: ["runtime"],
      reason: "Account-owned password-reset content uses the shared technical email layout"
    },
    %{
      source: "lib/storyarn/accounts/authentication/adapters/email/mailer.ex",
      target: "lib/storyarn/platform/adapters/email/mailer.ex",
      kinds: ["runtime"],
      reason: "The Account email adapter hands rendered messages to the application mailer"
    },
    %{
      source: "lib/storyarn_web/live/user_live/login.ex",
      target: "lib/storyarn/platform/adapters/email/mailer.ex",
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
      source: "lib/storyarn/workspaces/invitations/delivery/content.ex",
      target: "lib/storyarn/platform/adapters/email/layout.ex",
      kinds: ["runtime"],
      reason: "Workspace-owned invitation content uses the shared technical email layout"
    },
    %{
      source: "lib/storyarn/workspaces/invitations/adapters/email/mailer.ex",
      target: "lib/storyarn/platform/adapters/email/mailer.ex",
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
      source: "lib/storyarn/platform/discovery/queries/global_search/destinations.ex",
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
      source: "lib/storyarn/platform/discovery/queries/global_search/variable_search.ex",
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
      source: "lib/storyarn/scenes/editor/commands/scenes.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Scene mutations request durable notification delivery through the public Platform contract"
    },
    %{
      source: "lib/storyarn/platform/reactions/events/product_metrics.ex",
      target: "lib/storyarn/platform/reactions/adapters/analytics.ex",
      kinds: ["runtime"],
      reason: "Platform product metrics owns the only new product-context access to the analytics transport"
    },
    %{
      source: "lib/storyarn/platform/reactions/reactions.ex",
      target: "lib/storyarn/platform/reactions/adapters/analytics.ex",
      kinds: ["runtime"],
      reason: "The Platform Reactions facade mediates allowlisted presentation analytics"
    },
    %{
      source: "lib/storyarn/platform/reactions/events/product_metrics.ex",
      target: "lib/storyarn/platform/reactions/contracts/analytics_event_contract.ex",
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
      source: "lib/storyarn_web/live/workspace_live/show.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "The workspace home reads plan policy through the public Platform facade"
    },
    %{
      source: "lib/storyarn/platform/adapters/configuration/urls.ex",
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
