# ENG-92 code boundaries. These rules intentionally protect code ownership only:
# they do not assign database write ownership or change the shared schema.

boundaries = %{
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
  project: [
    "lib/storyarn/projects.ex",
    "lib/storyarn/projects/",
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
    "lib/storyarn_web/live/project_live/",
    "lib/storyarn_web/live/project_settings_live/",
    "lib/storyarn_web/live/project_sidebar_live.ex",
    "lib/storyarn_web/live/compare_live/",
    "lib/storyarn_web/live/version_viewer_live.ex",
    "lib/storyarn_web/live/export_import_live/",
    "lib/storyarn_web/live/template_live/"
  ],

  # Technical classification, not a fifth bounded context. It makes imports of
  # supporting internals visible while allowing platform modules to collaborate
  # with each other. More specific roots above always win.
  platform: [
    "lib/storyarn/"
  ],

  # Web coordination outside a concrete tool/Project surface. This is kept
  # separate from platform so shared Web helpers cannot hide tool imports.
  web_platform: [
    "lib/storyarn_web/"
  ]
}

# ENG-92 has four business boundaries. Project owns the global/project surface;
# its members are intentionally allowed to collaborate with each other. The
# tools cannot import each other or Project, while Project cannot import tools.
# Platform is asymmetric in ratchet v1: tools may call only its explicitly
# public/technical targets, and platform cannot bridge back into tools. Project
# and platform may still collaborate while the high-risk lifecycle code is
# migrated; tightening that relationship is not part of ENG-92. Shared Web code
# may be consumed by a boundary, but cannot bridge into a tool domain.
forbidden_dependencies = %{
  sheets: [:flows, :platform, :project, :scenes],
  flows: [:platform, :project, :scenes, :sheets],
  scenes: [:flows, :platform, :project, :sheets],
  project: [:flows, :scenes, :sheets],
  platform: [:flows, :scenes, :sheets],
  web_platform: [:flows, :scenes, :sheets]
}

%{
  version: 1,
  boundaries: boundaries,
  forbidden_dependencies: forbidden_dependencies,

  # Repo is deliberately shared during ENG-92. Ecto and other external
  # dependencies do not appear as repository paths in the xref JSON graph.
  always_allowed_targets: [
    "lib/storyarn/repo.ex",
    "lib/storyarn/gettext.ex",
    "lib/storyarn/accounts/scope.ex",
    "lib/storyarn/dashboards/cache.ex",
    "lib/storyarn/accounts.ex",
    "lib/storyarn/ai.ex",
    "lib/storyarn/analytics.ex",
    "lib/storyarn/assets.ex",
    "lib/storyarn/billing.ex",
    "lib/storyarn/collaboration.ex",
    "lib/storyarn/command_palette.ex",
    "lib/storyarn/feature_flags.ex",
    "lib/storyarn/global_search.ex",
    "lib/storyarn/localization.ex",
    "lib/storyarn/mailer.ex",
    "lib/storyarn/notifications.ex",
    "lib/storyarn/onboarding.ex",
    "lib/storyarn/rate_limiter.ex",
    "lib/storyarn/urls.ex",
    "lib/storyarn/workspaces.ex",
    "lib/storyarn/shared/color_utils.ex",
    "lib/storyarn/shared/formula_engine.ex",
    "lib/storyarn/shared/formula_runtime.ex",
    "lib/storyarn/shared/hierarchical_schema.ex",
    "lib/storyarn/shared/html_sanitizer.ex",
    "lib/storyarn/shared/html_utils.ex",
    "lib/storyarn/shared/import_helpers.ex",
    "lib/storyarn/shared/map_utils.ex",
    "lib/storyarn/shared/name_normalizer.ex",
    "lib/storyarn/shared/search_helpers.ex",
    "lib/storyarn/shared/severity.ex",
    "lib/storyarn/shared/shortcut_helpers.ex",
    "lib/storyarn/shared/soft_delete.ex",
    "lib/storyarn/shared/string_utils.ex",
    "lib/storyarn/shared/time_helpers.ex",
    "lib/storyarn/shared/token_generator.ex",
    "lib/storyarn/shared/trashable.ex",
    "lib/storyarn/shared/tree_operations.ex",
    "lib/storyarn/shared/validations.ex",
    "lib/storyarn/shared/word_count.ex"
  ],

  # Exceptions must identify one exact edge and dependency kind, and explain
  # why it is a durable architectural contract. Temporary debt belongs only in
  # the baseline files, never here.
  exceptions:
    Enum.map(
      [
        "lib/storyarn_web/live/flow_live/index.ex",
        "lib/storyarn_web/live/flow_live/player_live.ex",
        "lib/storyarn_web/live/flow_live/show.ex",
        "lib/storyarn_web/live/scene_live/exploration_live.ex",
        "lib/storyarn_web/live/scene_live/index.ex",
        "lib/storyarn_web/live/scene_live/show.ex",
        "lib/storyarn_web/live/sheet_live/index.ex",
        "lib/storyarn_web/live/sheet_live/show.ex"
      ],
      fn target ->
        %{
          source: "lib/storyarn_web/router.ex",
          target: target,
          kinds: ["runtime"],
          reason: "Phoenix router owns the route declaration for this tool LiveView"
        }
      end
    )
}
