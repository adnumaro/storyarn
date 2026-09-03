# ENG-92 code boundaries plus incremental ENG-103 persistence ownership. The
# shared schema remains intentional; semantic write authority is added one
# reviewed table/workflow at a time instead of inferred from Ecto module names.
# PostgreSQL roles and schema separation remain a later ENG-106 concern.

# These are the bounded contexts sealed by the current ENG-92 ratchet.
bounded_contexts = [
  :accounts,
  :workspaces,
  :commercial,
  :platform,
  :projects,
  :sheets,
  :flows,
  :scenes,
  :localization,
  :ai
]

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
      functions: [
        %{identity: "defp insert_language/2", operations: [:insert]},
        %{identity: "defp reactivate_language/3", operations: [:update]}
      ],
      role: :command,
      reason: "adds or reactivates a Project language and reconciles its localized-text inventory",
      transaction: "runs inside the command's Repo.transaction",
      locks_or_preconditions: "locks the project and localization inventory before mutation"
    },
    %{
      path: "lib/storyarn/localization/languages/commands/change_source.ex",
      functions: [
        %{identity: "defp promote_source_language/2", operations: [:update, :update_all]},
        %{identity: "defp reactivate_or_insert_source_candidate/2", operations: [:insert!, :update!]}
      ],
      role: :command,
      reason: "owns ordinary source-language promotion and optional translation reset",
      transaction: "runs inside the command's Repo.transaction",
      locks_or_preconditions: "locks the project and localization inventory before mutation"
    },
    %{
      path: "lib/storyarn/localization/languages/commands/remove.ex",
      functions: [%{identity: "defp archive_language!/1", operations: [:update]}],
      role: :command,
      reason: "archives an ordinary target language and its localized-text inventory",
      transaction: "runs inside the command's Repo.transaction",
      locks_or_preconditions: "locks the project, localization inventory and selected language before mutation"
    },
    %{
      path: "lib/storyarn/localization/languages/commands/reorder.ex",
      functions: [],
      role: :command_orchestrator,
      reason: "owns ordinary language ordering and delegates the set-based write to the declared adapter",
      transaction: "runs inside the command's Repo.transaction",
      locks_or_preconditions: "locks the project and every active language row before delegating the position update"
    },
    %{
      path: "lib/storyarn/localization/languages/commands/update.ex",
      functions: [%{identity: "def run/2", operations: [:update]}],
      role: :command,
      reason: "updates ordinary language metadata",
      transaction: "runs inside the command's Repo.transaction",
      locks_or_preconditions: "locks the project, localization inventory and selected language before mutation"
    },
    %{
      path: "lib/storyarn/localization/languages/adapters/positions/postgres.ex",
      functions: [%{identity: "def set_positions/2", operations: [:update]}],
      role: :persistence_adapter,
      reason: "the reorder command delegates its set-based position update to one PostgreSQL adapter",
      transaction: "called inside Languages.Commands.Reorder's Repo.transaction",
      locks_or_preconditions:
        "the reorder command locks the project and every active language row before calling the adapter"
    }
  ],
  foreign_schema_mappings: %{
    flows: [
      "lib/storyarn/flows/versioning/projections/project_language_record.ex"
    ],
    sheets: [
      "lib/storyarn/sheets/versioning/projections/project_language_record.ex"
    ]
  },
  privileged_project_schema_mappings: [
    "lib/storyarn/projects/content/localization/records/project_language_record.ex"
  ],
  foreign_readers: %{
    flows: [
      "lib/storyarn/flows/versioning/execution/localization_codec.ex"
    ],
    projects: [
      "lib/storyarn/projects/content/localization/queries/read_model.ex",
      "lib/storyarn/projects/interchange/exports/queries/data_collector.ex",
      "lib/storyarn/projects/templates/execution/audit.ex",
      "lib/storyarn/projects/versioning/execution/localization_snapshot_codec.ex"
    ],
    sheets: [
      "lib/storyarn/sheets/versioning/execution/localization_codec.ex"
    ]
  },
  # ENG-103 moved every localized-text write out of these consumers. Keeping
  # this field explicit makes a future mixed reader/writer fail the inventory
  # until its exact source and content fingerprint are reviewed.
  reviewed_mixed_foreign_consumers: [],
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
          mapping_paths: [
            "lib/storyarn/projects/content/localization/records/project_language_record.ex"
          ],
          functions: [%{identity: "def import_language/2", operations: [:insert]}]
        },
        %{
          path: "lib/storyarn/projects/interchange/imports/commands/replacement.ex",
          mapping_paths: [
            "lib/storyarn/projects/content/localization/records/project_language_record.ex"
          ],
          functions: [%{identity: "defp archive_active_localization/1", operations: [:update_all]}]
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
          mapping_paths: [
            "lib/storyarn/projects/content/localization/records/project_language_record.ex"
          ],
          functions: [%{identity: "defp restore_languages/4", operations: [:insert_all]}]
        },
        %{
          path: "lib/storyarn/projects/versioning/execution/project_snapshot_restore_executor.ex",
          mapping_paths: [
            "lib/storyarn/projects/content/localization/records/project_language_record.ex"
          ],
          functions: [
            %{
              identity: "defp reconcile_localization_before_materialization/2",
              operations: [:update_all]
            }
          ]
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

# The ENG-103 table inventories below use one conservative source analyzer.
# It is intentionally a source-level ratchet, not a database security boundary.
persistence_write_analyzer = %{
  scanner: "Storyarn.Architecture.PersistenceWriteOwnershipTest.table_mutations/4",
  scope: "Elixir sources under lib/**/*.ex, including Web, workers and operator Mix tasks",
  detects:
    "Repo and Ecto.Multi writes through aliases, imports and fully normalized pipes; private injected-Repo helpers require unambiguous Storyarn.Repo provenance at every visible local call site, reject ambiguous alias chains, invalidate rebinding/shadowing and support lexical Ecto.Multi.run callbacks; Repo imports, Repo write captures, Function.capture, apply dispatch and Repo-shaped compound receivers are rejected; public variable-Repo writers are rejected unless structurally sealed as transparent delegates; reviewed transparent materialization delegates require direct qualified calls with proven Repo provenance and a schema whose complete private caller set is statically restricted to literal targets; runtime struct schemas and insert_all targets with any opaque caller are rejected; binary table attributes assembled from static fragments remain discoverable candidates but do not count as literal generic-write authority; association-mutating changeset stages, build_assoc, direct preloaded-field write targets, field/map/tuple aliases and mutating Enum, Stream or Task callbacks are rejected; Repo and Ecto.Adapters.SQL raw SQL resolves from literals, binary module attributes, single-assignment local bindings and static concatenation, while every unresolved statement must match the exact reviewed dynamic-writer inventory",
  limits: [
    "every unresolved raw-SQL call fails the global guard unless its exact path/function and pinned module digest appear in reviewed_dynamic_writers; runtime-generated table names therefore require an explicit reviewed contract",
    "a raw-SQL parameter rebound in the function, or a local binding assigned more than once, is deliberately unresolved for every call in that function; later assignments and opaque branches cannot retroactively make an earlier statement appear safe",
    "dynamic Repo module/function dispatch is rejected instead of inferred; transparent delegates additionally reject apply, Function.capture, capture, import and piped dynamic dispatch",
    "Repo provenance and target propagation are limited to visible local functions in one source file and a reviewed set of Ecto, Map, Enum, Stream and Task forms; arbitrary fallbacks, external helper returns, custom macros and unmodelled callbacks are not trusted",
    "a variable-receiver write without proven Storyarn.Repo provenance fails the global guard; public variable-receiver writers are forbidden unless their exact callers are sealed as transparent delegates; direct dynamic writes inside callbacks must first be exposed through a local helper whose Repo argument can be attributed lexically",
    "the variable-receiver guard conservatively treats insert/update/delete-shaped calls as persistence capabilities and may reject a non-Ecto technical adapter with the same API",
    "generic schema attribution is universal only across direct private callers in the same source file; public selectors, captures, external calls and runtime branches remain opaque and require refactoring rather than implicit authority",
    "inline from/select bindings are resolved to their selected record; association-mutating changeset stages, build_assoc and direct field/map/tuple-backed writes are rejected, while selecting a joined binding from another opaque prebuilt query remains outside the source analyzer",
    "source-wide alias collection and name-based taint are conservative and may flag unrelated aliases or same-named variables in nested scopes",
    "database triggers are not inspected",
    "row predicates and inserted source_type values are reviewed metadata; the scanner identifies table effects, not row-level ownership",
    "multiple call sites with the same path, function and operation collapse into one writer identity",
    "migrations, tests and runtime-generated code are outside this inventory"
  ]
}

entity_reference_persistence_ownership = %{
  table: "entity_references",
  source_owners: %{
    "block" => :sheets,
    "flow_node" => :flows,
    "scene_pin" => :scenes,
    "scene_zone" => :scenes
  },
  ordinary_writers: [
    %{
      context: :flows,
      source_types: ["flow_node"],
      path: "lib/storyarn/flows/references/commands/entity_reference_tracker.ex",
      functions: [
        %{identity: "def delete_references/1", operations: [:delete_all]},
        %{identity: "defp insert_references/3", operations: [:insert_all]}
      ],
      reason: "Flows maintains the entity-reference rows derived from Flow node data"
    },
    %{
      context: :scenes,
      source_types: ["scene_pin", "scene_zone"],
      path: "lib/storyarn/scenes/references/commands/entity_projection.ex",
      functions: [
        %{identity: "def delete_pin_references/1", operations: [:delete_all]},
        %{identity: "def delete_zone_references/1", operations: [:delete_all]},
        %{identity: "defp insert_references/3", operations: [:insert_all]},
        %{identity: "defp replace_references/4", operations: [:delete_all]}
      ],
      reason: "Scenes maintains the entity-reference rows derived from pins and zones"
    },
    %{
      context: :sheets,
      source_types: ["block"],
      path: "lib/storyarn/sheets/references/commands/entity_projection.ex",
      functions: [
        %{identity: "def delete_block_references/1", operations: [:delete_all]},
        %{identity: "def delete_block_references_for_sources/1", operations: [:delete_all]},
        %{identity: "def delete_target_references/2", operations: [:delete_all]},
        %{identity: "def update_block_references/2", operations: [:delete_all]},
        %{identity: "defp batch_insert_references/4", operations: [:insert_all]}
      ],
      reason: "Sheets maintains the entity-reference rows derived from Sheet blocks"
    }
  ],
  privileged_writers: [
    %{
      context: :projects,
      source_types: ["block", "flow_node"],
      exception: :project_reconstitution_recovery_and_trash,
      path: "lib/storyarn/projects/references/commands/entity_reference_projection.ex",
      mapping_paths: [
        "lib/storyarn/projects/references/entities/entity_reference.ex"
      ],
      functions: [
        %{identity: "def delete_block_references/1", operations: [:delete_all]},
        %{identity: "def delete_flow_node_references/1", operations: [:delete_all]},
        %{identity: "def delete_target_references/2", operations: [:delete_all]},
        %{identity: "def update_block_references/2", operations: [:delete_all]},
        %{identity: "defp batch_insert_references/4", operations: [:insert_all]}
      ],
      reason: "Projects reconstructs or removes its closed Project graph without borrowing ordinary Flow or Sheet writers"
    },
    %{
      context: :projects,
      source_types: ["scene_pin", "scene_zone"],
      exception: :project_reconstitution_and_recovery,
      path: "lib/storyarn/projects/references/commands/scene_entity_reference_tracker.ex",
      mapping_paths: [
        "lib/storyarn/projects/references/records/entity_reference_record.ex"
      ],
      functions: [
        %{identity: "defp insert_references/3", operations: [:insert_all]},
        %{identity: "defp replace_references/4", operations: [:delete_all]}
      ],
      reason: "Projects reconstructs Scene-derived references inside privileged Project materialization"
    }
  ],
  analyzer: persistence_write_analyzer
}

variable_reference_persistence_ownership = %{
  table: "variable_references",
  source_owners: %{
    "flow_node" => :flows,
    "scene_ambient_flow" => :scenes,
    "scene_pin" => :scenes,
    "scene_zone" => :scenes
  },
  ordinary_writers: [
    %{
      context: :flows,
      source_types: ["flow_node"],
      path: "lib/storyarn/flows/references/commands/variable_reference_tracker.ex",
      functions: [
        %{identity: "def delete_references/1", operations: [:delete_all]},
        %{identity: "defp delete_replaced_references/2", operations: [:delete_all]},
        %{identity: "defp replace_references/3", operations: [:insert_all]}
      ],
      reason: "Flows maintains the variable-reference rows derived from Flow node data"
    },
    %{
      context: :scenes,
      source_types: ["scene_ambient_flow", "scene_pin", "scene_zone"],
      path: "lib/storyarn/scenes/references/commands/variable_projection.ex",
      functions: [
        %{identity: "defp delete_references/2", operations: [:delete_all]},
        %{identity: "defp insert_references/3", operations: [:insert_all]}
      ],
      reason: "Scenes maintains the variable-reference rows derived from its pins, zones and ambient flows"
    }
  ],
  privileged_writers: [
    %{
      context: :projects,
      source_types: ["flow_node", "scene_ambient_flow", "scene_pin", "scene_zone"],
      exception: :project_reconstitution_recovery_and_trash,
      path: "lib/storyarn/projects/references/commands/variable_reference_tracker.ex",
      mapping_paths: [
        "lib/storyarn/projects/references/entities/variable_reference.ex"
      ],
      functions: [
        %{identity: "defp insert_missing_references/4", operations: [:insert_all]},
        %{identity: "defp insert_reference_entries/1", operations: [:insert_all]},
        %{identity: "defp replace_references/4", operations: [:delete_all]}
      ],
      reason:
        "Projects reconstructs its closed Project graph and restores Flow trash through its independently owned tracker"
    },
    %{
      context: :projects,
      source_types: ["flow_node", "scene_ambient_flow", "scene_pin", "scene_zone"],
      exception: :exact_project_snapshot_restore,
      path: "lib/storyarn/projects/versioning/execution/project_snapshot_restore_executor.ex",
      mapping_paths: [
        "lib/storyarn/projects/references/entities/variable_reference.ex"
      ],
      functions: [
        %{identity: "defp delete_active_variable_references_by_source/2", operations: [:delete_all]}
      ],
      reason: "exact Project restore clears the active closed graph before rebuilding every captured reference"
    },
    %{
      context: :sheets,
      source_types: ["flow_node", "scene_ambient_flow", "scene_pin", "scene_zone"],
      exception: :sheet_snapshot_additive_reconciliation,
      path: "lib/storyarn/sheets/references/commands/variable_projection.ex",
      mapping_paths: [
        "lib/storyarn/sheets/references/records/variable_reference_record.ex"
      ],
      functions: [
        %{identity: "defp insert_missing_references/4", operations: [:insert_all]}
      ],
      reason:
        "Sheet restore additively restores missing usages of Sheet-owned variables without deleting source-owner rows"
    }
  ],
  analyzer: persistence_write_analyzer
}

# Assets are a Projects-owned aggregate even when another tool owns the upload
# or restore use case that requests registration. Consumer contexts retain
# storage transfer, quota accounting, compensation and their local read model;
# only these Projects writers may mutate the shared `assets` rows.
asset_persistence_ownership = %{
  table: "assets",
  ownership_model: :single_context_writer,
  ordinary_owner: :projects,
  ordinary_writers: [
    %{
      context: :projects,
      path: "lib/storyarn/projects/assets/commands/asset_registration.ex",
      functions: [
        %{identity: "defp insert_asset/4", operations: [:insert]},
        %{identity: "defp update_variant_link/2", operations: [:update]}
      ],
      reason:
        "Projects validates and registers assets requested by Sheet, Scene and Flow use cases inside their existing transactions"
    },
    %{
      context: :projects,
      path: "lib/storyarn/projects/assets/execution/asset_operations.ex",
      functions: [
        %{identity: "def import_asset/2", operations: [:insert]},
        %{identity: "def import_snapshot_asset/3", operations: [:insert]},
        %{identity: "def update_imported_snapshot_asset_locked/3", operations: [:update]},
        %{identity: "defp create_asset_record_with_lock/5", operations: [:insert]},
        %{identity: "defp insert_snapshot_asset_batches/1", operations: [:insert_all]},
        %{identity: "defp update_asset_in_transaction/2", operations: [:update]},
        %{identity: "defp upsert_snapshot_asset_batches/1", operations: [:insert_all]}
      ],
      reason: "Projects owns ordinary asset lifecycle plus validated import and snapshot materialization"
    },
    %{
      context: :projects,
      path: "lib/storyarn/projects/assets/execution/asset_trash.ex",
      functions: [
        %{identity: "defp delete_asset_rows/1", operations: [:delete]},
        %{identity: "defp restore_assets/1", operations: [:update]},
        %{identity: "defp trash_assets/3", operations: [:update]}
      ],
      reason: "Projects owns asset trash and restoration as part of the Project asset lifecycle"
    },
    %{
      context: :projects,
      path: "lib/storyarn/projects/assets/execution/blob_store.ex",
      functions: [%{identity: "defp copy_and_insert_asset/5", operations: [:insert]}],
      reason: "Projects owns the asset row inserted after a guarded canonical blob copy"
    }
  ],
  privileged_writers: [],
  analyzer: persistence_write_analyzer
}

# Localization owns ordinary localized-text persistence. Projects retains four
# explicit closed-graph exceptions for import/replacement/recovery/exact restore;
# those are reconstitution responsibilities, never permission for ordinary
# Project features to write Localization state.
localized_text_persistence_ownership = %{
  table: "localized_texts",
  ownership_model: :single_context_writer_with_project_reconstitution,
  ordinary_owner: :localization,
  ordinary_writers: [
    %{
      context: :localization,
      path: "lib/storyarn/localization/texts/adapters/upserts/postgres.ex",
      functions: [%{identity: "def upsert_chunk/1", operations: [:insert]}],
      reason: "Localization owns the set-based PostgreSQL upsert used by ordinary extraction"
    },
    %{
      context: :localization,
      path: "lib/storyarn/localization/texts/commands/create.ex",
      functions: [%{identity: "def create_text/2", operations: [:insert]}],
      reason: "Localization owns ordinary localized-text creation"
    },
    %{
      context: :localization,
      path: "lib/storyarn/localization/texts/commands/lifecycle.ex",
      functions: [
        %{identity: "def archive_texts_for_active_target_locales/4", operations: [:update_all]},
        %{identity: "def archive_texts_for_sources/3", operations: [:update_all]},
        %{identity: "def delete_texts_for_source_field/3", operations: [:update_all]},
        %{identity: "def purge_texts_for_sources/2", operations: [:delete_all]},
        %{identity: "def reset_project_texts/1", operations: [:delete_all]}
      ],
      reason: "Localization owns archive, purge and reset transitions for its text inventory"
    },
    %{
      context: :localization,
      path: "lib/storyarn/localization/texts/commands/reconcile.ex",
      functions: [
        %{identity: "def bulk_import_texts/1", operations: [:insert_all]},
        %{identity: "defp archive_obsolete_project_texts/2", operations: [:update_all]}
      ],
      reason: "Localization owns ordinary import and reconciliation of localized text rows"
    },
    %{
      context: :localization,
      path: "lib/storyarn/localization/texts/commands/update.ex",
      functions: [%{identity: "defp update_text_in_transaction/2", operations: [:update]}],
      reason: "Localization owns ordinary translation and review updates"
    },
    %{
      context: :localization,
      path: "lib/storyarn/localization/texts/commands/upsert.ex",
      functions: [
        %{identity: "defp do_upsert_text/3", operations: [:insert]},
        %{identity: "defp update_source_text/2", operations: [:update]}
      ],
      reason: "Localization owns idempotent source-text upsert"
    },
    %{
      context: :localization,
      path: "lib/storyarn/localization/texts/commands/version_restore.ex",
      functions: [
        %{identity: "defp archive_active_target_flow_nodes/4", operations: [:update_all]},
        %{identity: "defp archive_flow_nodes/4", operations: [:update_all]},
        %{identity: "defp insert_restore_entries/1", operations: [:insert_all]}
      ],
      reason: "Localization persists exact Flow and Sheet version state inside the caller-owned restore transaction"
    }
  ],
  privileged_writers: [
    %{
      context: :projects,
      exception: :project_import_reconstitution,
      path: "lib/storyarn/projects/interchange/imports/commands/localization_reconstitution.ex",
      mapping_paths: [
        "lib/storyarn/projects/content/localization/records/localized_text_record.ex"
      ],
      functions: [%{identity: "def bulk_import_texts/1", operations: [:insert_all]}],
      reason: "validated Project import materializes the captured localization graph"
    },
    %{
      context: :projects,
      exception: :project_replacement,
      path: "lib/storyarn/projects/interchange/imports/commands/replacement.ex",
      mapping_paths: [
        "lib/storyarn/projects/content/localization/records/localized_text_record.ex"
      ],
      functions: [%{identity: "defp archive_active_localization/1", operations: [:update_all]}],
      reason: "replacement import archives the current closed Project graph before materialization"
    },
    %{
      context: :projects,
      exception: :project_recovery,
      path: "lib/storyarn/projects/versioning/execution/project_recovery.ex",
      mapping_paths: [
        "lib/storyarn/projects/content/localization/records/localized_text_record.ex"
      ],
      functions: [%{identity: "defp insert_recovery_text_chunk/1", operations: [:insert_all]}],
      reason: "Project recovery reconstructs exact snapshot-owned localized text rows"
    },
    %{
      context: :projects,
      exception: :exact_project_snapshot_restore,
      path: "lib/storyarn/projects/versioning/execution/project_snapshot_restore_executor.ex",
      mapping_paths: [
        "lib/storyarn/projects/content/localization/records/localized_text_record.ex"
      ],
      functions: [
        %{identity: "defp reconcile_localization_before_materialization/2", operations: [:update_all]}
      ],
      reason: "exact Project restore clears the active localization graph before rebuilding the snapshot"
    }
  ],
  analyzer: persistence_write_analyzer
}

# Cleanup handoff rows form a deliberately shared technical protocol. Tool
# contexts may only append storage-compensation requests through their exact
# adapter. Projects owns retries, rotation, deferral and every lifecycle update.
storage_cleanup_persistence_ownership = %{
  table: "storage_cleanup_requests",
  ownership_model: :append_only_consumer_requests_projects_lifecycle,
  request_owners: [:flows, :scenes, :sheets],
  lifecycle_owner: :projects,
  ordinary_writers: [
    %{
      context: :flows,
      write_authority: :append_storage_compensation_request,
      path: "lib/storyarn/flows/versioning/adapters/storage/asset_storage_compensation.ex",
      request_record_path: "lib/storyarn/flows/versioning/entities/storage_cleanup_request_record.ex",
      request_changeset: :flow_restore_changeset,
      functions: [%{identity: "defp persist_cleanup_request/1", operations: [:insert]}],
      reason: "Flow restore may durably hand off cleanup when immediate object deletion fails"
    },
    %{
      context: :projects,
      write_authority: :full_lifecycle,
      path: "lib/storyarn/projects/assets/execution/multipart_cleanup.ex",
      functions: [
        %{identity: "def reopen_confirmed/1", operations: [:update]},
        %{identity: "defp block_unbound_legacy_request/1", operations: [:update]},
        %{identity: "defp clear_retry_state_for_replay/1", operations: [:update]},
        %{identity: "defp consume_confirmed_request/2", operations: [:delete]},
        %{identity: "defp enter_quiet/2", operations: [:update]},
        %{identity: "defp initialize_and_claim/2", operations: [:update]},
        %{identity: "defp persist_claim/2", operations: [:update]},
        %{identity: "defp persist_confirmed/3", operations: [:update]},
        %{identity: "defp persist_discovery/4", operations: [:update]},
        %{identity: "defp persist_failure/2", operations: [:update]},
        %{identity: "defp persist_residue_state/3", operations: [:update]},
        %{identity: "defp release_claim/1", operations: [:update]},
        %{identity: "defp reset_blocked_request_for_replay/1", operations: [:update]},
        %{identity: "defp retire_expired_claim/2", operations: [:update]},
        %{identity: "defp transition_claimed/2", operations: [:update]}
      ],
      reason: "Projects owns the durable exact multipart cleanup state machine"
    },
    %{
      context: :projects,
      write_authority: :full_lifecycle,
      path: "lib/storyarn/projects/assets/execution/storage_compensation.ex",
      functions: [
        %{identity: "defp insert_cleanup_request_with_handoff/2", operations: [:insert]},
        %{identity: "defp retry_persisted_cleanup_request/2", operations: [:delete]},
        %{identity: "defp rotate_persisted_cleanup_request/2", operations: [:delete, :insert]}
      ],
      reason: "Projects owns durable cleanup creation, retry and rotation"
    },
    %{
      context: :scenes,
      write_authority: :append_storage_compensation_request,
      path: "lib/storyarn/scenes/assets/adapters/storage/compensation.ex",
      request_record_path: "lib/storyarn/scenes/assets/entities/storage_cleanup_request_record.ex",
      request_changeset: :scene_restore_changeset,
      functions: [%{identity: "defp persist_cleanup_request/1", operations: [:insert]}],
      reason: "Scene restore may durably hand off cleanup when immediate object deletion fails"
    },
    %{
      context: :sheets,
      write_authority: :append_storage_compensation_request,
      path: "lib/storyarn/sheets/assets/adapters/storage/compensation.ex",
      request_record_path: "lib/storyarn/sheets/assets/entities/storage_cleanup_request_record.ex",
      request_changeset: :sheet_restore_changeset,
      functions: [%{identity: "defp persist_cleanup_request/1", operations: [:insert]}],
      reason: "Sheet restore may durably hand off cleanup when immediate object deletion fails"
    }
  ],
  privileged_writers: [],
  analyzer: persistence_write_analyzer
}

# ENG-113 closes the classification gap around duplicated Ecto mappings. The
# inventory is discovered from source: any SQL table mapped by more than one
# bounded context is shared, regardless of whether the duplicate lives under
# `projections/`, `records/` or `entities/`.
#
# For the tables already sealed by `persistence_ownership`, their ordinary
# writer contexts and exact privileged writers remain the stronger source of
# truth. For the rest, one and only one context must own an `entities/` mapping.
# The two exceptions below cannot be inferred from that structural rule:
# entity versions are deliberately partitioned by tool, while cleanup receipts
# are database-trigger-owned evidence exposed through read models only.
#
# Foreign mappings are passive by default. A foreign write must be named here
# by table, context, source path, function and operation. Adding a mapping below
# `entities/` or `records/` never grants write authority on its own.
shared_persistence_mapping_policy = %{
  bounded_contexts: bounded_contexts,
  passive_mapping_roots: ["architecture", "public", "workers"],
  mapping_root: "lib/storyarn",
  write_root: "lib",
  transparent_write_delegates: [
    %{
      module: "Storyarn.Projects.Versioning.MaterializationHelpers",
      path: "lib/storyarn/projects/versioning/execution/materialization_helpers.ex",
      function: :insert_all,
      arity: 3,
      repo_argument: 0,
      schema_argument: 1,
      operation: :insert_all,
      reason:
        "Project materializers share result normalization while each call site retains proven Repo and an attributable schema target"
    },
    %{
      module: "Storyarn.Projects.Versioning.MaterializationHelpers",
      path: "lib/storyarn/projects/versioning/execution/materialization_helpers.ex",
      function: :insert_one_returning_id,
      arity: 3,
      repo_argument: 0,
      schema_argument: 1,
      operation: :insert_all,
      reason:
        "Project materializers use one-row insert_all for deterministic returning IDs while each call site retains proven Repo and an attributable schema target"
    },
    %{
      module: "Storyarn.Scenes.Versioning.Commands.MaterializationHelpers",
      path: "lib/storyarn/scenes/versioning/commands/materialization_helpers.ex",
      function: :insert_all,
      arity: 3,
      repo_argument: 0,
      schema_argument: 1,
      operation: :insert_all,
      reason:
        "Scene restore shares result normalization while each call site retains proven Repo and an attributable schema target"
    },
    %{
      module: "Storyarn.Sheets.Versioning.Commands.MaterializationHelpers",
      path: "lib/storyarn/sheets/versioning/commands/materialization_helpers.ex",
      function: :insert_all,
      arity: 3,
      repo_argument: 0,
      schema_argument: 1,
      operation: :insert_all,
      reason:
        "Sheet restore shares result normalization while each call site retains proven Repo and an attributable schema target"
    },
    %{
      module: "Storyarn.Sheets.Versioning.Commands.MaterializationHelpers",
      path: "lib/storyarn/sheets/versioning/commands/materialization_helpers.ex",
      function: :insert_one_returning_id,
      arity: 3,
      repo_argument: 0,
      schema_argument: 1,
      operation: :insert_all,
      reason:
        "Sheet restore uses one-row insert_all for deterministic returning IDs while each call site retains proven Repo and an attributable schema target"
    }
  ],
  owner_context_overrides: %{
    entity_versions: %{
      owner_contexts: [:flows, :scenes, :sheets],
      application_write_mode: :exact_inventory,
      reason: "entity_versions is a row-partitioned protocol: each tool owns only its own entity_type rows"
    },
    storage_cleanup_ownership_receipts: %{
      owner_contexts: [:projects],
      application_write_mode: :no_application_writes,
      reason: "immutable cleanup evidence is written only by a database trigger; every application mapping is passive"
    }
  },
  exact_writers: [
    %{
      table: :entity_versions,
      context: :flows,
      authority: :flow_version_rows,
      entity_type: "flow",
      mapping_paths: [
        "lib/storyarn/flows/versioning/entities/entity_version_record.ex"
      ],
      path: "lib/storyarn/flows/versioning/commands/version_lifecycle.ex",
      functions: [
        %{identity: "defp delete_persisted_version/1", operations: [:delete]},
        %{identity: "defp insert_stored_version/6", operations: [:insert]},
        %{identity: "defp persist_locked_version/3", operations: [:update]}
      ],
      reason: "Flows owns only entity_versions rows whose entity_type is flow"
    },
    %{
      table: :entity_versions,
      context: :projects,
      authority: :project_sheet_hard_delete,
      entity_type: "sheet",
      mapping_paths: [
        "lib/storyarn/projects/versioning/projections/entity_version_record.ex"
      ],
      path: "lib/storyarn/projects/trash/execution/sheet_project_trash.ex",
      functions: [
        %{identity: "def hard_delete/1", operations: [:delete_all]}
      ],
      reason: "Project-owned Sheet hard delete removes only the deleted Sheet's version rows"
    },
    %{
      table: :entity_versions,
      context: :scenes,
      authority: :scene_version_rows,
      entity_type: "scene",
      mapping_paths: [
        "lib/storyarn/scenes/versioning/entities/entity_version_record.ex"
      ],
      path: "lib/storyarn/scenes/versioning/commands/version_lifecycle.ex",
      functions: [
        %{identity: "defp delete_persisted_version/1", operations: [:delete]},
        %{identity: "defp insert_stored_version/6", operations: [:insert]},
        %{identity: "defp persist_locked_version/3", operations: [:update]}
      ],
      reason: "Scenes owns only entity_versions rows whose entity_type is scene"
    },
    %{
      table: :entity_versions,
      context: :sheets,
      authority: :sheet_hard_delete,
      entity_type: "sheet",
      mapping_paths: [
        "lib/storyarn/sheets/versioning/entities/entity_version_record.ex"
      ],
      path: "lib/storyarn/sheets/editor/commands/sheets.ex",
      functions: [
        %{identity: "def permanently_delete_sheet/1", operations: [:delete_all]}
      ],
      reason: "Sheet hard delete removes only the deleted Sheet's version rows"
    },
    %{
      table: :entity_versions,
      context: :sheets,
      authority: :sheet_version_rows,
      entity_type: "sheet",
      mapping_paths: [
        "lib/storyarn/sheets/versioning/entities/entity_version_record.ex"
      ],
      path: "lib/storyarn/sheets/versioning/commands/version_lifecycle.ex",
      functions: [
        %{identity: "defp delete_persisted_version/1", operations: [:delete]},
        %{identity: "defp insert_stored_version/6", operations: [:insert]},
        %{identity: "defp persist_locked_version/3", operations: [:update]}
      ],
      reason: "Sheets owns only entity_versions rows whose entity_type is sheet"
    }
  ],
  reviewed_dynamic_writers: [
    %{
      context: :sheets,
      path: "lib/storyarn/sheets/editor/adapters/postgres/positions.ex",
      function: "def batch_set/3",
      tables: [:blocks, :sheets, :table_columns, :table_rows],
      operation: :update,
      module_sha256: "fecd6d264820fb01d3bc9e66748aab8d1fc91e8be7b9b33d0581c7c12ef9aaf2",
      reason: "the Sheet ordering adapter selects one table from a fixed allowlist before issuing its set-based UPDATE"
    }
  ],
  privileged_workflows: %{
    exact_project_restore: %{
      transaction: "the Project snapshot restore executor's enclosing restore transaction",
      locks_or_preconditions: "validated snapshot/project identity plus the executor's Project and materialization locks"
    },
    project_flow_materialization: %{
      transaction: "the enclosing Project snapshot materialization transaction",
      locks_or_preconditions: "validated snapshot rows and the builder's locked active Project graph"
    },
    project_flow_trash: %{
      transaction: "the Project-owned Flow trash, restore or hard-delete transaction",
      locks_or_preconditions:
        "an active Project and the affected Flow, node and captured-reference rows are locked before mutation"
    },
    project_import: %{
      transaction: "the validated Project import materializer's enclosing transaction",
      locks_or_preconditions: "validated import identity and payload plus the materializer's locked active Project graph"
    },
    project_recovery: %{
      transaction: "the Project recovery/materialization coordinator's enclosing transaction",
      locks_or_preconditions: "validated snapshot data and the coordinator's workspace, Project and materialization locks"
    },
    project_scene_materialization: %{
      transaction: "the enclosing Project snapshot materialization transaction",
      locks_or_preconditions: "validated snapshot rows and the builder's locked active Project graph"
    },
    project_scene_trash: %{
      transaction: "the Project-owned Scene trash, restore or hard-delete transaction",
      locks_or_preconditions: "the affected Project, Scene and descendant rows are resolved and locked before mutation"
    },
    project_sheet_materialization: %{
      transaction: "the enclosing Project snapshot materialization transaction",
      locks_or_preconditions: "validated snapshot rows and the builder's locked Project and inheritance sources"
    },
    project_sheet_trash: %{
      transaction: "the Project-owned Sheet trash, restore or hard-delete transaction",
      locks_or_preconditions:
        "an active Project and the affected Sheet, block, inheritance and reference rows are locked before mutation"
    }
  },
  privileged_writers: [
    %{
      table: :block_gallery_images,
      context: :projects,
      authority: :project_sheet_materialization,
      mapping_paths: ["lib/storyarn/projects/content/sheets/records/block_gallery_image_record.ex"],
      path: "lib/storyarn/projects/versioning/execution/builders/sheet_builder.ex",
      functions: [%{identity: "defp restore_gallery_images/6", operations: [:insert_all]}],
      reason: "Project snapshot materialization restores captured Sheet gallery images"
    },
    %{
      table: :blocks,
      context: :projects,
      authority: :project_import,
      mapping_paths: ["lib/storyarn/projects/content/sheets/records/block_record.ex"],
      path: "lib/storyarn/projects/interchange/imports/commands/sheet_import_persistence.ex",
      functions: [
        %{identity: "def import_block/2", operations: [:insert]},
        %{identity: "def link_block_value/2", operations: [:update_all]}
      ],
      reason: "validated Project import materializes Sheet blocks and remaps their embedded root references"
    },
    %{
      table: :blocks,
      context: :projects,
      authority: :project_sheet_trash,
      mapping_paths: ["lib/storyarn/projects/content/sheets/records/block_record.ex"],
      path: "lib/storyarn/projects/trash/execution/sheet_project_trash.ex",
      functions: [%{identity: "defp reconcile_active_block/2", operations: [:update!]}],
      reason: "Project-owned Sheet restore normalizes restored block references"
    },
    %{
      table: :blocks,
      context: :projects,
      authority: :project_sheet_materialization,
      mapping_paths: ["lib/storyarn/projects/content/sheets/records/block_record.ex"],
      path: "lib/storyarn/projects/versioning/execution/builders/sheet_builder.ex",
      functions: [
        %{identity: "defp insert_sheet_blocks/3", operations: [:insert_all]},
        %{identity: "defp update_inherited_from_block/2", operations: [:update_all]}
      ],
      reason: "Project snapshot materialization remaps captured block inheritance"
    },
    %{
      table: :blocks,
      context: :projects,
      authority: :project_recovery,
      mapping_paths: ["lib/storyarn/projects/content/sheets/records/block_record.ex"],
      path: "lib/storyarn/projects/versioning/execution/project_recovery.ex",
      functions: [
        %{identity: "defp insert_snapshot_import_block_tombstone/3", operations: [:insert_all]},
        %{identity: "defp remap_block_inheritance/4", operations: [:update_all]},
        %{identity: "defp remap_sheet_block_payloads/3", operations: [:update_all]}
      ],
      reason: "Project recovery remaps captured Sheet block identity and payload references"
    },
    %{
      table: :flow_connections,
      context: :projects,
      authority: :project_flow_materialization,
      mapping_paths: ["lib/storyarn/projects/content/flows/records/flow_connection_record.ex"],
      path: "lib/storyarn/projects/versioning/execution/builders/flow_builder.ex",
      functions: [%{identity: "defp insert_flow_connections/5", operations: [:insert]}],
      reason: "Project snapshot materialization restores captured Flow connections"
    },
    %{
      table: :flow_connections,
      context: :projects,
      authority: :project_import,
      mapping_paths: ["lib/storyarn/projects/content/flows/records/flow_connection_record.ex"],
      path: "lib/storyarn/projects/interchange/imports/commands/flow_import_persistence.ex",
      functions: [%{identity: "def bulk_insert_connections/2", operations: [:insert_all]}],
      reason: "validated Project import materializes captured Flow connections"
    },
    %{
      table: :flow_connections,
      context: :projects,
      authority: :project_recovery,
      mapping_paths: ["lib/storyarn/projects/content/flows/records/flow_connection_record.ex"],
      path: "lib/storyarn/projects/versioning/execution/project_recovery.ex",
      functions: [
        %{identity: "defp remap_single_flow_connection_endpoints/6", operations: [:update_all]},
        %{identity: "defp update_recovered_dynamic_exit_pin/6", operations: [:update]}
      ],
      reason: "Project recovery remaps captured Flow connection endpoints and exit pins"
    },
    %{
      table: :flow_node_sequence_configs,
      context: :projects,
      authority: :project_flow_materialization,
      mapping_paths: ["lib/storyarn/projects/content/flows/records/sequence_config_record.ex"],
      path: "lib/storyarn/projects/versioning/execution/builders/flow_builder.ex",
      functions: [%{identity: "defp insert_sequence_config/4", operations: [:insert]}],
      reason: "Project snapshot materialization restores captured Flow sequence configuration"
    },
    %{
      table: :flow_node_sequence_configs,
      context: :projects,
      authority: :project_import,
      mapping_paths: ["lib/storyarn/projects/content/flows/records/sequence_config_record.ex"],
      path: "lib/storyarn/projects/interchange/imports/commands/flow_import_persistence.ex",
      functions: [%{identity: "defp maybe_insert_sequence_config!/3", operations: [:insert]}],
      reason: "validated Project import materializes captured Flow sequence configuration"
    },
    %{
      table: :flow_node_sequence_tracks,
      context: :projects,
      authority: :project_flow_materialization,
      mapping_paths: ["lib/storyarn/projects/content/flows/records/sequence_track_record.ex"],
      path: "lib/storyarn/projects/versioning/execution/builders/flow_builder.ex",
      functions: [%{identity: "defp insert_sequence_tracks/7", operations: [:insert]}],
      reason: "Project snapshot materialization restores captured Flow sequence tracks"
    },
    %{
      table: :flow_node_sequence_visual_layers,
      context: :projects,
      authority: :project_flow_materialization,
      mapping_paths: ["lib/storyarn/projects/content/flows/records/sequence_visual_layer_record.ex"],
      path: "lib/storyarn/projects/versioning/execution/builders/flow_builder.ex",
      functions: [%{identity: "defp insert_sequence_visual_layer/5", operations: [:insert]}],
      reason: "Project snapshot materialization restores captured Flow sequence visual layers"
    },
    %{
      table: :flow_nodes,
      context: :projects,
      authority: :project_flow_materialization,
      mapping_paths: ["lib/storyarn/projects/content/flows/records/flow_node_record.ex"],
      path: "lib/storyarn/projects/versioning/execution/builders/flow_builder.ex",
      functions: [
        %{identity: "defp do_restore_exact_authored_node_types/4", operations: [:update_all]},
        %{identity: "defp insert_flow_nodes/7", operations: [:insert]},
        %{identity: "defp link_exact_snapshot_node_parent/6", operations: [:update]},
        %{identity: "defp link_portable_snapshot_node_parent/6", operations: [:update]}
      ],
      reason: "Project snapshot materialization restores and links captured Flow nodes"
    },
    %{
      table: :flow_nodes,
      context: :projects,
      authority: :project_import,
      mapping_paths: ["lib/storyarn/projects/content/flows/records/flow_node_record.ex"],
      path: "lib/storyarn/projects/interchange/imports/commands/flow_import_persistence.ex",
      functions: [
        %{identity: "def link_node_data/2", operations: [:update_all]},
        %{identity: "defp insert_import_node!/4", operations: [:insert]},
        %{identity: "defp update_node_parent!/2", operations: [:update]}
      ],
      reason: "validated Project import materializes and links captured Flow nodes"
    },
    %{
      table: :flow_nodes,
      context: :projects,
      authority: :project_flow_trash,
      mapping_paths: ["lib/storyarn/projects/content/flows/records/flow_node_record.ex"],
      path: "lib/storyarn/projects/trash/execution/flow_entity_trash_references.ex",
      functions: [
        %{identity: "defp restore_locked_flow_ref/3", operations: [:update_all]},
        %{identity: "defp sweep_rows/2", operations: [:update_all]}
      ],
      reason: "Project-owned Flow trash restores and sweeps captured node reference fields"
    },
    %{
      table: :flow_nodes,
      context: :projects,
      authority: :project_flow_trash,
      mapping_paths: ["lib/storyarn/projects/content/flows/records/flow_node_record.ex"],
      path: "lib/storyarn/projects/trash/execution/flow_project_trash.ex",
      functions: [%{identity: "defp normalize_restored_flow_node/2", operations: [:update]}],
      reason: "Project-owned Flow restore normalizes restored node references"
    },
    %{
      table: :flow_nodes,
      context: :projects,
      authority: :project_recovery,
      mapping_paths: ["lib/storyarn/projects/content/flows/records/flow_node_record.ex"],
      path: "lib/storyarn/projects/versioning/execution/project_recovery.ex",
      functions: [
        %{identity: "defp insert_snapshot_import_node_tombstones/4", operations: [:insert_all]},
        %{identity: "defp persist_remapped_node_data/3", operations: [:update_all]}
      ],
      reason: "Project recovery persists remapped captured Flow node payloads"
    },
    %{
      table: :flows,
      context: :projects,
      authority: :project_flow_materialization,
      mapping_paths: ["lib/storyarn/projects/content/flows/records/flow_record.ex"],
      path: "lib/storyarn/projects/versioning/execution/builders/flow_builder.ex",
      functions: [%{identity: "defp insert_flow_root/2", operations: [:insert]}],
      reason: "Project snapshot materialization restores the captured Flow root"
    },
    %{
      table: :flows,
      context: :projects,
      authority: :project_import,
      mapping_paths: ["lib/storyarn/projects/content/flows/records/flow_record.ex"],
      path: "lib/storyarn/projects/interchange/imports/commands/flow_import_persistence.ex",
      functions: [
        %{identity: "def import_flow/2", operations: [:insert]},
        %{identity: "def link_flow_parent/2", operations: [:update!]}
      ],
      reason: "validated Project import replaces, materializes and links captured Flows"
    },
    %{
      table: :flows,
      context: :projects,
      authority: :project_flow_trash,
      mapping_paths: ["lib/storyarn/projects/content/flows/records/flow_record.ex"],
      path: "lib/storyarn/projects/trash/execution/flow_project_trash.ex",
      functions: [
        %{identity: "def hard_delete/1", operations: [:delete]},
        %{identity: "defp restore_flow_transaction/2", operations: [:update]},
        %{identity: "defp soft_delete_descendants/2", operations: [:update_all]}
      ],
      reason: "Project owns the closed-graph Flow trash, restore and purge lifecycle"
    },
    %{
      table: :flows,
      context: :projects,
      authority: :project_recovery,
      mapping_paths: ["lib/storyarn/projects/content/flows/records/flow_record.ex"],
      path: "lib/storyarn/projects/versioning/execution/project_recovery.ex",
      functions: [
        %{identity: "defp apply_tree_position/5", operations: [:update_all]},
        %{identity: "defp insert_snapshot_import_root_tombstone_for_schema/7", operations: [:insert_all]},
        %{identity: "defp remap_flow_scene_id/5", operations: [:update_all]}
      ],
      reason: "Project recovery remaps captured Flow hierarchy and Flow-to-Scene identity"
    },
    %{
      table: :flows_entity_trash_refs,
      context: :projects,
      authority: :project_flow_trash,
      mapping_paths: [
        "lib/storyarn/projects/references/records/flow_entity_trash_reference_record.ex"
      ],
      path: "lib/storyarn/projects/trash/execution/flow_entity_trash_references.ex",
      functions: [%{identity: "defp sweep_rows/2", operations: [:insert_all]}],
      reason: "Project Flow trash captures durable references needed for exact restoration"
    },
    %{
      table: :localization_glossary_entries,
      context: :projects,
      authority: :project_import,
      mapping_paths: ["lib/storyarn/projects/content/localization/records/glossary_entry_record.ex"],
      path: "lib/storyarn/projects/interchange/imports/commands/localization_reconstitution.ex",
      functions: [%{identity: "def bulk_import_glossary_entries/1", operations: [:insert_all]}],
      reason: "validated Project import materializes captured glossary entries"
    },
    %{
      table: :localization_glossary_entries,
      context: :projects,
      authority: :project_recovery,
      mapping_paths: ["lib/storyarn/projects/content/localization/records/glossary_entry_record.ex"],
      path: "lib/storyarn/projects/versioning/execution/project_recovery.ex",
      functions: [%{identity: "defp restore_glossary/4", operations: [:insert_all]}],
      reason: "Project recovery materializes captured glossary entries"
    },
    %{
      table: :localization_glossary_entries,
      context: :projects,
      authority: :exact_project_restore,
      mapping_paths: ["lib/storyarn/projects/content/localization/records/glossary_entry_record.ex"],
      path: "lib/storyarn/projects/versioning/execution/project_snapshot_restore_executor.ex",
      functions: [
        %{identity: "defp reconcile_localization_before_materialization/2", operations: [:delete_all]}
      ],
      reason: "exact Project restore clears active glossary rows before closed-graph materialization"
    },
    %{
      table: :scene_ambient_flows,
      context: :projects,
      authority: :project_scene_materialization,
      mapping_paths: ["lib/storyarn/projects/content/scenes/records/scene_ambient_flow_record.ex"],
      path: "lib/storyarn/projects/versioning/execution/builders/scene_builder.ex",
      functions: [
        %{identity: "defp insert_materialized_ambient_flow_pairs/2", operations: [:insert_all]}
      ],
      reason: "Project snapshot materialization restores captured Scene ambient Flow links"
    },
    %{
      table: :scene_ambient_flows,
      context: :projects,
      authority: :project_recovery,
      mapping_paths: ["lib/storyarn/projects/content/scenes/records/scene_ambient_flow_record.ex"],
      path: "lib/storyarn/projects/versioning/execution/project_recovery.ex",
      functions: [%{identity: "defp remap_scene_ambient_flows/5", operations: [:insert]}],
      reason: "Project recovery materializes captured Scene ambient Flow links"
    },
    %{
      table: :scene_annotations,
      context: :projects,
      authority: :project_scene_materialization,
      mapping_paths: ["lib/storyarn/projects/content/scenes/records/scene_annotation_record.ex"],
      path: "lib/storyarn/projects/versioning/execution/builders/scene_builder.ex",
      functions: [%{identity: "defp insert_scene_snapshot_rows/4", operations: [:insert_all]}],
      reason: "Project snapshot materialization restores captured Scene annotations"
    },
    %{
      table: :scene_annotations,
      context: :projects,
      authority: :project_import,
      mapping_paths: ["lib/storyarn/projects/content/scenes/records/scene_annotation_record.ex"],
      path: "lib/storyarn/projects/interchange/imports/commands/scene_import_persistence.ex",
      functions: [%{identity: "defp bulk_insert/3", operations: [:insert_all]}],
      reason: "validated Project import materializes captured Scene annotations"
    },
    %{
      table: :scene_connections,
      context: :projects,
      authority: :project_scene_materialization,
      mapping_paths: ["lib/storyarn/projects/content/scenes/records/scene_connection_record.ex"],
      path: "lib/storyarn/projects/versioning/execution/builders/scene_builder.ex",
      functions: [%{identity: "defp insert_scene_snapshot_rows/4", operations: [:insert_all]}],
      reason: "Project snapshot materialization restores captured Scene connections"
    },
    %{
      table: :scene_connections,
      context: :projects,
      authority: :project_import,
      mapping_paths: ["lib/storyarn/projects/content/scenes/records/scene_connection_record.ex"],
      path: "lib/storyarn/projects/interchange/imports/commands/scene_import_persistence.ex",
      functions: [%{identity: "defp bulk_insert/3", operations: [:insert_all]}],
      reason: "validated Project import materializes captured Scene connections"
    },
    %{
      table: :scene_connections,
      context: :projects,
      authority: :project_recovery,
      mapping_paths: ["lib/storyarn/projects/content/scenes/records/scene_connection_record.ex"],
      path: "lib/storyarn/projects/versioning/execution/project_recovery.ex",
      functions: [%{identity: "defp remap_single_scene_connection_ref/4", operations: [:update_all]}],
      reason: "Project recovery remaps captured Scene connection targets"
    },
    %{
      table: :scene_layers,
      context: :projects,
      authority: :project_scene_materialization,
      mapping_paths: ["lib/storyarn/projects/content/scenes/records/scene_layer_record.ex"],
      path: "lib/storyarn/projects/versioning/execution/builders/scene_builder.ex",
      functions: [%{identity: "defp insert_scene_layers/4", operations: [:insert_all]}],
      reason: "Project snapshot materialization restores captured Scene layers"
    },
    %{
      table: :scene_layers,
      context: :projects,
      authority: :project_import,
      mapping_paths: ["lib/storyarn/projects/content/scenes/records/scene_layer_record.ex"],
      path: "lib/storyarn/projects/interchange/imports/commands/scene_import_persistence.ex",
      functions: [%{identity: "def import_layer/2", operations: [:insert]}],
      reason: "validated Project import materializes captured Scene layers"
    },
    %{
      table: :scene_pins,
      context: :projects,
      authority: :project_scene_materialization,
      mapping_paths: ["lib/storyarn/projects/content/scenes/records/scene_pin_record.ex"],
      path: "lib/storyarn/projects/versioning/execution/builders/scene_builder.ex",
      functions: [%{identity: "defp insert_scene_snapshot_rows/4", operations: [:insert_all]}],
      reason: "Project snapshot materialization restores captured Scene pins"
    },
    %{
      table: :scene_pins,
      context: :projects,
      authority: :project_import,
      mapping_paths: ["lib/storyarn/projects/content/scenes/records/scene_pin_record.ex"],
      path: "lib/storyarn/projects/interchange/imports/commands/scene_import_persistence.ex",
      functions: [
        %{identity: "def import_pin/2", operations: [:insert]},
        %{identity: "def link_pin_flow_id/2", operations: [:update!]}
      ],
      reason: "validated Project import materializes and links captured Scene pins"
    },
    %{
      table: :scene_pins,
      context: :projects,
      authority: :project_recovery,
      mapping_paths: ["lib/storyarn/projects/content/scenes/records/scene_pin_record.ex"],
      path: "lib/storyarn/projects/versioning/execution/project_recovery.ex",
      functions: [%{identity: "defp maybe_update_scene_pin/2", operations: [:update_all]}],
      reason: "Project recovery remaps captured Scene pin references"
    },
    %{
      table: :scene_zones,
      context: :projects,
      authority: :project_scene_materialization,
      mapping_paths: ["lib/storyarn/projects/content/scenes/records/scene_zone_record.ex"],
      path: "lib/storyarn/projects/versioning/execution/builders/scene_builder.ex",
      functions: [%{identity: "defp insert_scene_snapshot_rows/4", operations: [:insert_all]}],
      reason: "Project snapshot materialization restores captured Scene zones"
    },
    %{
      table: :scene_zones,
      context: :projects,
      authority: :project_import,
      mapping_paths: ["lib/storyarn/projects/content/scenes/records/scene_zone_record.ex"],
      path: "lib/storyarn/projects/interchange/imports/commands/scene_import_persistence.ex",
      functions: [
        %{identity: "def import_zone/2", operations: [:insert]},
        %{identity: "def link_zone_target/3", operations: [:update!]}
      ],
      reason: "validated Project import materializes and links captured Scene zones"
    },
    %{
      table: :scene_zones,
      context: :projects,
      authority: :project_recovery,
      mapping_paths: ["lib/storyarn/projects/content/scenes/records/scene_zone_record.ex"],
      path: "lib/storyarn/projects/versioning/execution/project_recovery.ex",
      functions: [%{identity: "defp maybe_update_scene_zone/2", operations: [:update_all]}],
      reason: "Project recovery remaps captured Scene zone references"
    },
    %{
      table: :scenes,
      context: :projects,
      authority: :project_scene_materialization,
      mapping_paths: ["lib/storyarn/projects/content/scenes/records/scene_record.ex"],
      path: "lib/storyarn/projects/versioning/execution/builders/scene_builder.ex",
      functions: [%{identity: "defp instantiate_scene_snapshot/3", operations: [:insert_all]}],
      reason: "Project snapshot materialization restores the captured Scene root"
    },
    %{
      table: :scenes,
      context: :projects,
      authority: :project_import,
      mapping_paths: ["lib/storyarn/projects/content/scenes/records/scene_record.ex"],
      path: "lib/storyarn/projects/interchange/imports/commands/scene_import_persistence.ex",
      functions: [
        %{identity: "def import_scene/2", operations: [:insert]},
        %{identity: "def link_parent/2", operations: [:update!]}
      ],
      reason: "validated Project import replaces, materializes and links captured Scenes"
    },
    %{
      table: :scenes,
      context: :projects,
      authority: :project_scene_trash,
      mapping_paths: ["lib/storyarn/projects/content/scenes/records/scene_record.ex"],
      path: "lib/storyarn/projects/trash/execution/scene_project_trash.ex",
      functions: [
        %{identity: "def delete_subtree_in_transaction/1", operations: [:update]},
        %{identity: "def hard_delete/1", operations: [:delete]},
        %{identity: "def restore/1", operations: [:update]},
        %{identity: "defp restore_children/1", operations: [:update_all]},
        %{identity: "defp soft_delete_children/2", operations: [:update_all]}
      ],
      reason: "Project owns the closed-graph Scene trash, restore and purge lifecycle"
    },
    %{
      table: :scenes,
      context: :projects,
      authority: :project_recovery,
      mapping_paths: ["lib/storyarn/projects/content/scenes/records/scene_record.ex"],
      path: "lib/storyarn/projects/versioning/execution/project_recovery.ex",
      functions: [
        %{identity: "defp apply_tree_position/5", operations: [:update_all]},
        %{identity: "defp insert_snapshot_import_root_tombstone_for_schema/7", operations: [:insert_all]}
      ],
      reason: "Project recovery remaps the captured Scene hierarchy"
    },
    %{
      table: :sheet_avatars,
      context: :projects,
      authority: :project_sheet_materialization,
      mapping_paths: ["lib/storyarn/projects/content/sheets/records/sheet_avatar_record.ex"],
      path: "lib/storyarn/projects/versioning/execution/builders/sheet_builder.ex",
      functions: [%{identity: "defp insert_sheet_avatars/2", operations: [:insert_all]}],
      reason: "Project snapshot materialization restores captured Sheet avatars"
    },
    %{
      table: :sheet_avatars,
      context: :projects,
      authority: :project_import,
      mapping_paths: ["lib/storyarn/projects/content/sheets/records/sheet_avatar_record.ex"],
      path: "lib/storyarn/projects/interchange/imports/commands/sheet_import_persistence.ex",
      functions: [%{identity: "def add_avatar/3", operations: [:insert]}],
      reason: "validated Project import materializes captured Sheet avatars"
    },
    %{
      table: :sheets,
      context: :projects,
      authority: :project_sheet_materialization,
      mapping_paths: ["lib/storyarn/projects/content/sheets/records/sheet_record.ex"],
      path: "lib/storyarn/projects/versioning/execution/builders/sheet_builder.ex",
      functions: [%{identity: "defp instantiate_sheet_snapshot/3", operations: [:insert_all]}],
      reason: "Project snapshot materialization restores the captured Sheet root"
    },
    %{
      table: :sheets,
      context: :projects,
      authority: :project_import,
      mapping_paths: ["lib/storyarn/projects/content/sheets/records/sheet_record.ex"],
      path: "lib/storyarn/projects/interchange/imports/commands/sheet_import_persistence.ex",
      functions: [
        %{identity: "def import_sheet/2", operations: [:insert]},
        %{identity: "def link_import_parent/2", operations: [:update!]}
      ],
      reason: "validated Project import replaces, materializes and links captured Sheets"
    },
    %{
      table: :sheets,
      context: :projects,
      authority: :project_sheet_trash,
      mapping_paths: ["lib/storyarn/projects/content/sheets/records/sheet_record.ex"],
      path: "lib/storyarn/projects/trash/execution/sheet_project_trash.ex",
      functions: [
        %{identity: "def delete_subtree_in_transaction/1", operations: [:update!, :update_all]},
        %{identity: "def hard_delete/1", operations: [:delete]},
        %{identity: "def restore/1", operations: [:update]}
      ],
      reason: "Project owns the closed-graph Sheet trash, restore and purge lifecycle"
    },
    %{
      table: :sheets,
      context: :projects,
      authority: :project_sheet_materialization,
      mapping_paths: ["lib/storyarn/projects/content/sheets/records/sheet_record.ex"],
      path: "lib/storyarn/projects/versioning/execution/builders/sheet_builder.ex",
      functions: [
        %{identity: "defp remap_hidden_inherited_block_ids/6", operations: [:update_all]}
      ],
      reason: "Project snapshot materialization remaps captured Sheet inheritance metadata"
    },
    %{
      table: :sheets,
      context: :projects,
      authority: :project_recovery,
      mapping_paths: ["lib/storyarn/projects/content/sheets/records/sheet_record.ex"],
      path: "lib/storyarn/projects/versioning/execution/project_recovery.ex",
      functions: [
        %{identity: "defp apply_tree_position/5", operations: [:update_all]},
        %{identity: "defp insert_snapshot_import_root_tombstone_for_schema/7", operations: [:insert_all]},
        %{identity: "defp remap_hidden_inherited_block_ids/4", operations: [:update_all]}
      ],
      reason: "Project recovery remaps captured Sheet hierarchy and inheritance metadata"
    },
    %{
      table: :table_columns,
      context: :projects,
      authority: :project_sheet_materialization,
      mapping_paths: ["lib/storyarn/projects/content/sheets/records/table_column_record.ex"],
      path: "lib/storyarn/projects/versioning/execution/builders/sheet_builder.ex",
      functions: [%{identity: "defp insert_table_data/4", operations: [:insert_all]}],
      reason: "Project snapshot materialization restores captured Sheet table columns"
    },
    %{
      table: :table_columns,
      context: :projects,
      authority: :project_import,
      mapping_paths: ["lib/storyarn/projects/content/sheets/records/table_column_record.ex"],
      path: "lib/storyarn/projects/interchange/imports/commands/sheet_import_persistence.ex",
      functions: [%{identity: "def import_column/2", operations: [:insert]}],
      reason: "validated Project import materializes captured table columns"
    },
    %{
      table: :table_rows,
      context: :projects,
      authority: :project_sheet_materialization,
      mapping_paths: ["lib/storyarn/projects/content/sheets/records/table_row_record.ex"],
      path: "lib/storyarn/projects/versioning/execution/builders/sheet_builder.ex",
      functions: [%{identity: "defp insert_table_data/4", operations: [:insert_all]}],
      reason: "Project snapshot materialization restores captured Sheet table rows"
    },
    %{
      table: :table_rows,
      context: :projects,
      authority: :project_import,
      mapping_paths: ["lib/storyarn/projects/content/sheets/records/table_row_record.ex"],
      path: "lib/storyarn/projects/interchange/imports/commands/sheet_import_persistence.ex",
      functions: [%{identity: "def import_row/2", operations: [:insert]}],
      reason: "validated Project import materializes captured table rows"
    },
    %{
      table: :table_rows,
      context: :projects,
      authority: :project_recovery,
      mapping_paths: ["lib/storyarn/projects/references/records/table_row_record.ex"],
      path: "lib/storyarn/projects/references/commands/materialized_formula_binding_rewriter.ex",
      functions: [%{identity: "defp rewrite_materialized_formula_row/2", operations: [:update]}],
      reason: "Project recovery rewrites only formula cells whose portable variable namespace changed"
    }
  ],
  scanner_false_positives: []
}

# ENG-108 seals the four aggregate identity tables touched by owner transfer.
# These inventories describe direct writes from `lib/`; database cascades are
# deliberately outside the source ratchet. Every declared writer must be tied
# statically to the owned schema and detected by the analyzer; when a dynamic
# writer hides that target, expose it at the writer boundary instead of adding
# an opaque exemption. `scanner_false_positives` keeps conservative candidates
# visible without granting them write authority.
aggregate_identity_persistence_ownership = %{
  projects: %{
    table: "projects",
    ownership_model: :projects_owned_aggregate_identity,
    ordinary_owner: :projects,
    writers: [
      %{
        context: :projects,
        authority: :ownership_transfer,
        path: "lib/storyarn/projects/access/commands/transfer_ownership.ex",
        functions: [
          %{identity: "defp change_project_owner/2", operations: [:update], detected_by_analyzer: true}
        ],
        reason: "the serialized Project transfer changes the canonical owner_id"
      },
      %{
        context: :projects,
        authority: :ordinary_lifecycle,
        path: "lib/storyarn/projects/lifecycle/commands/project_commands.ex",
        functions: [
          %{identity: "def touch_project/2", operations: [:update_all], detected_by_analyzer: true},
          %{identity: "defp delete_locked_project/1", operations: [:delete], detected_by_analyzer: true},
          %{identity: "defp insert_project/2", operations: [:insert], detected_by_analyzer: true},
          %{identity: "defp persist_project_update/2", operations: [:update], detected_by_analyzer: true},
          %{identity: "defp soft_delete_locked_project/2", operations: [:update], detected_by_analyzer: true}
        ],
        reason: "Projects owns create, update, activity, trash and hard-delete lifecycle"
      },
      %{
        context: :projects,
        authority: :template_instantiation,
        path: "lib/storyarn/projects/templates/execution/installation.ex",
        functions: [
          %{identity: "defp mark_template_origin/2", operations: [:update], detected_by_analyzer: true}
        ],
        reason: "template installation records the version that materialized the new Project"
      },
      %{
        context: :projects,
        authority: :project_reconstitution,
        path: "lib/storyarn/projects/versioning/execution/project_recovery.ex",
        functions: [
          %{identity: "defp create_project/5", operations: [:insert], detected_by_analyzer: true}
        ],
        reason: "validated Project recovery materializes the captured Project identity"
      },
      %{
        context: :projects,
        authority: :exact_snapshot_restore,
        path: "lib/storyarn/projects/versioning/execution/project_snapshot_restore_executor.ex",
        functions: [
          %{identity: "defp restore_project_fields/2", operations: [:update], detected_by_analyzer: true}
        ],
        reason: "exact restore replaces the snapshot-owned Project fields"
      }
    ],
    scanner_false_positives: [
      %{
        path: "lib/storyarn/projects/templates/execution/publication_runner.ex",
        function: "defp insert_publication_and_enqueue_locked/1",
        operation: :insert,
        source_sha256: "e7ddb193c9a9f9adba9bddd478424bccbdb9c1ada6a66fa6e85e01d4eb499807",
        reason: "writes project_template_publications after reading a Project"
      },
      %{
        path: "lib/storyarn/projects/versioning/commands/workspace_snapshot_imports.ex",
        function: "defp clear_reservation/1",
        operation: :update,
        source_sha256: "748417dbb47be04e04bec4759b989efe534b9253ca1e6a09aaedff2ac6016476",
        reason: "updates a workspace_snapshot_import after reading Project identity"
      }
    ],
    analyzer: persistence_write_analyzer
  },
  project_memberships: %{
    table: "project_memberships",
    ownership_model: :projects_owned_membership,
    ordinary_owner: :projects,
    writers: [
      %{
        context: :projects,
        authority: :ordinary_membership_lifecycle,
        path: "lib/storyarn/projects/access/commands/membership_operations.ex",
        functions: [
          %{identity: "def create_membership/4", operations: [:insert], detected_by_analyzer: true},
          %{identity: "def remove_member/1", operations: [:delete], detected_by_analyzer: true},
          %{identity: "def update_member_role/3", operations: [:update], detected_by_analyzer: true}
        ],
        reason: "the Projects membership capability owns ordinary member creation, role changes and removal"
      },
      %{
        context: :projects,
        authority: :ownership_transfer,
        path: "lib/storyarn/projects/access/commands/transfer_ownership.ex",
        functions: [
          %{identity: "defp change_role/2", operations: [:update], detected_by_analyzer: true}
        ],
        reason: "the serialized Project transfer atomically demotes and promotes owner memberships"
      },
      %{
        context: :projects,
        authority: :aggregate_creation,
        path: "lib/storyarn/projects/lifecycle/commands/project_commands.ex",
        functions: [
          %{identity: "defp create_owner_membership/2", operations: [:insert], detected_by_analyzer: true}
        ],
        reason: "Project creation creates its matching owner membership in the same transaction"
      },
      %{
        context: :projects,
        authority: :project_reconstitution,
        path: "lib/storyarn/projects/versioning/execution/project_recovery.ex",
        functions: [
          %{identity: "defp create_owner_membership/2", operations: [:insert], detected_by_analyzer: true}
        ],
        reason: "Project recovery creates the matching owner membership in its materialization transaction"
      }
    ],
    scanner_false_positives: [],
    analyzer: persistence_write_analyzer
  },
  workspaces: %{
    table: "workspaces",
    ownership_model: :workspaces_owned_aggregate_identity,
    ordinary_owner: :workspaces,
    writers: [
      %{
        context: :workspaces,
        authority: :banner_lifecycle,
        path: "lib/storyarn/workspaces/banner/commands/change.ex",
        functions: [
          %{identity: "defp update_banner_url/2", operations: [:update], detected_by_analyzer: true}
        ],
        reason: "Workspace banner lifecycle owns the banner_url field"
      },
      %{
        context: :workspaces,
        authority: :aggregate_creation,
        path: "lib/storyarn/workspaces/lifecycle/commands/create_workspace.ex",
        functions: [
          %{identity: "defp insert_workspace/2", operations: [:insert], detected_by_analyzer: true}
        ],
        reason: "Workspace lifecycle owns aggregate creation"
      },
      %{
        context: :workspaces,
        authority: :aggregate_hard_delete,
        path: "lib/storyarn/workspaces/lifecycle/commands/delete_workspace.ex",
        functions: [
          %{identity: "def delete/2", operations: [:delete], detected_by_analyzer: true}
        ],
        reason: "Workspace lifecycle owns coordinated hard deletion"
      },
      %{
        context: :workspaces,
        authority: :ordinary_lifecycle,
        path: "lib/storyarn/workspaces/lifecycle/commands/update_workspace.ex",
        functions: [
          %{identity: "def update/3", operations: [:update], detected_by_analyzer: true}
        ],
        reason: "Workspace lifecycle owns ordinary metadata updates"
      },
      %{
        context: :workspaces,
        authority: :ownership_transfer,
        path: "lib/storyarn/workspaces/memberships/commands/transfer_ownership.ex",
        functions: [
          %{identity: "defp change_workspace_owner/2", operations: [:update], detected_by_analyzer: true}
        ],
        reason: "the serialized Workspace transfer changes the canonical owner_id"
      }
    ],
    scanner_false_positives: [],
    analyzer: persistence_write_analyzer
  },
  workspace_memberships: %{
    table: "workspace_memberships",
    ownership_model: :workspaces_owned_membership,
    ordinary_owner: :workspaces,
    writers: [
      %{
        context: :workspaces,
        authority: :aggregate_creation,
        path: "lib/storyarn/workspaces/lifecycle/commands/create_workspace.ex",
        functions: [
          %{identity: "defp create_owner_membership/2", operations: [:insert], detected_by_analyzer: true}
        ],
        reason: "Workspace creation creates its matching owner membership in the same transaction"
      },
      %{
        context: :workspaces,
        authority: :ordinary_membership_lifecycle,
        path: "lib/storyarn/workspaces/memberships/commands/change_member_role.ex",
        functions: [
          %{identity: "def change/4", operations: [:update], detected_by_analyzer: true}
        ],
        reason: "Workspace memberships owns ordinary role changes"
      },
      %{
        context: :workspaces,
        authority: :ordinary_membership_lifecycle,
        path: "lib/storyarn/workspaces/memberships/commands/create_membership.ex",
        functions: [
          %{identity: "def create/3", operations: [:insert], detected_by_analyzer: true}
        ],
        reason: "Workspace memberships owns ordinary member creation"
      },
      %{
        context: :workspaces,
        authority: :ordinary_membership_lifecycle,
        path: "lib/storyarn/workspaces/memberships/commands/remove_member.ex",
        functions: [
          %{identity: "def remove/3", operations: [:delete], detected_by_analyzer: true}
        ],
        reason: "Workspace memberships owns ordinary member removal"
      },
      %{
        context: :workspaces,
        authority: :ownership_transfer,
        path: "lib/storyarn/workspaces/memberships/commands/transfer_ownership.ex",
        functions: [
          %{identity: "defp change_role/2", operations: [:update], detected_by_analyzer: true}
        ],
        reason: "the serialized Workspace transfer atomically demotes and promotes owner memberships"
      }
    ],
    scanner_false_positives: [],
    analyzer: persistence_write_analyzer
  }
}

# The rule is intentionally implemented inside each consumer that owns its read
# model. This contract records the conservatively discovered copies and makes
# the duplicated semantic explicit without centralizing contexts on one shared
# business helper. Its source-level discovery limits are declared below.
canonical_owner_membership_invariant = %{
  invariant: "owner_id must identify the user on exactly one role=owner membership for the same aggregate",
  implementations: [
    %{
      aggregates: [:project, :workspace],
      context: :ai,
      path: "lib/storyarn/ai/governance/execution/authorization.ex",
      functions: [
        "defp list_project_owner_memberships/1",
        "defp list_workspace_owner_memberships/1",
        "defp owner_memberships/3",
        "defp validate_owner_membership/4"
      ],
      mode: :consumer_owned_projection
    },
    %{
      aggregates: [:workspace],
      context: :ai,
      path: "lib/storyarn/ai/governance/commands/policies.ex",
      functions: ["defp lock_and_authorize_owner/2"],
      mode: :consumer_owned_projection
    },
    %{
      aggregates: [:project],
      context: :flows,
      path: "lib/storyarn/flows/references/commands/owner_authority.ex",
      functions: ["defp authorize_canonical_owner/3", "defp lock_owner_memberships/1"],
      mode: :consumer_owned_projection
    },
    %{
      aggregates: [:project],
      context: :localization,
      path: "lib/storyarn/localization/project_access/commands/owner_authority.ex",
      functions: ["defp authorize_canonical_owner/3", "defp lock_owner_memberships/1"],
      mode: :consumer_owned_projection
    },
    %{
      aggregates: [:project],
      context: :projects,
      path: "lib/storyarn/projects/access/rules/ownership_invariant.ex",
      functions: ["def owner/2"],
      mode: :owner_context_rule
    },
    %{
      aggregates: [:workspace],
      context: :workspaces,
      path: "lib/storyarn/workspaces/lifecycle/commands/delete_workspace.ex",
      functions: ["defp lock_and_authorize_owner/2"],
      mode: :owner_context_command
    },
    %{
      aggregates: [:workspace],
      context: :workspaces,
      path: "lib/storyarn/workspaces/lifecycle/commands/update_workspace.ex",
      functions: ["defp lock_and_authorize_owner/2"],
      mode: :owner_context_command
    },
    %{
      aggregates: [:workspace],
      context: :workspaces,
      path: "lib/storyarn/workspaces/memberships/rules/ownership_invariant.ex",
      functions: ["def owner/2"],
      mode: :owner_context_rule
    }
  ],
  discovery: %{
    root: "lib/storyarn",
    required_literals: [":ownership_invariant_violation", "owner_id"],
    owner_role_patterns: ["role == \"owner\"", "role: \"owner\""],
    limits: [
      "candidate discovery is conservative source matching and can miss semantically equivalent alternative syntax",
      "a second implementation added inside an already declared source file is not discovered automatically"
    ],
    reviewed_non_implementations: [
      %{
        path: "lib/storyarn/projects/access/memberships.ex",
        reason: "loads owner rows but delegates the semantic decision to Projects.Access.Rules.OwnershipInvariant"
      }
    ]
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
  commercial: [
    "lib/storyarn/commercial.ex",
    "lib/storyarn/commercial/"
  ],
  platform: [
    "lib/storyarn/platform.ex",
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
    "lib/mix/tasks/storyarn.ownership.audit.ex",
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
  "access" => ~w(adapters commands delivery queries rules),
  "assets" => ~w(adapters commands execution projections queries rules),
  "overview" => ~w(execution queries rules),
  "trash" => ~w(execution),
  "references" => ~w(adapters commands execution projections queries records reference_data rules),
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

# Commercial is an independent business context. Its root facade may compose
# the stable Billing, Entitlements and ProjectStorageReservations facets, but it
# must not reach directly into effectful or passive implementation roles.
commercial_root_private_targets = [
  "commands/",
  "entities/",
  "execution/",
  "projections/",
  "queries/storage_cleanup_ownership_receipt_record.ex",
  "queries/subscriptions.ex",
  "reference_data/",
  "rules/",
  "subscription_crud.ex"
]

commercial_root_facade_path_denials =
  for private_target <- commercial_root_private_targets do
    %{
      source_root: "lib/storyarn/commercial.ex",
      target_root: "lib/storyarn/commercial/#{private_target}",
      kinds: ["runtime", "export", "compile"],
      reason: "The Storyarn.Commercial facade composes stable capability facets rather than private implementation roles"
    }
  end

commercial_passive_roles = ["entities", "projections", "queries", "reference_data", "rules"]

commercial_effectful_targets = [
  "lib/storyarn/commercial.ex",
  "lib/storyarn/commercial/billing.ex",
  "lib/storyarn/commercial/project_storage_reservations.ex",
  "lib/storyarn/commercial/subscription_crud.ex",
  "lib/storyarn/commercial/commands/",
  "lib/storyarn/commercial/execution/"
]

commercial_passive_effect_denials =
  for source_role <- commercial_passive_roles,
      target_root <- commercial_effectful_targets do
    %{
      source_root: "lib/storyarn/commercial/#{source_role}/",
      target_root: target_root,
      kinds: ["runtime", "export", "compile"],
      reason: "Commercial passive roles cannot invoke effectful workflows or mixed writer facades"
    }
  end

commercial_passive_role_dependency_denials =
  for {source_role, target_role} <- [
        {"rules", "queries"},
        {"projections", "queries"},
        {"projections", "rules"},
        {"reference_data", "queries"},
        {"reference_data", "rules"},
        {"entities", "queries"}
      ] do
    %{
      source_root: "lib/storyarn/commercial/#{source_role}/",
      target_root: "lib/storyarn/commercial/#{target_role}/",
      kinds: ["runtime", "export", "compile"],
      reason: "Commercial passive roles cannot become hidden readers or policy orchestrators"
    }
  end

commercial_rule_persistence_denial = %{
  source_root: "lib/storyarn/commercial/rules/",
  target_root: "lib/storyarn/repo.ex",
  kinds: ["runtime", "export", "compile"],
  reason: "Commercial rules are deterministic policy and cannot query or orchestrate persistence"
}

# Platform is one control-plane context split into cohesive capabilities. A
# capability may consume another capability's facade, but its operational code,
# data projections, entities, and rules remain private to their owner.
# Reaction contracts and analytics adapters stay outside this private set: the
# former are stable event contracts and the latter are technical infrastructure.
platform_capability_private_targets = %{
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

# The root facade composes capability facades rather than their private roles.
platform_root_facade_path_denials =
  for {capability, private_targets} <- platform_capability_private_targets,
      private_target <- private_targets do
    %{
      source_root: "lib/storyarn/platform.ex",
      target_root: "lib/storyarn/platform/#{capability}/#{private_target}",
      kinds: ["runtime", "export", "compile"],
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

# These modules are deliberately more powerful than an ordinary context facade:
# they can materialize, replace, repair or reconcile state owned by several
# bounded contexts, or expose a narrower transaction/lock authority. Keep their
# caller set exact so a new import, recovery, restore, repair or pre-locked path
# cannot bypass the reviewed coordinator accidentally.
# Module-scoped entries also fail closed when a module is passed as a runtime
# dependency; function-scoped entries leave unrelated capability functions
# available to their context. Runtime-injected modules must expose their exact
# privileged functions through explicit callbacks anchored to the reviewed
# default module; opaque field or ambiguously rebound module receivers are not
# accepted by the ratchet.
privileged_entrypoints = [
  %{
    module: "Storyarn.Projects.Imports.Materializer",
    path: "lib/storyarn/projects/interchange/imports/execution/materializer.ex",
    functions: :all,
    allowed_callers: [
      "lib/storyarn/projects/reconstitution/project_reconstitution.ex"
    ],
    reason: "the import materializer is internal to the exact Project reconstitution boundary"
  },
  %{
    module: "Storyarn.Projects.FlowImportPersistence",
    path: "lib/storyarn/projects/interchange/imports/commands/flow_import_persistence.ex",
    functions: :all,
    allowed_callers: [
      "lib/storyarn/projects/interchange/imports/execution/materializer.ex"
    ],
    reason: "only the validated Project import materializer may write imported Flow state"
  },
  %{
    module: "Storyarn.Projects.SheetImportPersistence",
    path: "lib/storyarn/projects/interchange/imports/commands/sheet_import_persistence.ex",
    functions: :all,
    allowed_callers: [
      "lib/storyarn/projects/interchange/imports/execution/materializer.ex"
    ],
    reason: "only the validated Project import materializer may write imported Sheet state"
  },
  %{
    module: "Storyarn.Projects.SceneImportPersistence",
    path: "lib/storyarn/projects/interchange/imports/commands/scene_import_persistence.ex",
    functions: :all,
    allowed_callers: [
      "lib/storyarn/projects/interchange/imports/execution/materializer.ex"
    ],
    reason: "only the validated Project import materializer may write imported Scene state"
  },
  %{
    module: "Storyarn.Projects.LocalizationReconstitution",
    path: "lib/storyarn/projects/interchange/imports/commands/localization_reconstitution.ex",
    functions: :all,
    allowed_callers: [
      "lib/storyarn/projects/interchange/imports/execution/materializer.ex"
    ],
    reason: "only the validated Project import materializer may write imported Localization state"
  },
  %{
    module: "Storyarn.Projects.Versioning.Builders.FlowBuilder",
    path: "lib/storyarn/projects/versioning/execution/builders/flow_builder.ex",
    functions: [build_snapshot: 1, build_capture_snapshot: 1],
    allowed_callers: [
      "lib/storyarn/projects/versioning/execution/builders/project_snapshot_builder.ex"
    ],
    reason: "Flow graph capture belongs only to the reviewed whole-Project snapshot builder"
  },
  %{
    module: "Storyarn.Projects.Versioning.Builders.FlowBuilder",
    path: "lib/storyarn/projects/versioning/execution/builders/flow_builder.ex",
    functions: [
      validate_portable_snapshot: 1,
      instantiate_snapshot: 2,
      instantiate_snapshot: 3,
      validate_materialized_reference_cycles: 1
    ],
    allowed_callers: [
      "lib/storyarn/projects/versioning/execution/project_recovery.ex"
    ],
    reason: "Flow graph validation and materialization belong only to whole-Project recovery"
  },
  %{
    module: "Storyarn.Projects.Versioning.Builders.SheetBuilder",
    path: "lib/storyarn/projects/versioning/execution/builders/sheet_builder.ex",
    functions: [build_snapshot: 1, build_capture_snapshot: 1],
    allowed_callers: [
      "lib/storyarn/projects/versioning/execution/builders/project_snapshot_builder.ex"
    ],
    reason: "Sheet graph capture belongs only to the reviewed whole-Project snapshot builder"
  },
  %{
    module: "Storyarn.Projects.Versioning.Builders.SheetBuilder",
    path: "lib/storyarn/projects/versioning/execution/builders/sheet_builder.ex",
    functions: [validate_portable_snapshot: 1, instantiate_snapshot: 2, instantiate_snapshot: 3],
    allowed_callers: [
      "lib/storyarn/projects/versioning/execution/project_recovery.ex"
    ],
    reason: "Sheet graph validation and materialization belong only to whole-Project recovery"
  },
  %{
    module: "Storyarn.Projects.Versioning.Builders.SceneBuilder",
    path: "lib/storyarn/projects/versioning/execution/builders/scene_builder.ex",
    functions: [build_snapshot: 1, build_capture_snapshot: 1],
    allowed_callers: [
      "lib/storyarn/projects/versioning/execution/builders/project_snapshot_builder.ex"
    ],
    reason: "Scene graph capture belongs only to the reviewed whole-Project snapshot builder"
  },
  %{
    module: "Storyarn.Projects.Versioning.Builders.SceneBuilder",
    path: "lib/storyarn/projects/versioning/execution/builders/scene_builder.ex",
    functions: [validate_portable_snapshot: 1, instantiate_snapshot: 2, instantiate_snapshot: 3],
    allowed_callers: [
      "lib/storyarn/projects/versioning/execution/project_recovery.ex"
    ],
    reason: "Scene graph validation and materialization belong only to whole-Project recovery"
  },
  %{
    module: "Storyarn.Projects.References.EntityReferenceExtraction",
    path: "lib/storyarn/projects/references/rules/entity_reference_extraction.ex",
    functions: [extract_block_value_references: 2],
    allowed_callers: [
      "lib/storyarn/projects/references/commands/entity_reference_projection.ex",
      "lib/storyarn/projects/references/references.ex",
      "lib/storyarn/projects/versioning/rules/snapshot_references/flow_scanner.ex",
      "lib/storyarn/projects/versioning/rules/snapshot_references/sheet_scanner.ex"
    ],
    reason:
      "only the Project References facade, reference writers and pure portable snapshot scanners consume strict block reference extraction"
  },
  %{
    module: "Storyarn.Projects.Versioning.SnapshotReferences",
    path: "lib/storyarn/projects/versioning/rules/snapshot_references/snapshot_references.ex",
    functions: [validate: 4],
    allowed_callers: [
      "lib/storyarn/projects/versioning/execution/project_recovery.ex"
    ],
    reason: "portable Project recovery is the only production entry to snapshot reference validation"
  },
  %{
    module: "Storyarn.Projects.Versioning.SnapshotReferences.SheetScanner",
    path: "lib/storyarn/projects/versioning/rules/snapshot_references/sheet_scanner.ex",
    functions: [scan: 1],
    allowed_callers: [
      "lib/storyarn/projects/versioning/rules/snapshot_references/snapshot_references.ex"
    ],
    reason: "the pure snapshot reference coordinator owns Sheet scanner ordering"
  },
  %{
    module: "Storyarn.Projects.Versioning.SnapshotReferences.FlowScanner",
    path: "lib/storyarn/projects/versioning/rules/snapshot_references/flow_scanner.ex",
    functions: [scan: 1],
    allowed_callers: [
      "lib/storyarn/projects/versioning/rules/snapshot_references/snapshot_references.ex"
    ],
    reason: "the pure snapshot reference coordinator owns Flow scanner ordering"
  },
  %{
    module: "Storyarn.Projects.Versioning.SnapshotReferences.SceneScanner",
    path: "lib/storyarn/projects/versioning/rules/snapshot_references/scene_scanner.ex",
    functions: [scan: 1],
    allowed_callers: [
      "lib/storyarn/projects/versioning/rules/snapshot_references/snapshot_references.ex"
    ],
    reason: "the pure snapshot reference coordinator owns Scene scanner ordering"
  },
  %{
    module: "Storyarn.Projects.Versioning.MaterializationHelpers",
    path: "lib/storyarn/projects/versioning/execution/materialization_helpers.ex",
    functions: [insert_all: 3, insert_one_returning_id: 3],
    allowed_callers: [
      "lib/storyarn/projects/versioning/execution/builders/scene_builder.ex",
      "lib/storyarn/projects/versioning/execution/builders/sheet_builder.ex",
      "lib/storyarn/projects/versioning/execution/project_recovery.ex"
    ],
    reason:
      "only reviewed Project materializers may invoke transparent insert delegates whose call sites retain proven Repo and attributable schema targets"
  },
  %{
    module: "Storyarn.Scenes.Versioning.Commands.MaterializationHelpers",
    path: "lib/storyarn/scenes/versioning/commands/materialization_helpers.ex",
    functions: [insert_all: 3],
    allowed_callers: [
      "lib/storyarn/scenes/versioning/execution/scene_snapshot.ex"
    ],
    reason: "only exact Scene snapshot restore may invoke its transparent insert delegates"
  },
  %{
    module: "Storyarn.Sheets.Versioning.Commands.MaterializationHelpers",
    path: "lib/storyarn/sheets/versioning/commands/materialization_helpers.ex",
    functions: [insert_all: 3, insert_one_returning_id: 3],
    allowed_callers: [
      "lib/storyarn/sheets/versioning/execution/sheet_snapshot.ex"
    ],
    reason: "only exact Sheet snapshot restore may invoke its transparent insert delegates"
  },
  %{
    module: "Storyarn.Projects.Versioning.ProjectRecovery",
    path: "lib/storyarn/projects/versioning/execution/project_recovery.ex",
    functions: [
      materialize_template: 3,
      materialize_template: 4,
      validate_snapshot_import: 1,
      materialize_snapshot_import: 3,
      materialize_snapshot_import: 4
    ],
    allowed_callers: [
      "lib/storyarn/projects/reconstitution/project_reconstitution.ex"
    ],
    reason: "whole-Project import and template materialization are internal to ProjectReconstitution"
  },
  %{
    module: "Storyarn.Projects.Versioning.ProjectRecovery",
    path: "lib/storyarn/projects/versioning/execution/project_recovery.ex",
    functions: [
      lock_materializable_localization_actors: 1,
      lock_materializable_localization_actors: 2,
      materialize_into_project: 4,
      materialize_into_project: 5
    ],
    allowed_callers: [
      "lib/storyarn/projects/versioning/execution/project_snapshot_restore_executor.ex"
    ],
    reason: "exact in-place Project materialization is internal to the persisted restore executor"
  },
  %{
    module: "Storyarn.Projects.Versioning.ProjectSnapshotRestoreExecutor",
    path: "lib/storyarn/projects/versioning/execution/project_snapshot_restore_executor.ex",
    functions: :all,
    allowed_callers: [
      "lib/storyarn/projects/reconstitution/project_reconstitution.ex"
    ],
    reason: "the restore executor is internal to the exact Project reconstitution boundary"
  },
  %{
    module: "Storyarn.Projects.ProjectReconstitution",
    path: "lib/storyarn/projects/reconstitution/project_reconstitution.ex",
    functions: [preview_import: 2],
    allowed_callers: [
      "lib/storyarn/projects/interchange/imports/queries/preview.ex"
    ],
    reason: "only the validated import preview may request a read-only reconstitution preview"
  },
  %{
    module: "Storyarn.Projects.ProjectReconstitution",
    path: "lib/storyarn/projects/reconstitution/project_reconstitution.ex",
    functions: [execute_import: 2, execute_import: 3],
    allowed_callers: [
      "lib/storyarn/projects/interchange/imports/execution/import_lifecycle.ex"
    ],
    reason: "only the immediate import lifecycle may enter the transaction-owning import materializer"
  },
  %{
    module: "Storyarn.Projects.ProjectReconstitution",
    path: "lib/storyarn/projects/reconstitution/project_reconstitution.ex",
    functions: [
      materialize_locked_import_in_transaction: 2,
      materialize_locked_import_in_transaction: 3
    ],
    allowed_callers: [
      "lib/storyarn/projects/interchange/imports/execution/execution.ex"
    ],
    reason: "only the durable import execution lifecycle may materialize under its existing locks"
  },
  %{
    module: "Storyarn.Projects.ProjectReconstitution",
    path: "lib/storyarn/projects/reconstitution/project_reconstitution.ex",
    functions: [materialize_template: 3, materialize_template: 4],
    allowed_callers: [
      "lib/storyarn/projects/templates/execution/audit.ex",
      "lib/storyarn/projects/templates/execution/installation.ex",
      "lib/storyarn/projects/templates/execution/portable_import.ex"
    ],
    reason: "only the reviewed template workflows may materialize a portable Project graph"
  },
  %{
    module: "Storyarn.Projects.ProjectReconstitution",
    path: "lib/storyarn/projects/reconstitution/project_reconstitution.ex",
    functions: [
      validate_snapshot_import: 1,
      materialize_snapshot_import: 3,
      materialize_snapshot_import: 4
    ],
    allowed_callers: [
      "lib/storyarn/projects/versioning/commands/workspace_snapshot_imports.ex"
    ],
    reason: "only the verified workspace snapshot-import lifecycle may validate and materialize its exact Project archive"
  },
  %{
    module: "Storyarn.Projects.ProjectReconstitution",
    path: "lib/storyarn/projects/reconstitution/project_reconstitution.ex",
    functions: [execute_snapshot_restore: 2],
    allowed_callers: [
      "lib/storyarn/projects/versioning/commands/project_snapshot_restore_lifecycle.ex"
    ],
    reason: "only the persisted restore lifecycle may execute an exact in-place Project restore"
  },
  %{
    module: "Storyarn.Projects.ProjectReconstitution",
    path: "lib/storyarn/projects/reconstitution/project_reconstitution.ex",
    functions: [
      settle_snapshot_restore_reservation: 1,
      settle_snapshot_restore_reservation: 2
    ],
    allowed_callers: [
      "lib/storyarn/projects/versioning/commands/project_snapshot_restore_lifecycle.ex"
    ],
    reason: "only the persisted restore lifecycle may settle storage ownership after restore execution"
  },
  %{
    module: "Storyarn.Sheets.Editor.Adapters.Flows.DialogueAudio",
    path: "lib/storyarn/sheets/editor/adapters/flows/dialogue_audio.ex",
    functions: [assign: 4],
    allowed_callers: [
      "lib/storyarn/sheets/editor/editor.ex"
    ],
    reason: "only the Sheet audio use case may enter Sheets' narrow Flow command adapter"
  },
  %{
    module: "Storyarn.Flows",
    path: "lib/storyarn/flows.ex",
    functions: [assign_dialogue_audio: 4],
    allowed_callers: [
      "lib/storyarn/sheets/editor/adapters/flows/dialogue_audio.ex"
    ],
    reason: "only the reviewed Sheet adapter may request the Flow-owned audio mutation"
  },
  %{
    module: "Storyarn.Flows.Editor",
    path: "lib/storyarn/flows/editor/editor.ex",
    functions: [assign_dialogue_audio: 4],
    allowed_callers: [
      "lib/storyarn/flows.ex"
    ],
    reason: "the dialogue-audio command remains behind the public Flows facade"
  },
  %{
    module: "Storyarn.Flows.Editor.Commands.DialogueAudio",
    path: "lib/storyarn/flows/editor/commands/dialogue_audio.ex",
    functions: [assign: 4],
    allowed_callers: [
      "lib/storyarn/flows/editor/editor.ex"
    ],
    reason: "the Flows Editor capability is the only route to the transaction-owning dialogue-audio writer"
  },
  %{
    module: "Storyarn.Projects.References.Adapters.Flows.StaleVariableReferenceRepair",
    path: "lib/storyarn/projects/references/adapters/flows/stale_variable_reference_repair.ex",
    functions: [repair_project: 2],
    allowed_callers: [
      "lib/storyarn/projects/references/execution/variable_usage.ex"
    ],
    reason: "only the Projects stale-variable use case may enter its narrow Flow repair adapter"
  },
  %{
    module: "Storyarn.Flows",
    path: "lib/storyarn/flows.ex",
    functions: [repair_stale_variable_references: 2],
    allowed_callers: [
      "lib/storyarn/projects/references/adapters/flows/stale_variable_reference_repair.ex"
    ],
    reason: "only the reviewed Projects adapter may request Flow-owned stale-variable repair"
  },
  %{
    module: "Storyarn.Flows.References",
    path: "lib/storyarn/flows/references/references.ex",
    functions: [repair_stale_variable_references: 2],
    allowed_callers: [
      "lib/storyarn/flows.ex"
    ],
    reason: "the stale-variable repair command remains behind the public Flows facade"
  },
  %{
    module: "Storyarn.Flows.References.Commands.StaleVariableReferenceRepair",
    path: "lib/storyarn/flows/references/commands/stale_variable_reference_repair.ex",
    functions: [repair_project: 2],
    allowed_callers: [
      "lib/storyarn/flows/references/references.ex"
    ],
    reason: "the Flows References capability is the only route to its transaction-owning repair writer"
  },
  %{
    module: "Storyarn.Flows.Versioning.Adapters.Projects.AssetRegistration",
    path: "lib/storyarn/flows/versioning/adapters/projects/asset_registration.ex",
    functions: [register_materialized_asset: 3],
    allowed_callers: [
      "lib/storyarn/flows/versioning/execution/asset_catalog.ex"
    ],
    reason: "only Flow snapshot materialization may enter Flow's narrow Projects asset adapter"
  },
  %{
    module: "Storyarn.Scenes.Assets.Adapters.Projects.AssetRegistration",
    path: "lib/storyarn/scenes/assets/adapters/projects/asset_registration.ex",
    functions: [register_uploaded_asset: 4, register_materialized_asset: 3, link_asset_variant: 3],
    allowed_callers: [
      "lib/storyarn/scenes/assets/commands/assets.ex"
    ],
    reason: "only the Scene asset use case may enter Scene's narrow Projects asset adapter"
  },
  %{
    module: "Storyarn.Sheets.Assets.Adapters.Projects.AssetRegistration",
    path: "lib/storyarn/sheets/assets/adapters/projects/asset_registration.ex",
    functions: [register_uploaded_asset: 4, register_materialized_asset: 3, link_asset_variant: 3],
    allowed_callers: [
      "lib/storyarn/sheets/assets/commands/assets.ex"
    ],
    reason: "only the Sheet asset use case may enter Sheet's narrow Projects asset adapter"
  },
  %{
    module: "Storyarn.Projects",
    path: "lib/storyarn/projects.ex",
    functions: [register_uploaded_asset: 4],
    allowed_callers: [
      "lib/storyarn/scenes/assets/adapters/projects/asset_registration.ex",
      "lib/storyarn/sheets/assets/adapters/projects/asset_registration.ex"
    ],
    reason: "only the reviewed Sheet and Scene upload adapters may request Projects-owned asset registration"
  },
  %{
    module: "Storyarn.Projects",
    path: "lib/storyarn/projects.ex",
    functions: [register_materialized_asset: 3],
    allowed_callers: [
      "lib/storyarn/flows/versioning/adapters/projects/asset_registration.ex",
      "lib/storyarn/scenes/assets/adapters/projects/asset_registration.ex",
      "lib/storyarn/sheets/assets/adapters/projects/asset_registration.ex"
    ],
    reason: "only reviewed tool restore adapters may request Projects-owned asset materialization"
  },
  %{
    module: "Storyarn.Projects",
    path: "lib/storyarn/projects.ex",
    functions: [link_asset_variant: 3],
    allowed_callers: [
      "lib/storyarn/scenes/assets/adapters/projects/asset_registration.ex",
      "lib/storyarn/sheets/assets/adapters/projects/asset_registration.ex"
    ],
    reason: "only reviewed Sheet and Scene variant workflows may request the Projects-owned relationship write"
  },
  %{
    module: "Storyarn.Projects.Assets",
    path: "lib/storyarn/projects/assets/assets.ex",
    functions: [register_uploaded_asset: 4, register_materialized_asset: 3, link_asset_variant: 3],
    allowed_callers: [
      "lib/storyarn/projects.ex"
    ],
    reason: "asset-registration commands remain behind the public Projects facade"
  },
  %{
    module: "Storyarn.Projects.Assets.Commands.AssetRegistration",
    path: "lib/storyarn/projects/assets/commands/asset_registration.ex",
    functions: [register_uploaded_asset: 4, register_materialized_asset: 3, link_asset_variant: 3],
    allowed_callers: [
      "lib/storyarn/projects/assets/assets.ex"
    ],
    reason: "the Projects Assets capability is the only route to the transaction-bound asset writer"
  },
  %{
    module: "Storyarn.Flows.Versioning.Adapters.Localization.VersionRestore",
    path: "lib/storyarn/flows/versioning/adapters/localization/version_restore.ex",
    functions: [prepare: 3],
    allowed_callers: [
      "lib/storyarn/flows/versioning/execution/flow_snapshot.ex"
    ],
    reason: "only exact Flow snapshot restore may archive its current localization inventory"
  },
  %{
    module: "Storyarn.Flows.Versioning.Adapters.Localization.VersionRestore",
    path: "lib/storyarn/flows/versioning/adapters/localization/version_restore.ex",
    functions: [restore: 3],
    allowed_callers: [
      "lib/storyarn/flows/versioning/execution/flow_snapshot.ex",
      "lib/storyarn/flows/versioning/execution/localization_codec.ex"
    ],
    reason: "only the reviewed Flow restore paths may enter Flow's Localization version adapter"
  },
  %{
    module: "Storyarn.Sheets.Versioning.Adapters.Localization.VersionRestore",
    path: "lib/storyarn/sheets/versioning/adapters/localization/version_restore.ex",
    functions: [restore: 3],
    allowed_callers: [
      "lib/storyarn/sheets/versioning/execution/localization_codec.ex",
      "lib/storyarn/sheets/versioning/execution/sheet_snapshot.ex"
    ],
    reason: "only the reviewed Sheet restore paths may enter Sheet's Localization version adapter"
  },
  %{
    module: "Storyarn.Projects.Versioning.Adapters.Localization.VersionRestore",
    path: "lib/storyarn/projects/versioning/adapters/localization/version_restore.ex",
    functions: [lock_inventory!: 1],
    allowed_callers: [
      "lib/storyarn/projects/versioning/execution/builders/flow_builder.ex",
      "lib/storyarn/projects/versioning/execution/builders/sheet_builder.ex"
    ],
    reason: "only Project Flow and Sheet materializers may acquire the Localization inventory lock through this adapter"
  },
  %{
    module: "Storyarn.Projects.Versioning.Adapters.Localization.VersionRestore",
    path: "lib/storyarn/projects/versioning/adapters/localization/version_restore.ex",
    functions: [extract_flow: 1],
    allowed_callers: [
      "lib/storyarn/projects/versioning/execution/builders/flow_builder.ex"
    ],
    reason: "only Project Flow materialization may request post-restore Flow text extraction"
  },
  %{
    module: "Storyarn.Projects.Versioning.Adapters.Localization.VersionRestore",
    path: "lib/storyarn/projects/versioning/adapters/localization/version_restore.ex",
    functions: [extract_sheet: 1, sync_sheet_names: 1],
    allowed_callers: [
      "lib/storyarn/projects/versioning/execution/builders/sheet_builder.ex"
    ],
    reason: "only Project Sheet materialization may request post-restore Sheet text reconciliation"
  },
  %{
    module: "Storyarn.Projects.Versioning.Adapters.Localization.VersionRestore",
    path: "lib/storyarn/projects/versioning/adapters/localization/version_restore.ex",
    functions: [restore_flow: 3],
    allowed_callers: [
      "lib/storyarn/projects/versioning/execution/builders/flow_builder.ex"
    ],
    reason: "only Project Flow materialization may request exact Flow localization restoration"
  },
  %{
    module: "Storyarn.Projects.Versioning.Adapters.Localization.VersionRestore",
    path: "lib/storyarn/projects/versioning/adapters/localization/version_restore.ex",
    functions: [restore_sheet: 3],
    allowed_callers: [
      "lib/storyarn/projects/versioning/execution/builders/sheet_builder.ex"
    ],
    reason: "only Project Sheet materialization may request exact Sheet localization restoration"
  },
  %{
    module: "Storyarn.Flows.Localization",
    path: "lib/storyarn/flows/localization/localization.ex",
    functions: [lock_inventory!: 1],
    allowed_callers: [
      "lib/storyarn/flows/versioning/execution/flow_snapshot.ex"
    ],
    reason:
      "only Flow snapshot build/restore may use the narrow inventory lock that preserves its existing Project-then-Flow lock order"
  },
  %{
    module: "Storyarn.Localization",
    path: "lib/storyarn/localization.ex",
    functions: [lock_inventory_after_project_lock!: 1],
    allowed_callers: [
      "lib/storyarn/flows/localization/localization.ex"
    ],
    reason:
      "only the sealed Flow localization boundary may request the advisory lock after its caller has already locked Project"
  },
  %{
    module: "Storyarn.Localization.Texts",
    path: "lib/storyarn/localization/texts/texts.ex",
    functions: [lock_inventory_after_project_lock!: 1],
    allowed_callers: [
      "lib/storyarn/localization.ex"
    ],
    reason: "the pre-locked inventory port remains behind the public Localization facade"
  },
  %{
    module: "Storyarn.Localization.Texts.Commands.Extract",
    path: "lib/storyarn/localization/texts/commands/extract.ex",
    functions: [lock_inventory_after_project_lock!: 1],
    allowed_callers: [
      "lib/storyarn/localization/texts/texts.ex"
    ],
    reason: "only the Localization Texts capability may acquire the advisory inventory lock without relocking Project"
  },
  %{
    module: "Storyarn.Localization",
    path: "lib/storyarn/localization.ex",
    functions: [prepare_flow_version_texts: 3],
    allowed_callers: [
      "lib/storyarn/flows/versioning/adapters/localization/version_restore.ex"
    ],
    reason: "Flow's narrow version adapter is the only caller of the public prepare command"
  },
  %{
    module: "Storyarn.Localization",
    path: "lib/storyarn/localization.ex",
    functions: [restore_flow_version_texts: 3],
    allowed_callers: [
      "lib/storyarn/flows/versioning/adapters/localization/version_restore.ex",
      "lib/storyarn/projects/versioning/adapters/localization/version_restore.ex"
    ],
    reason: "only reviewed Flow and Project materializers may request exact Flow localization writes"
  },
  %{
    module: "Storyarn.Localization",
    path: "lib/storyarn/localization.ex",
    functions: [restore_sheet_version_texts: 3],
    allowed_callers: [
      "lib/storyarn/projects/versioning/adapters/localization/version_restore.ex",
      "lib/storyarn/sheets/versioning/adapters/localization/version_restore.ex"
    ],
    reason: "only reviewed Sheet and Project materializers may request exact Sheet localization writes"
  },
  %{
    module: "Storyarn.Localization.Texts",
    path: "lib/storyarn/localization/texts/texts.ex",
    functions: [
      prepare_flow_version_texts: 3,
      restore_flow_version_texts: 3,
      restore_sheet_version_texts: 3
    ],
    allowed_callers: [
      "lib/storyarn/localization.ex"
    ],
    reason: "version writers remain behind the public Localization facade"
  },
  %{
    module: "Storyarn.Localization.Texts.Commands.VersionRestore",
    path: "lib/storyarn/localization/texts/commands/version_restore.ex",
    functions: [prepare_flow: 3, restore_flow: 3, restore_sheet: 3],
    allowed_callers: [
      "lib/storyarn/localization/texts/texts.ex"
    ],
    reason: "the Localization Texts capability is the only route to exact transaction-participating version writes"
  },
  %{
    module: "Storyarn.Projects.References.EntityTracker",
    path: "lib/storyarn/projects/references/commands/entity_tracker.ex",
    functions: [rebuild_project_entity_references: 1],
    allowed_callers: [
      "lib/storyarn/projects/references/references.ex"
    ],
    reason: "the Project-wide entity-reference rebuild stays behind the Projects References capability"
  },
  %{
    module: "Storyarn.Projects.References.VariableReferenceTracker",
    path: "lib/storyarn/projects/references/commands/variable_reference_tracker.ex",
    functions: [rebuild_project_variable_references: 1],
    allowed_callers: [
      "lib/storyarn/projects/references/execution/variable_tracker.ex"
    ],
    reason: "the Project-wide variable-reference rebuild stays behind its internal Projects adapter"
  },
  %{
    module: "Storyarn.Projects.References.MaterializedFormulaBindingRewriter",
    path: "lib/storyarn/projects/references/commands/materialized_formula_binding_rewriter.ex",
    functions: [rewrite: 3],
    allowed_callers: [
      "lib/storyarn/projects/versioning/execution/project_recovery.ex"
    ],
    reason: "only Project recovery may rewrite materialized formula bindings after portable namespace remapping"
  },
  %{
    module: "Storyarn.Projects.References.VariableTracker",
    path: "lib/storyarn/projects/references/execution/variable_tracker.ex",
    functions: [rebuild_project_variable_references: 1],
    allowed_callers: [
      "lib/storyarn/projects/references/references.ex"
    ],
    reason: "the internal Project-wide variable-reference adapter stays behind the Projects References capability"
  },
  %{
    module: "Storyarn.Projects.References",
    path: "lib/storyarn/projects/references/references.ex",
    functions: [rebuild_project_entity_references: 1],
    allowed_callers: [
      "lib/storyarn/projects/versioning/execution/project_recovery.ex",
      "lib/storyarn/projects/versioning/execution/project_snapshot_restore_executor.ex"
    ],
    reason: "Project-wide entity-reference rebuild is reserved for recovery and exact restore"
  },
  %{
    module: "Storyarn.Projects.References",
    path: "lib/storyarn/projects/references/references.ex",
    functions: [rebuild_project_variable_references: 1],
    allowed_callers: [
      "lib/storyarn/projects/versioning/execution/builders/sheet_builder.ex",
      "lib/storyarn/projects/versioning/execution/project_recovery.ex",
      "lib/storyarn/projects/versioning/execution/project_snapshot_restore_executor.ex"
    ],
    reason: "Project-wide variable-reference rebuild is reserved for materialization, recovery and exact restore"
  },
  %{
    module: "Storyarn.Sheets.References.Commands.VariableProjection",
    path: "lib/storyarn/sheets/references/commands/variable_projection.ex",
    functions: [rebuild_project: 1],
    allowed_callers: [
      "lib/storyarn/sheets/references/references.ex"
    ],
    reason: "the additive Sheet-owned reference reconciliation stays behind the Sheets References capability"
  },
  %{
    module: "Storyarn.Sheets.References",
    path: "lib/storyarn/sheets/references/references.ex",
    functions: [rebuild_project_variable_references: 1],
    allowed_callers: [
      "lib/storyarn/sheets/versioning/execution/sheet_snapshot.ex"
    ],
    reason:
      "only Sheet snapshot materialization and restore may request additive cross-tool variable-reference reconciliation"
  },
  %{
    module: "Storyarn.Projects.FlowProjectTrash",
    path: "lib/storyarn/projects/trash/execution/flow_project_trash.ex",
    functions: [delete_subtree_in_transaction: 1],
    allowed_callers: [
      "lib/storyarn/projects/interchange/imports/commands/replacement.ex",
      "lib/storyarn/projects/versioning/execution/project_snapshot_restore_executor.ex"
    ],
    reason: "transaction-internal Flow subtree deletion is reserved for exact Project replacement and restore"
  },
  %{
    module: "Storyarn.Projects.SheetProjectTrash",
    path: "lib/storyarn/projects/trash/execution/sheet_project_trash.ex",
    functions: [delete_subtree_in_transaction: 1],
    allowed_callers: [
      "lib/storyarn/projects/interchange/imports/commands/replacement.ex",
      "lib/storyarn/projects/versioning/execution/project_snapshot_restore_executor.ex"
    ],
    reason: "transaction-internal Sheet subtree deletion is reserved for exact Project replacement and restore"
  },
  %{
    module: "Storyarn.Projects.SceneProjectTrash",
    path: "lib/storyarn/projects/trash/execution/scene_project_trash.ex",
    functions: [delete_subtree_in_transaction: 1],
    allowed_callers: [
      "lib/storyarn/projects/interchange/imports/commands/replacement.ex",
      "lib/storyarn/projects/versioning/execution/project_snapshot_restore_executor.ex"
    ],
    reason: "transaction-internal Scene subtree deletion is reserved for exact Project replacement and restore"
  },
  %{
    module: "Storyarn.Flows.Versioning.FlowSnapshot",
    path: "lib/storyarn/flows/versioning/execution/flow_snapshot.ex",
    functions: [restore: 2, restore: 3, restore_snapshot: 2, restore_snapshot: 3],
    allowed_callers: [
      "lib/storyarn/flows/versioning/execution/restore.ex"
    ],
    reason: "only the Flow restore use case may enter the exact Flow snapshot writer"
  },
  %{
    module: "Storyarn.Sheets.Versioning.SheetSnapshot",
    path: "lib/storyarn/sheets/versioning/execution/sheet_snapshot.ex",
    functions: [restore: 2, restore: 3, restore_snapshot: 2, restore_snapshot: 3],
    allowed_callers: [
      "lib/storyarn/sheets/versioning/execution/restore.ex"
    ],
    reason: "only the Sheet restore use case may enter the exact Sheet snapshot writer"
  },
  %{
    module: "Storyarn.Sheets.Versioning.SheetSnapshot",
    path: "lib/storyarn/sheets/versioning/execution/sheet_snapshot.ex",
    functions: [instantiate_snapshot: 2, instantiate_snapshot: 3],
    allowed_callers: [],
    reason: "the unused public Sheet materializer remains sealed until a reviewed owner use case needs it"
  },
  %{
    module: "Storyarn.Scenes.Versioning.SceneSnapshot",
    path: "lib/storyarn/scenes/versioning/execution/scene_snapshot.ex",
    functions: [restore: 2, restore: 3, restore_snapshot: 2, restore_snapshot: 3],
    allowed_callers: [
      "lib/storyarn/scenes/versioning/execution/restore.ex"
    ],
    reason: "only the Scene restore use case may enter the exact Scene snapshot writer"
  }
]

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
  # tests consume these per-table contracts and reject new writers until source
  # ownership or a privileged exception is reviewed deliberately.
  persistence_ownership: %{
    assets: asset_persistence_ownership,
    entity_references: entity_reference_persistence_ownership,
    localized_texts: localized_text_persistence_ownership,
    project_languages: project_language_persistence_ownership,
    projects: aggregate_identity_persistence_ownership.projects,
    project_memberships: aggregate_identity_persistence_ownership.project_memberships,
    storage_cleanup_requests: storage_cleanup_persistence_ownership,
    variable_references: variable_reference_persistence_ownership,
    workspaces: aggregate_identity_persistence_ownership.workspaces,
    workspace_memberships: aggregate_identity_persistence_ownership.workspace_memberships
  },
  shared_persistence_mappings: shared_persistence_mapping_policy,
  canonical_owner_membership_invariant: canonical_owner_membership_invariant,
  privileged_entrypoints: privileged_entrypoints,

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
      commercial_root_facade_path_denials ++
      commercial_passive_effect_denials ++
      commercial_passive_role_dependency_denials ++
      [commercial_rule_persistence_denial] ++
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
    :commercial,
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
  isolated_contexts: [
    :accounts,
    :ai,
    :commercial,
    :flows,
    :localization,
    :platform,
    :projects,
    :scenes,
    :sheets,
    :workspaces
  ],

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
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason: "Asset lifecycle accounts storage usage through the public Commercial facade"
    },
    %{
      source: "lib/storyarn/projects/assets/execution/asset_trash.ex",
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason: "Asset lifecycle accounts storage usage through the public Commercial facade"
    },
    %{
      source: "lib/storyarn/projects/assets/execution/blob_store.ex",
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason: "Asset lifecycle accounts storage usage through the public Commercial facade"
    },
    %{
      source: "lib/storyarn/projects/interchange/imports/execution/execution.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Project imports publish committed notification outcomes through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/interchange/imports/execution/execution.ex",
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason: "Project imports enforce storage policy through the public Commercial facade"
    },
    %{
      source: "lib/storyarn/projects/interchange/imports/commands/expiration.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Project imports publish committed notification outcomes through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/interchange/imports/execution/materializer.ex",
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason: "Project imports enforce storage policy through the public Commercial facade"
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
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason: "Project replacement imports coordinate storage locks through the public Commercial facade"
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
      reason: "Template installation publishes notification outcomes through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/templates/execution/installation.ex",
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason: "Template installation enforces policy through the public Commercial facade"
    },
    %{
      source: "lib/storyarn/projects/templates/execution/publication_runner.ex",
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason: "Template publication enforces commercial policy through the public Commercial facade"
    },
    %{
      source: "lib/storyarn/projects/lifecycle/commands/project_commands.ex",
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason: "Project lifecycle enforces commercial policy through the public Commercial facade"
    },
    %{
      source: "lib/storyarn/projects/lifecycle/commands/workspace_data_lifecycle.ex",
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason: "Workspace hard-delete preparation verifies the Commercial-owned canonical workspace lock"
    },
    %{
      source: "lib/storyarn/projects/versioning/adapters/commercial/storage_reservations.ex",
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason:
        "The Projects anti-corruption layer exchanges transport-neutral storage receipts through the public Commercial facade"
    },
    %{
      source: "lib/storyarn/projects/trash/execution/project_trash.ex",
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason: "Project lifecycle enforces commercial policy through the public Commercial facade"
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
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason: "Project invitations enforce Commercial-owned member seat policy"
    },
    %{
      source: "lib/storyarn/projects/versioning/versioning.ex",
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason: "Snapshot storage lifecycle accounts usage and locks through the public Commercial facade"
    },
    %{
      source: "lib/storyarn/projects/versioning/execution/materialization_helpers.ex",
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason: "Snapshot materialization accounts storage through the public Commercial facade"
    },
    %{
      source: "lib/storyarn/projects/versioning/execution/project_recovery.ex",
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason: "Project recovery coordinates storage locks through the public Commercial facade"
    },
    %{
      source: "lib/storyarn/projects/versioning/rules/project_snapshot_lease_policy.ex",
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason: "Project snapshot grants consume the lease policy through the public Commercial facade"
    },
    %{
      source: "lib/storyarn/projects/versioning/execution/project_snapshot_asset_materializer.ex",
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason: "Snapshot asset materialization accounts storage through the public Commercial facade"
    },
    %{
      source: "lib/storyarn/projects/versioning/execution/project_snapshot_build.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Snapshot builds publish notification outcomes through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/versioning/execution/project_snapshot_build.ex",
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason: "Snapshot builds coordinate storage accounting through the public Commercial facade"
    },
    %{
      source: "lib/storyarn/projects/versioning/commands/project_snapshot_crud.ex",
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason: "Snapshot lifecycle accounts storage and locks through the public Commercial facade"
    },
    %{
      source: "lib/storyarn/projects/versioning/execution/project_snapshot_download.ex",
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason: "Snapshot downloads acquire storage leases through the public Commercial facade"
    },
    %{
      source: "lib/storyarn/projects/versioning/commands/project_snapshot_lifecycle.ex",
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason: "Snapshot lifecycle accounts storage and locks through the public Commercial facade"
    },
    %{
      source: "lib/storyarn/projects/versioning/execution/project_snapshot_reconciliation_repair.ex",
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason: "Snapshot reconciliation repairs storage accounting through the public Commercial facade"
    },
    %{
      source: "lib/storyarn/projects/versioning/commands/project_snapshot_restore_lifecycle.ex",
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason: "Snapshot restore lifecycle accounts storage and locks through the public Commercial facade"
    },
    %{
      source: "lib/storyarn/projects/versioning/commands/workspace_snapshot_imports.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Workspace snapshot imports publish notification outcomes through the public Platform facade"
    },
    %{
      source: "lib/storyarn/projects/versioning/commands/workspace_snapshot_imports.ex",
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason: "Workspace snapshot imports coordinate storage through the public Commercial facade"
    },
    %{
      source: "lib/storyarn/projects/versioning/queries/snapshot_accounting.ex",
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason:
        "Projects consumes neutral storage usage, reservation totals and entitlements through the public Commercial facade"
    },
    %{
      source: "lib/storyarn_web/live/project_live/invitation.ex",
      target: "lib/storyarn/public/publication/locales.ex",
      kinds: ["runtime"],
      reason: "Invitation pages normalize the public locale like the other public-facing pages"
    },
    %{
      source: "lib/storyarn_web/live/project_settings_live/snapshots.ex",
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason: "Project snapshot settings subscribe to Commercial-owned export-lease fences through the public facade"
    },
    %{
      source: "lib/storyarn_web/live/project_settings_live/usage_limits.ex",
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason: "Project settings pages show plan usage through the public Commercial facade"
    },
    %{
      source: "lib/storyarn_web/live/project_settings_live/version_control.ex",
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason: "Project settings pages show plan usage through the public Commercial facade"
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
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason: "Flow authoring applies Commercial-owned item entitlements"
    },
    %{
      source: "lib/storyarn/flows/versioning/commands/named_version_capacity.ex",
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason: "Flow versioning applies Commercial-owned named-version entitlements"
    },
    %{
      source: "lib/storyarn/flows/versioning/execution/asset_catalog.ex",
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason: "Flow snapshot materialization applies the Commercial-owned storage entitlement"
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
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason: "Scene asset writes apply the Commercial-owned storage entitlement"
    },
    %{
      source: "lib/storyarn/scenes/assets/events/assets.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Scene Assets publishes its owned business facts through the Platform reaction contract"
    },
    %{
      source: "lib/storyarn/scenes/editor/commands/item_capacity.ex",
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason: "The Scene editor applies the Commercial-owned project item entitlement"
    },
    %{
      source: "lib/storyarn/scenes/exploration/events/exploration_events.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Scene Exploration publishes its owned business facts through the Platform reaction contract"
    },
    %{
      source: "lib/storyarn/scenes/versioning/commands/named_version_capacity.ex",
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason: "Scene Versioning applies the Commercial-owned named-version entitlement"
    },
    %{
      source: "lib/storyarn/scenes/versioning/events/versions.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Scene Versioning publishes its owned business facts through the Platform reaction contract"
    },
    %{
      source: "lib/storyarn/sheets/assets/commands/assets.ex",
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason: "Sheet asset writes apply the Commercial-owned storage entitlement"
    },
    %{
      source: "lib/storyarn/sheets/assets/events/assets.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Sheet Assets publishes its owned business facts through the Platform reaction contract"
    },
    %{
      source: "lib/storyarn/sheets/editor/commands/item_capacity.ex",
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason: "The Sheet editor applies the Commercial-owned project item entitlement"
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
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason: "Sheet Versioning applies the Commercial-owned named-version entitlement"
    },
    %{
      source: "lib/storyarn/sheets/versioning/events/versions.ex",
      target: "lib/storyarn/platform.ex",
      kinds: ["runtime"],
      reason: "Sheet Versioning publishes its owned business facts through the Platform reaction contract"
    },
    %{
      source: "lib/storyarn/workspaces/lifecycle/commands/create_workspace.ex",
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason: "Workspace creation applies commercial limits and subscriptions through the public Commercial facade"
    },
    %{
      source: "lib/storyarn/workspaces/memberships/commands/transfer_ownership.ex",
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason:
        "Workspace ownership transfer applies the receiver's Commercial-owned workspace entitlement while holding its user lock"
    },
    %{
      source: "lib/storyarn/workspaces/lifecycle/commands/delete_workspace.ex",
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason: "Workspace hard-delete executes under the Commercial-owned workspace lifecycle lock"
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
      source: "lib/storyarn_web/live/project_settings_live/localization.ex",
      target: "lib/storyarn/projects.ex",
      kinds: ["runtime"],
      reason:
        "The Localization-owned project settings adapter subscribes to committed Project ownership changes and refreshes access through the public Projects facade"
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
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason: "Workspace invitation creation applies Commercial-owned member seat policy"
    },
    %{
      source: "lib/storyarn/workspaces/invitations/commands/accept.ex",
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason: "Workspace invitation acceptance applies Commercial-owned member seat policy"
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
      source: "lib/storyarn/sheets/editor/adapters/flows/dialogue_audio.ex",
      target: "lib/storyarn/flows.ex",
      kinds: ["runtime"],
      reason:
        "The Sheet audio workspace sends one explicit command to the Flow-owned node writer; the adapter exposes no Flow records or internals"
    },
    %{
      source: "lib/storyarn/flows/versioning/adapters/projects/asset_registration.ex",
      target: "lib/storyarn/projects.ex",
      kinds: ["runtime"],
      reason:
        "Flow snapshot materialization requests Projects-owned asset persistence through one narrow transaction-bound adapter"
    },
    %{
      source: "lib/storyarn/flows/localization/localization.ex",
      target: "lib/storyarn/localization.ex",
      kinds: ["runtime"],
      reason:
        "Flow mutations request ordinary localized-text extraction and lifecycle through the public Localization owner"
    },
    %{
      source: "lib/storyarn/flows/versioning/adapters/localization/version_restore.ex",
      target: "lib/storyarn/localization.ex",
      kinds: ["runtime"],
      reason: "Flow restore enters exact Localization persistence through one sealed transaction-participating adapter"
    },
    %{
      source: "lib/storyarn/scenes/assets/adapters/projects/asset_registration.ex",
      target: "lib/storyarn/projects.ex",
      kinds: ["runtime"],
      reason:
        "Scene upload and restore workflows request Projects-owned asset persistence through one narrow transaction-bound adapter"
    },
    %{
      source: "lib/storyarn/sheets/assets/adapters/projects/asset_registration.ex",
      target: "lib/storyarn/projects.ex",
      kinds: ["runtime"],
      reason:
        "Sheet upload and restore workflows request Projects-owned asset persistence through one narrow transaction-bound adapter"
    },
    %{
      source: "lib/storyarn/projects/trash/execution/flow_project_trash.ex",
      target: "lib/storyarn/localization.ex",
      kinds: ["runtime"],
      reason: "Project Flow trash restoration asks Localization to rebuild its owned derived text inventory"
    },
    %{
      source: "lib/storyarn/projects/trash/execution/sheet_project_trash.ex",
      target: "lib/storyarn/localization.ex",
      kinds: ["runtime"],
      reason: "Project Sheet trash restoration asks Localization to rebuild its owned derived text inventory"
    },
    %{
      source: "lib/storyarn/projects/versioning/adapters/localization/version_restore.ex",
      target: "lib/storyarn/localization.ex",
      kinds: ["runtime"],
      reason:
        "Project reconstitution enters exact Localization persistence through one sealed transaction-participating adapter"
    },
    %{
      source: "lib/storyarn/sheets/localization/localization.ex",
      target: "lib/storyarn/localization.ex",
      kinds: ["runtime"],
      reason:
        "Sheet mutations request ordinary localized-text extraction and lifecycle through the public Localization owner"
    },
    %{
      source: "lib/storyarn/sheets/versioning/adapters/localization/version_restore.ex",
      target: "lib/storyarn/localization.ex",
      kinds: ["runtime"],
      reason: "Sheet restore enters exact Localization persistence through one sealed transaction-participating adapter"
    },
    %{
      source: "lib/storyarn/projects/references/adapters/flows/stale_variable_reference_repair.ex",
      target: "lib/storyarn/flows.ex",
      kinds: ["runtime"],
      reason:
        "Project settings preserve the aggregate repair workflow through one exact command adapter while Flows owns candidate interpretation, node data and derivative writes"
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
      target: "lib/storyarn/commercial.ex",
      kinds: ["runtime"],
      reason: "The workspace home reads plan policy through the public Commercial facade"
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
