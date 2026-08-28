defmodule Storyarn.Architecture.FlowsInternalStructureTest do
  use ExUnit.Case, async: true

  alias Storyarn.Architecture.DependencyPolicy

  @root "lib/storyarn/flows"
  @capability_roles %{
    "ai" => ~w(commands contracts projections execution queries),
    "editor" => ~w(adapters commands contracts projections entities events queries rules),
    "health" => ~w(adapters projections execution queries rules),
    "localization" => ~w(adapters commands contracts projections records rules),
    "expressions" => ~w(compatibility contracts projections queries rules),
    "references" => ~w(commands projections records entities queries rules),
    "runtime" => ~w(adapters projections entities events execution queries rules),
    "versioning" => ~w(adapters commands contracts projections records entities events execution queries rules)
  }
  @private_roles ~w(adapters commands compatibility queries rules projections records execution events)
  @passive_roles ~w(projections entities contracts rules)
  @capability_facade_dependencies ~w(
    Storyarn.Flows.AI
    Storyarn.Flows.Editor
    Storyarn.Flows.Health
    Storyarn.Flows.Localization
    Storyarn.Flows.Expressions
    Storyarn.Flows.References
    Storyarn.Flows.Runtime
    Storyarn.Flows.Versioning
  )
  @stable_type_dependencies ~w(
    Storyarn.Flows.EditorCatalog
    Storyarn.Flows.FlowNode
    Storyarn.Flows.StructuralAnalysis.Analysis
    Storyarn.Flows.VariableSearch
  )
  @root_facade_targets ~w(AI Editor Health Localization Expressions References Runtime Versioning)
  @versioning_facade_contract [
    build_snapshot: 1,
    build_version_snapshot: 1,
    can_create_named_version?: 2,
    count_versions: 1,
    count_versions: 2,
    count_versions_since: 2,
    count_versions_since: 3,
    create_named_version: 3,
    create_version: 2,
    create_version: 3,
    create_version: 4,
    create_version: 5,
    delete_version: 1,
    detect_restore_conflicts: 2,
    detect_restore_conflicts: 3,
    detect_version_restore_conflicts: 2,
    ensure_restore_enabled: 0,
    ensure_restore_enabled: 1,
    ensure_version_restore_enabled: 0,
    get_adjacent_version_numbers: 2,
    get_adjacent_version_numbers: 3,
    get_builder!: 1,
    get_latest_version: 1,
    get_latest_version: 2,
    get_version: 2,
    get_version: 3,
    list_versions: 1,
    list_versions: 2,
    list_versions: 3,
    load_version_snapshot: 1,
    maybe_create_version: 2,
    maybe_create_version: 3,
    maybe_create_version: 4,
    maybe_create_version: 5,
    next_version_number: 1,
    prepare_restore: 2,
    prepare_restore_conflicts: 2,
    prepare_version_restore: 2,
    prepare_version_restore_conflicts: 2,
    record_version_compared: 2,
    record_version_panel_opened: 2,
    restore_enabled?: 0,
    restore_enabled?: 1,
    restore_tracked_version: 4,
    restore_version: 2,
    restore_version: 3,
    restore_version: 4,
    serialize_version_snapshot: 1,
    set_current_version: 2,
    snapshot_has_changes?: 2,
    snapshot_has_changes?: 3,
    update_version: 2,
    version_snapshot_has_changes?: 2
  ]
  @forbidden_role_edges [
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
  ]
  @write_functions ~w(
    delete delete! delete_all insert insert! insert_all rollback transact transaction
    update update! update_all
  )a

  test "Flows has exactly the agreed capabilities and no loose implementation files" do
    assert directories_in(@root) == @capability_roles |> Map.keys() |> Enum.sort()
    assert Path.wildcard(Path.join(@root, "*.ex")) == []
  end

  test "each capability keeps only its facade at the capability root" do
    Enum.each(@capability_roles, fn {capability, expected_roles} ->
      capability_root = Path.join(@root, capability)

      assert directories_in(capability_root) == Enum.sort(expected_roles),
             "#{capability} must use its agreed role folders"

      assert Path.wildcard(Path.join(capability_root, "*.ex")) == [
               Path.join(capability_root, "#{capability}.ex")
             ],
             "#{capability} may keep only its capability facade outside a role folder"
    end)
  end

  test "the bounded-context facade is declarative and executes only through capability facades" do
    source = File.read!("lib/storyarn/flows.ex")

    dependencies =
      ~r/^\s*alias\s+(Storyarn\.Flows\.[A-Za-z0-9_.]+)/m
      |> Regex.scan(source, capture: :all_but_first)
      |> List.flatten()
      |> Enum.sort()

    assert dependencies == Enum.sort(@capability_facade_dependencies ++ @stable_type_dependencies)

    assert implementation_definitions(source) == [],
           "Storyarn.Flows must remain a declarative facade made of delegates"

    delegate_targets = delegate_targets(source)

    assert delegate_targets != []
    assert delegate_targets |> Enum.uniq() |> Enum.sort() == Enum.sort(@root_facade_targets)
  end

  test "the Versioning capability facade remains declarative and preserves its contract" do
    source = File.read!("lib/storyarn/flows/versioning/versioning.ex")

    assert implementation_definitions(source) == [],
           "Storyarn.Flows.Versioning must remain a declarative facade made of delegates"

    assert source
           |> delegate_targets()
           |> Enum.uniq()
           |> Enum.sort() ==
             Enum.sort(~w(History NamedVersionCapacity Restore SnapshotReader SnapshotViewer Tracked VersionLifecycle))

    assert :functions |> Storyarn.Flows.Versioning.__info__() |> Enum.sort() ==
             Enum.sort(@versioning_facade_contract)
  end

  test "query folders cannot acquire writes, locks, or transaction orchestration" do
    violations =
      @root
      |> Path.join("*/queries/**/*.ex")
      |> Path.wildcard()
      |> Enum.filter(&query_effectful?/1)

    assert violations == [], "Flow queries must remain read-only: #{inspect(violations)}"
  end

  test "provider-specific SQL and Platform object storage stay behind capability adapters" do
    violations =
      @root
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.reject(&String.contains?(&1, "/adapters/"))
      |> Enum.filter(fn path ->
        Regex.match?(
          ~r/\bRepo\.query!?\s*\(|\bStoryarn\.Projects\.Assets\.(?:Storage|StorageHash|StorageKeyLock)\b|\bStoryarn\.Platform\.ObjectStorage\b/,
          File.read!(path)
        )
      end)

    assert violations == [],
           "Flow SQL and storage integrations must live under adapters/: #{inspect(violations)}"
  end

  test "passive roles cannot hide provider-specific query fragments" do
    passive_sources =
      for capability <- Map.keys(@capability_roles),
          role <- @passive_roles,
          path <- Path.wildcard("#{@root}/#{capability}/#{role}/**/*.ex"),
          do: path

    violations =
      Enum.filter(passive_sources, fn path ->
        File.read!(path) =~ ~r/\bfragment\s*\(/
      end)

    assert violations == [],
           "Flow passive roles must not construct provider-specific query fragments: #{inspect(violations)}"
  end

  test "projections, entities, contracts, and rules remain passive" do
    passive_sources =
      for capability <- Map.keys(@capability_roles),
          role <- @passive_roles,
          path <- Path.wildcard("#{@root}/#{capability}/#{role}/**/*.ex"),
          do: path

    violations = Enum.filter(passive_sources, &persistence_io?/1)

    assert violations == [],
           "Flow passive roles must not perform persistence I/O: #{inspect(violations)}"
  end

  test "every projection module documents its consumer-owned read purpose" do
    projection_sources = Path.wildcard(Path.join(@root, "*/projections/**/*.ex"))

    violations =
      Enum.reject(projection_sources, fn path ->
        source = File.read!(path)
        source =~ "@moduledoc" and not (source =~ "@moduledoc false")
      end)

    assert projection_sources != []
    assert violations == [], "Flow projections semantics must be explicit: #{inspect(violations)}"
    assert File.read!(Path.join(@root, "README.md")) =~ "## `projections/`"
  end

  test "the architecture ratchet blocks root and cross-capability access to private roles" do
    policy = DependencyPolicy.load!("config/architecture_boundaries.exs")

    Enum.each(Map.keys(@capability_roles), fn target_capability ->
      Enum.each(@private_roles, fn private_role ->
        assert denial?(
                 policy,
                 "lib/storyarn/flows.ex",
                 "#{@root}/#{target_capability}/#{private_role}/",
                 ["runtime", "compile"]
               ),
               "missing root-facade denial to #{target_capability}/#{private_role}"
      end)
    end)

    for source_capability <- Map.keys(@capability_roles),
        target_capability <- Map.keys(@capability_roles) -- [source_capability],
        private_role <- @private_roles do
      assert denial?(
               policy,
               "#{@root}/#{source_capability}/",
               "#{@root}/#{target_capability}/#{private_role}/"
             ),
             "missing private-role denial from #{source_capability} to #{target_capability}/#{private_role}"
    end
  end

  test "the architecture ratchet enforces direction between role folders" do
    policy = DependencyPolicy.load!("config/architecture_boundaries.exs")

    Enum.each(Map.keys(@capability_roles), fn capability ->
      Enum.each(@forbidden_role_edges, fn {source_role, target_role} ->
        assert denial?(
                 policy,
                 "#{@root}/#{capability}/#{source_role}/",
                 "#{@root}/#{capability}/#{target_role}/"
               ),
               "missing role-direction denial for #{capability}/#{source_role} -> #{target_role}"
      end)
    end)
  end

  defp directories_in(path) do
    path
    |> File.ls!()
    |> Enum.filter(&File.dir?(Path.join(path, &1)))
    |> Enum.sort()
  end

  defp implementation_definitions(source) do
    source
    |> Code.string_to_quoted!(file: "lib/storyarn/flows.ex", columns: true)
    |> collect_ast_nodes(fn
      {kind, meta, _arguments} when kind in ~w(def defp defmacro defmacrop defguard defguardp)a ->
        {:match, {kind, meta[:line]}}

      _node ->
        :skip
    end)
  end

  defp delegate_targets(source) do
    source
    |> Code.string_to_quoted!(file: "lib/storyarn/flows.ex", columns: true)
    |> collect_ast_nodes(fn
      {:defdelegate, _meta, [_call, options]} when is_list(options) ->
        {:match, options |> Keyword.fetch!(:to) |> Macro.to_string()}

      _node ->
        :skip
    end)
  end

  defp query_effectful?(path) do
    ast = path |> File.read!() |> Code.string_to_quoted!(file: path, columns: true)

    ast
    |> collect_ast_nodes(fn
      {{:., _meta, [receiver, function]}, _call_meta, _arguments}
      when function in @write_functions ->
        if repo_alias?(receiver), do: {:match, function}, else: :skip

      {:__aliases__, _meta, [:Ecto, :Multi | _rest]} ->
        {:match, :ecto_multi}

      {:lock, _meta, arguments} when is_list(arguments) ->
        if Enum.any?(arguments, &for_update_lock?/1), do: {:match, :write_lock}, else: :skip

      {:lock, value} when is_binary(value) ->
        if for_update_lock?(value), do: {:match, :write_lock}, else: :skip

      _node ->
        :skip
    end)
    |> Enum.any?()
  end

  defp persistence_io?(path) do
    ast = path |> File.read!() |> Code.string_to_quoted!(file: path, columns: true)

    ast
    |> collect_ast_nodes(fn
      {:__aliases__, _meta, [:Storyarn, :Repo]} -> {:match, :repo}
      {:__aliases__, _meta, [:Repo]} -> {:match, :repo}
      {:__aliases__, _meta, [:Ecto, :Query | _rest]} -> {:match, :ecto_query}
      {:__aliases__, _meta, [:Ecto, :Multi | _rest]} -> {:match, :ecto_multi}
      _node -> :skip
    end)
    |> Enum.any?()
  end

  defp collect_ast_nodes(ast, classifier) do
    {_ast, matches} =
      Macro.prewalk(ast, [], fn node, matches ->
        case classifier.(node) do
          {:match, match} -> {node, [match | matches]}
          :skip -> {node, matches}
        end
      end)

    Enum.reverse(matches)
  end

  defp repo_alias?({:__aliases__, _meta, [:Repo]}), do: true
  defp repo_alias?({:__aliases__, _meta, [:Storyarn, :Repo]}), do: true
  defp repo_alias?(_receiver), do: false

  defp for_update_lock?(value) when is_binary(value), do: String.starts_with?(value, "FOR ")
  defp for_update_lock?(_value), do: false

  defp denial?(policy, source_root, target_root, kinds \\ ["runtime", "export", "compile"]) do
    Enum.any?(policy.path_denials, fn denial ->
      denial.source_root == source_root and denial.target_root == target_root and
        denial.kinds == kinds
    end)
  end
end
