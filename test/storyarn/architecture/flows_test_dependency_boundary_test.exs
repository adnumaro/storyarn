defmodule Storyarn.Architecture.FlowsTestDependencyBoundaryTest do
  use ExUnit.Case, async: true

  @flow_owned_roots [
    "test/storyarn/flows/",
    "test/storyarn_web/live/flow_live/"
  ]

  @foreign_context_modules [
    "Storyarn.Accounts",
    "Storyarn.Projects.Assets",
    "Storyarn.Commercial.Billing",
    "Storyarn.Platform.Emails",
    "Storyarn.Projects.Exports",
    "Storyarn.Projects.Imports",
    "Storyarn.Localization",
    "Storyarn.Platform.Notifications",
    "Storyarn.Platform",
    "Storyarn.Projects",
    "Storyarn.Projects.ProjectTemplates",
    "Storyarn.Projects.References",
    "Storyarn.Scenes",
    "Storyarn.Sheets",
    "Storyarn.Shortcuts",
    "Storyarn.Projects.Versioning",
    "Storyarn.Workspaces"
  ]

  # Flow-owned tests may cross a boundary only when they explicitly exercise
  # an integration contract. This exact inventory makes those seams visible
  # and prevents an innocent-looking test helper from reintroducing coupling.
  @flow_owned_integration_contracts %{
    "test/storyarn/flows/editor/commands/dialogue_audio_concurrency_test.exs" => [
      "Storyarn.Accounts.User",
      "Storyarn.Projects.Assets",
      "Storyarn.Projects.Assets.Asset",
      "Storyarn.Projects.Project",
      "Storyarn.Workspaces.Workspace"
    ],
    "test/storyarn/flows/editor/commands/dialogue_audio_test.exs" => [
      "Storyarn.Projects.Assets"
    ],
    "test/storyarn/flows/references/commands/avatar_integrity_test.exs" => [
      "Storyarn.Sheets"
    ],
    "test/storyarn/flows/editor/commands/cross_flow_write_isolation_test.exs" => [
      "Storyarn.Accounts.User",
      "Storyarn.Projects.Project",
      "Storyarn.Workspaces.Workspace"
    ],
    "test/storyarn/flows/editor/queries/editor_catalog_test.exs" => [
      "Storyarn.Projects.Assets",
      "Storyarn.Projects.Assets.Asset",
      "Storyarn.Scenes",
      "Storyarn.Sheets"
    ],
    "test/storyarn/flows/references/commands/entity_trash_refs_concurrency_test.exs" => [
      "Storyarn.Accounts.User",
      "Storyarn.Sheets",
      "Storyarn.Sheets.Sheet",
      "Storyarn.Sheets.SheetAvatar",
      "Storyarn.Workspaces.Workspace"
    ],
    "test/storyarn/flows/references/commands/entity_trash_refs_test.exs" => [
      "Storyarn.Sheets"
    ],
    "test/storyarn/flows/references/commands/entity_reference_tracker_concurrency_test.exs" => [
      "Storyarn.Accounts.User",
      "Storyarn.Sheets",
      "Storyarn.Workspaces.Workspace"
    ],
    "test/storyarn/flows/references/commands/stale_variable_reference_repair_concurrency_test.exs" => [
      "Storyarn.Accounts.User",
      # Public ownership-transfer facade: this integration test pins the
      # transfer-versus-Flow-repair concurrency contract. No Projects internals
      # are allowed through this seam.
      "Storyarn.Projects",
      "Storyarn.Projects.Project",
      "Storyarn.Sheets",
      "Storyarn.Workspaces.Workspace"
    ],
    "test/storyarn/flows/references/commands/stale_variable_reference_repair_test.exs" => [
      "Storyarn.Projects"
    ],
    "test/storyarn/flows/editor/queries/exit_target_scenes_test.exs" => [
      "Storyarn.Scenes"
    ],
    "test/storyarn/flows/editor/commands/flow_restore_integrity_test.exs" => [
      "Storyarn.Scenes",
      "Storyarn.Sheets"
    ],
    "test/storyarn/flows/versioning/commands/named_version_capacity_concurrency_test.exs" => [
      "Storyarn.Accounts.User",
      "Storyarn.Projects.Project",
      "Storyarn.Workspaces.Workspace"
    ],
    "test/storyarn/flows/editor/commands/node_crud_test.exs" => [
      "Storyarn.Localization",
      "Storyarn.Localization.RuntimeKey",
      "Storyarn.Projects.References.EntityReference"
    ],
    "test/storyarn/flows/editor/commands/node_delete_concurrency_test.exs" => [
      "Storyarn.Accounts.User",
      "Storyarn.Workspaces.Workspace"
    ],
    "test/storyarn/flows/editor/commands/node_restore_integrity_test.exs" => [
      "Storyarn.Localization.RuntimeKey",
      "Storyarn.Projects.References",
      "Storyarn.Sheets"
    ],
    "test/storyarn/flows/editor/commands/node_update_batch_test.exs" => [
      "Storyarn.Sheets"
    ],
    "test/storyarn/flows/runtime/queries/player_catalog_test.exs" => [
      "Storyarn.Projects.Assets.Asset",
      "Storyarn.Sheets"
    ],
    "test/storyarn/flows/runtime/execution/runtime_variables_test.exs" => [
      "Storyarn.Sheets"
    ],
    "test/storyarn/flows/versioning/execution/conflict_detector_test.exs" => [
      "Storyarn.Projects.Assets",
      "Storyarn.Sheets"
    ],
    "test/storyarn/flows/versioning/execution/flow_snapshot_restore_test.exs" => [
      "Storyarn.Localization",
      "Storyarn.Localization.LocalizedText",
      "Storyarn.Platform.ObjectStorage",
      "Storyarn.Projects.Assets",
      "Storyarn.Projects.Assets.Asset",
      "Storyarn.Projects.Assets.BlobStore",
      "Storyarn.Projects.Project",
      "Storyarn.Projects.References"
    ],
    "test/storyarn/flows/versioning/adapters/storage/snapshot_storage_test.exs" => [
      "Storyarn.Platform.ObjectStorage"
    ],
    "test/storyarn/flows/versioning/execution/flow_snapshot_test.exs" => [
      "Storyarn.Localization",
      "Storyarn.Localization.LocalizedText",
      "Storyarn.Projects.Assets",
      "Storyarn.Projects.Assets.Asset",
      "Storyarn.Projects.Assets.BlobStore",
      "Storyarn.Projects.Persistence.FlowRecord",
      "Storyarn.Projects.Versioning.Builders.FlowBuilder"
    ],
    "test/storyarn/flows/versioning/integration/versioning_test.exs" => [
      "Storyarn.Projects.Versioning"
    ],
    "test/storyarn/flows/references/integration/writer_reference_integrity_test.exs" => [
      "Storyarn.Localization",
      "Storyarn.Projects",
      "Storyarn.Scenes"
    ],
    # The Flow editor mounts a project-owned conversation surface through its
    # public facade; this integration test checks authorization and event wiring.
    "test/storyarn_web/live/flow_live/comments_test.exs" => [
      "Storyarn.Projects"
    ],
    "test/storyarn_web/live/flow_live/player/player_live_test.exs" => [
      "Storyarn.Sheets"
    ]
  }

  # These are explicit composition seams, not permissions for feature tests to
  # reach into Flows. Keep every exception scoped to one file and one module.
  @integration_exceptions %{
    "test/storyarn/architecture/object_storage_lock_boundary_test.exs" => [
      "Storyarn.Flows.Versioning.Adapters.Storage.Locks",
      "Storyarn.Flows.Versioning.Adapters.Storage.Objects"
    ],
    "test/storyarn/architecture/flows_internal_structure_test.exs" => [
      "Storyarn.Flows.Versioning"
    ],
    "test/storyarn/architecture/flows_projection_associations_test.exs" => [
      "Storyarn.Flows.Editor.Projections.AssetRecord",
      "Storyarn.Flows.Editor.Projections.BlockRecord",
      "Storyarn.Flows.Editor.Projections.GalleryImageRecord",
      "Storyarn.Flows.Editor.Projections.SheetAvatarRecord",
      "Storyarn.Flows.Editor.Projections.SheetRecord",
      "Storyarn.Flows.Flow",
      "Storyarn.Flows.FlowConnection",
      "Storyarn.Flows.FlowNode",
      "Storyarn.Flows.References.Projections.AssetRecord",
      "Storyarn.Flows.References.Projections.BlockRecord",
      "Storyarn.Flows.References.Projections.SheetAvatarRecord",
      "Storyarn.Flows.References.Projections.SheetRecord",
      "Storyarn.Flows.References.Projections.TableColumnRecord",
      "Storyarn.Flows.References.Projections.TableRowRecord",
      "Storyarn.Flows.Runtime.Projections.AssetRecord",
      "Storyarn.Flows.Runtime.Projections.SheetAvatarRecord",
      "Storyarn.Flows.Runtime.Projections.SheetRecord",
      "Storyarn.Flows.SequenceConfig",
      "Storyarn.Flows.SequenceTrack",
      "Storyarn.Flows.SequenceVisualLayer",
      "Storyarn.Flows.VariableReference",
      "Storyarn.Flows.Versioning.Entities.AssetRecord",
      "Storyarn.Flows.Versioning.Projections.ProjectRecord",
      "Storyarn.Flows.Versioning.Projections.SheetAvatarRecord",
      "Storyarn.Flows.Versioning.Projections.SheetRecord",
      "Storyarn.Flows.Versioning.Projections.UserRecord",
      "Storyarn.Flows.Versioning.EntityVersionRecord"
    ],
    # Comments retain a tombstone when a Flow row is hard-deleted. Reusing the
    # exact ID and timestamp requires a deliberate persistence integration seam.
    "test/storyarn/projects/comments/integration/source_lifecycle_test.exs" => [
      "Storyarn.Flows.FlowNode"
    ],
    "test/storyarn/scenes/exploration/execution/formula_runtime_test.exs" => [
      "Storyarn.Flows.FormulaRuntime"
    ],
    "test/storyarn/sheets/versioning/execution/sheet_snapshot_contract_test.exs" => [
      "Storyarn.Flows.EntityTrashRefs"
    ],
    "test/storyarn_web/live/restore_containment_test.exs" => [
      "Storyarn.Flows.Versioning.RestorePolicy"
    ],
    "test/support/fixtures/flows_fixtures.ex" => [
      "Storyarn.Flows.Flow",
      "Storyarn.Flows.FlowNode",
      "Storyarn.Flows.SequenceTrack",
      "Storyarn.Flows.SequenceVisualLayer"
    ],
    "test/support/flows_ai_context_task.ex" => [
      "Storyarn.Flows.AI.ContextContract",
      "Storyarn.Flows.AI.DialogueContext",
      "Storyarn.Flows.AI.FlowNeighborhoodContext",
      "Storyarn.Flows.AI.SourceLocks"
    ]
  }

  @test_sources Enum.sort(Path.wildcard("test/**/*.ex") ++ Path.wildcard("test/**/*.exs"))

  test "only Flow-owned tests and exact integration seams reference Flow internals" do
    violations =
      @test_sources
      |> Enum.flat_map(&violations_in_file/1)
      |> Enum.sort()

    assert violations == [], """
    Tests outside the Flow bounded context may use the public Storyarn.Flows facade,
    but must not couple themselves to Flow internals. Move Flow-owned behavior under
    test/storyarn/flows or test/storyarn_web/live/flow_live; otherwise exercise the
    public facade or a consumer-owned read model:

    #{Enum.join(violations, "\n")}
    """
  end

  test "the classifier is fail-closed for fully qualified and locally aliased internals" do
    source = """
    defmodule ConsumerTest do
      alias Storyarn.Flows
      alias Storyarn.Flows.FlowNode

      def schema, do: Flows.Flow
    end
    """

    violations =
      "test/storyarn/sheets/consumer_test.exs"
      |> violations_in_source(source)
      |> Enum.sort()

    assert violations == [
             "test/storyarn/sheets/consumer_test.exs:3: Storyarn.Flows.FlowNode",
             "test/storyarn/sheets/consumer_test.exs:5: Storyarn.Flows.Flow"
           ]

    assert violations_in_source(
             "test/storyarn/sheets/public_integration_test.exs",
             "alias Storyarn.Flows"
           ) == []
  end

  test "Flow-owned tests keep an exact inventory of foreign context contracts" do
    actual =
      @test_sources
      |> Enum.filter(&flow_owned?/1)
      |> Map.new(&{&1, foreign_context_modules_in_file(&1)})
      |> Map.reject(fn {_path, modules} -> modules == [] end)

    assert actual == @flow_owned_integration_contracts, """
    Flow-owned tests may not acquire foreign context dependencies implicitly.
    Prefer Flow-owned persistence records and the public Storyarn.Flows facade.
    If a test genuinely verifies a cross-context contract, keep that test as an
    integration seam and add its exact modules to the reviewed inventory.

    Actual inventory:
    #{inspect(actual, pretty: true, limit: :infinity)}
    """
  end

  defp violations_in_file(path) do
    if flow_owned?(path) do
      []
    else
      violations_in_source(path, File.read!(path))
    end
  end

  defp violations_in_source(path, source) do
    ast = Code.string_to_quoted!(source, file: path, columns: true)
    facade_aliases = flow_facade_aliases(ast)

    alias_violations =
      ast
      |> module_aliases()
      |> Enum.filter(&internal_flow_alias?(&1.segments, facade_aliases))
      |> Enum.map(fn reference ->
        module = canonical_module(reference.segments, facade_aliases)
        %{line: reference.line, module: module}
      end)

    grouped_alias_violations =
      source
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {line, line_number} ->
        if Regex.match?(~r/\bStoryarn\.Flows\.\{/, line) do
          [%{line: line_number, module: String.trim(line)}]
        else
          []
        end
      end)

    (alias_violations ++ grouped_alias_violations)
    |> Enum.reject(&allowed_exception?(path, &1.module))
    |> Enum.uniq()
    |> Enum.map(&"#{path}:#{&1.line}: #{&1.module}")
  end

  defp foreign_context_modules_in_file(path) do
    ast = path |> File.read!() |> Code.string_to_quoted!(file: path, columns: true)
    local_aliases = local_module_aliases(ast)

    ast
    |> module_aliases()
    |> Enum.map(&canonical_reference(&1.segments, local_aliases))
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&foreign_context_module?/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp local_module_aliases(ast) do
    {_ast, aliases} =
      Macro.prewalk(ast, %{}, fn
        {:alias, _meta, [{:__aliases__, _, [:Storyarn | _rest] = segments} | options]} = node, aliases ->
          local_name = alias_name(segments, options)
          {node, Map.put(aliases, local_name, segments)}

        {:alias, _meta,
         [
           {{:., _, [{:__aliases__, _, [:Storyarn | _rest] = base}, :{}]}, _, children}
         ]} = node,
        aliases ->
          aliases =
            Enum.reduce(children, aliases, fn {:__aliases__, _, child}, acc ->
              Map.put(acc, List.last(child), base ++ child)
            end)

          {node, aliases}

        node, aliases ->
          {node, aliases}
      end)

    aliases
  end

  defp alias_name(segments, [options]) when is_list(options) do
    case Keyword.get(options, :as) do
      {:__aliases__, _, [name]} -> name
      _other -> List.last(segments)
    end
  end

  defp alias_name(segments, _options), do: List.last(segments)

  defp canonical_reference([:Storyarn | _rest] = segments, _aliases), do: Enum.join(segments, ".")

  defp canonical_reference([local_name | rest], aliases) do
    case Map.fetch(aliases, local_name) do
      {:ok, base} -> Enum.join(base ++ rest, ".")
      :error -> nil
    end
  end

  defp canonical_reference(_segments, _aliases), do: nil

  # The platform technical contracts remain allowed for every boundary
  # (mirrors globally_allowed_technical_targets in the ratchet config).
  defp foreign_context_module?("Storyarn.Platform.Shared" <> _rest), do: false
  defp foreign_context_module?("Storyarn.Platform.Collaboration" <> _rest), do: false
  defp foreign_context_module?("Storyarn.Platform.Dashboards.Cache" <> _rest), do: false
  defp foreign_context_module?("Storyarn.Platform.FeatureFlags" <> _rest), do: false
  defp foreign_context_module?("Storyarn.Platform.RateLimiter" <> _rest), do: false
  defp foreign_context_module?("Storyarn.Platform.Urls" <> _rest), do: false

  defp foreign_context_module?(module) do
    Enum.any?(@foreign_context_modules, fn root ->
      module == root or String.starts_with?(module, root <> ".")
    end)
  end

  defp flow_owned?(path), do: Enum.any?(@flow_owned_roots, &String.starts_with?(path, &1))

  defp flow_facade_aliases(ast) do
    {_ast, aliases} =
      Macro.prewalk(ast, MapSet.new([:Flows]), fn
        {:alias, _meta, [{:__aliases__, _, [:Storyarn, :Flows]} | opts]} = node, aliases ->
          alias_name =
            case Keyword.get(List.first(opts) || [], :as) do
              {:__aliases__, _, [name]} -> name
              _other -> :Flows
            end

          {node, MapSet.put(aliases, alias_name)}

        node, aliases ->
          {node, aliases}
      end)

    aliases
  end

  defp module_aliases(ast) do
    {_ast, aliases} =
      Macro.prewalk(ast, [], fn
        {:__aliases__, meta, segments} = node, aliases ->
          {node, [%{segments: segments, line: meta[:line]} | aliases]}

        node, aliases ->
          {node, aliases}
      end)

    aliases
  end

  defp internal_flow_alias?([:Storyarn, :Flows, _internal | _rest], _aliases), do: true

  defp internal_flow_alias?([local_alias, _internal | _rest], aliases), do: MapSet.member?(aliases, local_alias)

  defp internal_flow_alias?(_segments, _aliases), do: false

  defp canonical_module([:Storyarn, :Flows | rest], _aliases), do: Enum.join([:Storyarn, :Flows | rest], ".")

  defp canonical_module([_local_alias | rest], _aliases), do: Enum.join([:Storyarn, :Flows | rest], ".")

  defp allowed_exception?(path, module) do
    module in Map.get(@integration_exceptions, path, [])
  end
end
