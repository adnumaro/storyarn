defmodule Storyarn.Architecture.ProjectsInternalStructureTest do
  use ExUnit.Case, async: true

  alias Storyarn.Architecture.DependencyPolicy

  @root "lib/storyarn/projects"
  @capability_roles %{
    "access" => ~w(adapters commands delivery entities queries rules),
    "assets" => ~w(adapters commands contracts entities execution projections queries rules),
    "interchange" => ~w(exports imports),
    "lifecycle" => ~w(commands entities events projections queries reference_data rules),
    "overview" => ~w(contracts execution queries rules),
    "references" => ~w(adapters commands entities execution projections queries records reference_data rules),
    "templates" => ~w(adapters commands entities execution queries rules),
    "trash" => ~w(execution),
    "versioning" => ~w(adapters commands contracts entities execution projections queries rules)
  }
  @capability_root_files %{
    "access" => ~w(access.ex invitations.ex memberships.ex),
    "assets" => ~w(assets.ex project_assets.ex),
    "interchange" => ~w(interchange.ex),
    "lifecycle" => ~w(lifecycle.ex project_crud.ex),
    "overview" => ~w(overview.ex),
    "references" => ~w(references.ex),
    "templates" => ~w(project_templates.ex templates.ex),
    "trash" => ~w(trash.ex),
    "versioning" => ~w(versioning.ex)
  }
  @private_role_roots %{
    "access" => ~w(adapters commands delivery queries rules),
    "assets" => ~w(adapters commands execution projections queries rules),
    "interchange" => ~w(
      imports/adapters imports/commands imports/execution imports/queries imports/rules
      exports/adapters exports/queries exports/rules
    ),
    "lifecycle" => ~w(commands events projections queries reference_data rules),
    "overview" => ~w(execution queries rules),
    "references" => ~w(adapters commands execution projections queries records reference_data rules),
    "templates" => ~w(adapters commands execution queries rules),
    "trash" => ~w(execution),
    "versioning" => ~w(adapters commands execution projections queries rules)
  }
  @private_role_compatibility MapSet.new([
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
  @root_facade_dependencies ~w(
    Storyarn.Projects.Access
    Storyarn.Projects.Assets
    Storyarn.Projects.Assets.Asset
    Storyarn.Projects.Interchange
    Storyarn.Projects.Lifecycle
    Storyarn.Projects.Overview
    Storyarn.Projects.Project
    Storyarn.Projects.ProjectInvitation
    Storyarn.Projects.ProjectMembership
    Storyarn.Projects.ProjectTrash
    Storyarn.Projects.References
    Storyarn.Projects.SnapshotAccounting
    Storyarn.Projects.Templates
    Storyarn.Projects.Trash
    Storyarn.Projects.Versioning
  )
  @role_scopes ~w(lifecycle access assets overview trash references templates versioning) ++
                 ~w(interchange/imports interchange/exports)
  @forbidden_role_edges [
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
  ]
  @role_compatibility MapSet.new([
                        {"interchange/exports", "contracts", "adapters"},
                        {"interchange/exports", "rules", "adapters"},
                        {"interchange/imports", "rules", "adapters"}
                      ])

  test "Projects exposes the nine agreed capabilities with their role layout" do
    assert directories_in(@root) ==
             @capability_roles
             |> Map.keys()
             |> Kernel.++(["content", "reconstitution"])
             |> Enum.sort()

    Enum.each(@capability_roles, fn {capability, expected_roles} ->
      capability_root = Path.join(@root, capability)

      assert File.dir?(capability_root), "missing Projects capability: #{capability}"
      assert directories_in(capability_root) == Enum.sort(expected_roles)

      assert root_files_in(capability_root) ==
               @capability_root_files |> Map.fetch!(capability) |> Enum.sort()
    end)
  end

  test "reconstitution is a closed internal boundary, not a tenth capability facade" do
    reconstitution_root = Path.join(@root, "reconstitution")

    assert File.dir?(reconstitution_root)
    assert directories_in(reconstitution_root) == []
    assert root_files_in(reconstitution_root) == ["project_reconstitution.ex"]
    refute File.exists?(Path.join(@root, "reconstitution.ex"))
    refute File.exists?(Path.join(reconstitution_root, "reconstitution.ex"))

    source = File.read!(Path.join(reconstitution_root, "project_reconstitution.ex"))

    assert source =~ ~r/^defmodule Storyarn\.Projects\.ProjectReconstitution do/m
    refute File.read!("lib/storyarn/projects.ex") =~ "Storyarn.Projects.ProjectReconstitution"
  end

  test "variable reference projection writer stays write-only" do
    writer =
      File.read!(Path.join(@root, "references/commands/variable_reference_tracker.ex"))

    assert writer =~ "def rebuild_project_variable_references("
    assert writer =~ "def update_references("
    assert writer =~ "def update_scene_pin_references("
    assert writer =~ "def update_scene_zone_references("
    assert writer =~ "def update_scene_ambient_flow_references("

    for forbidden <- [
          "def get_variable_usage(",
          "def count_variable_usage(",
          "def count_stale_references(",
          "def check_stale_references(",
          "def list_stale_node_ids(",
          "def validate_snapshot_variable_references(",
          "def prepare_portable_project_snapshot(",
          "def rewrite_portable_project_snapshot("
        ] do
      refute writer =~ forbidden,
             "variable reference writer regained non-write responsibility: #{forbidden}"
    end
  end

  test "reference rules remain persistence-free" do
    sources =
      @root
      |> Path.join("references/rules/*.ex")
      |> Path.wildcard()
      |> Enum.sort()

    assert sources != [], "reference-rules ratchet matched no Elixir sources"

    for path <- sources do
      source = File.read!(path)

      refute source =~ "alias Storyarn.Repo",
             "reference rule acquired a Repo dependency: #{path}"

      refute source =~ "import Ecto.Query",
             "reference rule acquired query composition: #{path}"

      refute source =~ ~r/\bRepo\.(?:all|one|insert|insert!|insert_all|update|update!|delete|delete_all|transaction)\b/,
             "reference rule acquired persistence behavior: #{path}"
    end
  end

  test "content is a closed internal model, not a capability or public facade" do
    content_root = Path.join(@root, "content")

    assert File.dir?(content_root)
    refute File.exists?(Path.join(@root, "content.ex"))
    refute File.exists?(Path.join(content_root, "content.ex"))

    violations =
      content_root
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.filter(&(File.read!(&1) =~ ~r/^defmodule Storyarn\.Projects\.Content do/m))

    assert violations == [], "content/ must not acquire a capability facade: #{inspect(violations)}"

    for tool <- ~w(flows sheets scenes localization) do
      assert File.dir?(Path.join([content_root, tool, "records"])),
             "#{tool} content records must be explicit and must not live under Overview"
    end

    refute File.dir?(Path.join([@root, "overview", "data"]))
  end

  test "persistence-shaped folders never fall back to generic data" do
    generic_data_directories = Path.wildcard(Path.join(@root, "**/data"))

    assert generic_data_directories == [],
           "Projects must classify SQL models and catalogs explicitly: #{inspect(generic_data_directories)}"
  end

  test "Projects projections remain passive read mappings" do
    projection_sources = Path.wildcard(Path.join(@root, "*/projections/**/*.ex"))

    violations =
      Enum.filter(projection_sources, fn path ->
        source = File.read!(path)

        source =~ "Storyarn.Repo" or source =~ "Ecto.Query" or
          Regex.match?(~r/\bRepo\./, source) or
          Regex.match?(~r/^\s*def\s+\w*changeset\b/m, source)
      end)

    assert projection_sources != []

    assert violations == [],
           "Projects projections must remain read-only; move writable mappings to records/: #{inspect(violations)}"
  end

  test "the root facade is declarative and names only capability facades or stable public types" do
    source = File.read!("lib/storyarn/projects.ex")

    dependencies = project_module_references(source, "lib/storyarn/projects.ex")

    assert dependencies == Enum.sort(@root_facade_dependencies)

    refute source =~ ~r/^\s*defp?\s/m,
           "Storyarn.Projects must remain a declarative facade made of delegates"
  end

  test "the root facade ratchet resolves nested targets through local aliases" do
    source = """
    alias Storyarn.Projects.Versioning
    defdelegate hidden(arg), to: Versioning.ReferencedTombstones
    """

    assert "Storyarn.Projects.Versioning.ReferencedTombstones" in project_module_references(
             source,
             "synthetic_projects_facade.ex"
           )
  end

  test "every closed content model is integrated in at least two Project areas" do
    content_modules =
      @root
      |> Path.join("content/**/*.ex")
      |> Path.wildcard()
      |> Map.new(fn path -> {defined_module(path), path} end)

    consumers =
      @root
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.reduce(Map.new(content_modules, fn {module, _path} -> {module, MapSet.new()} end), fn path, acc ->
        case project_area(path) do
          nil ->
            acc

          area ->
            path
            |> File.read!()
            |> project_module_references(path)
            |> Enum.reduce(acc, fn module, references ->
              if Map.has_key?(references, module) and Map.fetch!(content_modules, module) != path do
                Map.update!(references, module, &MapSet.put(&1, area))
              else
                references
              end
            end)
        end
      end)

    violations =
      consumers
      |> Enum.filter(fn {_module, capabilities} -> MapSet.size(capabilities) < 2 end)
      |> Enum.map(fn {module, capabilities} ->
        {module, Map.fetch!(content_modules, module), capabilities |> MapSet.to_list() |> Enum.sort()}
      end)
      |> Enum.sort()

    assert violations == [],
           "content/ modules must serve at least two Project areas: #{inspect(violations)}"
  end

  test "historical module identities survive their physical relocation" do
    refute File.dir?(Path.join(@root, "persistence"))
    refute File.dir?(Path.join(@root, "imports"))
    refute File.dir?(Path.join(@root, "exports"))
    refute File.dir?(Path.join(@root, "project_templates"))

    assert Code.ensure_loaded?(Storyarn.Projects.Persistence.BlockRecord)
    assert Code.ensure_loaded?(Storyarn.Projects.Persistence.ProjectLanguageRecord)
    assert Code.ensure_loaded?(Storyarn.Projects.Persistence.SceneRecord)
    assert Code.ensure_loaded?(Storyarn.Projects.Assets.Persistence.FlowRecord)
    assert Code.ensure_loaded?(Storyarn.Projects.References.Persistence.BlockRecord)
    assert Code.ensure_loaded?(Storyarn.Projects.Imports)
    assert Code.ensure_loaded?(Storyarn.Projects.Exports)
    assert Code.ensure_loaded?(Storyarn.Projects.ProjectTemplates)
  end

  test "the ratchet closes every unreviewed cross-capability private role" do
    policy = DependencyPolicy.load!("config/architecture_boundaries.exs")
    capabilities = Map.keys(@capability_roles)

    for source <- capabilities,
        target <- capabilities -- [source],
        private_role_root <- Map.fetch!(@private_role_roots, target) do
      denied? =
        denial?(
          policy,
          "#{@root}/#{source}/",
          "#{@root}/#{target}/#{private_role_root}/",
          ["runtime", "export", "compile"]
        )

      assert denied? != MapSet.member?(@private_role_compatibility, {source, target, private_role_root}),
             "#{source} -> #{target}/#{private_role_root} must be either denied or explicitly retained, never both"
    end
  end

  test "the ratchet preserves the established direction between role folders" do
    policy = DependencyPolicy.load!("config/architecture_boundaries.exs")

    for scope <- @role_scopes,
        {source_role, target_role} <- @forbidden_role_edges do
      denied? =
        denial?(
          policy,
          "#{@root}/#{scope}/#{source_role}/",
          "#{@root}/#{scope}/#{target_role}/",
          ["runtime", "export", "compile"]
        )

      assert denied? != MapSet.member?(@role_compatibility, {scope, source_role, target_role}),
             "#{scope}/#{source_role} -> #{target_role} must be either denied or explicitly retained, never both"
    end
  end

  test "root, Web, and workers cannot bypass the closed content model" do
    policy = DependencyPolicy.load!("config/architecture_boundaries.exs")

    assert denial?(
             policy,
             "lib/storyarn/projects.ex",
             "lib/storyarn/projects/content/",
             ["runtime", "export", "compile"]
           )

    assert denial?(
             policy,
             "lib/storyarn/workers/projects/",
             "lib/storyarn/projects/",
             ["runtime", "export", "compile"]
           )

    assert Enum.any?(policy.path_denials, fn denial ->
             String.starts_with?(denial.source_root, "lib/storyarn_web/") and
               denial.target_root == "lib/storyarn/projects/"
           end)
  end

  test "Project workers call only the bounded-context facade" do
    violations =
      "lib/storyarn/workers/projects/**/*.ex"
      |> Path.wildcard()
      |> Enum.flat_map(&internal_project_references/1)
      |> Enum.sort()

    assert violations == [], "Project workers must call only Storyarn.Projects: #{inspect(violations)}"
  end

  defp defined_module(path) do
    [module] =
      Regex.run(
        ~r/^defmodule\s+(Storyarn\.Projects\.[A-Za-z0-9_.]+)\s+do/m,
        File.read!(path),
        capture: :all_but_first
      )

    module
  end

  defp project_capability(path) do
    case path |> Path.relative_to(@root) |> Path.split() do
      [capability | _rest] ->
        if Map.has_key?(@capability_roles, capability), do: capability

      _other ->
        nil
    end
  end

  defp project_area(path) do
    case path |> Path.relative_to(@root) |> Path.split() do
      ["content" | _rest] -> "content"
      _other -> project_capability(path)
    end
  end

  defp project_module_references(source, file_path) do
    ast = Code.string_to_quoted!(source, file: file_path, columns: true)
    aliases = project_aliases(ast)

    {_ast, references} =
      Macro.prewalk(ast, MapSet.new(), fn
        {:__aliases__, _metadata, segments} = node, references ->
          case resolve_project_alias(segments, aliases) do
            [:Storyarn, :Projects, _internal | _rest] = resolved ->
              {node, MapSet.put(references, module_name(resolved))}

            _other ->
              {node, references}
          end

        node, references ->
          {node, references}
      end)

    references |> MapSet.to_list() |> Enum.sort()
  end

  defp project_aliases(ast) do
    {_ast, aliases} =
      Macro.prewalk(ast, %{}, fn
        {:alias, _metadata,
         [
           {{:., _, [{:__aliases__, _, base_segments}, :{}]}, _, grouped_aliases}
         ]} = node,
        aliases ->
          aliases =
            if project_module_segments?(base_segments) do
              put_grouped_project_aliases(aliases, base_segments, grouped_aliases)
            else
              aliases
            end

          {node, aliases}

        {:alias, _metadata, [{:__aliases__, _, segments} | options]} = node, aliases ->
          aliases =
            if project_module_segments?(segments) do
              Map.put(aliases, alias_name(options, segments), segments)
            else
              aliases
            end

          {node, aliases}

        node, aliases ->
          {node, aliases}
      end)

    aliases
  end

  defp put_grouped_project_aliases(aliases, base_segments, grouped_aliases) do
    Enum.reduce(grouped_aliases, aliases, fn {:__aliases__, _, segments}, acc ->
      Map.put(acc, List.last(segments), base_segments ++ segments)
    end)
  end

  defp resolve_project_alias([:Storyarn, :Projects | _rest] = segments, _aliases), do: segments
  defp resolve_project_alias([:Projects | rest], _aliases), do: [:Storyarn, :Projects | rest]

  defp resolve_project_alias([local_name | rest], aliases) do
    case Map.fetch(aliases, local_name) do
      {:ok, base_segments} -> base_segments ++ rest
      :error -> nil
    end
  end

  defp resolve_project_alias(_segments, _aliases), do: nil

  defp project_module_segments?([:Storyarn, :Projects | _rest]), do: true
  defp project_module_segments?(_segments), do: false

  defp alias_name([[as: {:__aliases__, _, segments}]], _default_segments), do: List.last(segments)
  defp alias_name(_options, default_segments), do: List.last(default_segments)

  defp module_name(segments), do: Enum.join(segments, ".")

  defp directories_in(path) do
    path
    |> File.ls!()
    |> Enum.filter(&File.dir?(Path.join(path, &1)))
    |> Enum.sort()
  end

  defp root_files_in(path) do
    path
    |> File.ls!()
    |> Enum.filter(&File.regular?(Path.join(path, &1)))
    |> Enum.sort()
  end

  defp denial?(policy, source_root, target_root, kinds) do
    Enum.any?(policy.path_denials, fn denial ->
      denial.source_root == source_root and denial.target_root == target_root and denial.kinds == kinds
    end)
  end

  defp internal_project_references(path) do
    source = File.read!(path)
    project_module_references(source, path)
  end
end
