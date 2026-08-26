defmodule Storyarn.Architecture.AIInternalStructureTest do
  use ExUnit.Case, async: true

  alias Storyarn.Architecture.DependencyPolicy

  @root "lib/storyarn/ai"
  @capability_roles %{
    "context" => ~w(adapters contracts execution rules),
    "governance" => ~w(adapters commands data entities events execution queries rules),
    "integrations" => ~w(adapters commands contracts data entities events execution queries rules),
    "managed_spend" => ~w(adapters commands contracts data entities execution queries rules),
    "operations" => ~w(adapters commands contracts data entities execution rules),
    "routing" => ~w(commands contracts data entities execution queries rules)
  }
  @private_roles ~w(adapters commands queries rules data execution events)
  @passive_roles ~w(contracts data entities rules)
  @root_facade_dependencies ~w(
    Storyarn.AI.Governance
    Storyarn.AI.Integrations
    Storyarn.AI.ManagedSpend
    Storyarn.AI.Operations
    Storyarn.AI.Routing
  )
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
    {"data", "commands"},
    {"data", "queries"},
    {"data", "execution"},
    {"data", "events"},
    {"data", "adapters"},
    {"data", "rules"},
    {"entities", "commands"},
    {"entities", "queries"},
    {"entities", "execution"},
    {"entities", "events"},
    {"entities", "adapters"},
    {"contracts", "commands"},
    {"contracts", "queries"},
    {"contracts", "execution"},
    {"contracts", "events"},
    {"contracts", "data"},
    {"events", "commands"},
    {"events", "queries"},
    {"events", "execution"},
    {"events", "adapters"},
    {"events", "rules"},
    {"adapters", "queries"},
    {"adapters", "execution"},
    {"adapters", "events"}
  ]

  test "AI has exactly the agreed capabilities and no loose implementation files" do
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

  test "the bounded-context facade composes only capability facades" do
    dependencies =
      ~r/^\s*alias\s+(Storyarn\.AI\.[A-Za-z0-9_.]+)/m
      |> Regex.scan(File.read!("lib/storyarn/ai.ex"), capture: :all_but_first)
      |> List.flatten()
      |> Enum.sort()

    assert dependencies == Enum.sort(@root_facade_dependencies)
  end

  test "query folders remain read-only application queries" do
    violations =
      @root
      |> Path.join("*/queries/**/*.ex")
      |> Path.wildcard()
      |> Enum.filter(fn path ->
        source = File.read!(path)

        source =~ ".Commands." or
          Regex.match?(
            ~r/\bRepo\.(?:insert|insert!|insert_all|update|update!|update_all|delete|delete!|delete_all|transact|transaction|rollback|query|query!)\b|\bEcto\.Multi\b|lock:\s*"FOR /,
            source
          )
      end)

    assert violations == [], "AI queries must remain read-only: #{inspect(violations)}"
  end

  test "passive roles do not perform persistence effects" do
    passive_sources =
      for capability <- Map.keys(@capability_roles),
          role <- @passive_roles,
          path <- Path.wildcard("#{@root}/#{capability}/#{role}/**/*.ex"),
          do: path

    violations =
      Enum.filter(passive_sources, fn path ->
        Regex.match?(
          ~r/\bRepo\.(?:insert|insert!|insert_all|update|update!|update_all|delete|delete!|delete_all|transact|transaction|rollback|query|query!)\b|\bEcto\.Multi\b|lock:\s*"FOR /,
          File.read!(path)
        )
      end)

    assert violations == [],
           "AI contracts, data, entities, and rules must stay free of persistence effects: #{inspect(violations)}"
  end

  test "every data module documents its projection or reference-data purpose" do
    data_sources = Path.wildcard(Path.join(@root, "*/data/**/*.ex"))

    violations =
      Enum.reject(data_sources, fn path ->
        source = File.read!(path)
        source =~ "@moduledoc" and not (source =~ "@moduledoc false")
      end)

    assert data_sources != []
    assert violations == [], "AI data semantics must be explicit: #{inspect(violations)}"
  end

  test "the ratchet blocks cross-capability access to private roles" do
    policy = DependencyPolicy.load!("config/architecture_boundaries.exs")

    Enum.each(Map.keys(@capability_roles), fn target_capability ->
      Enum.each(@private_roles, fn private_role ->
        assert denial?(
                 policy,
                 "lib/storyarn/ai.ex",
                 "#{@root}/#{target_capability}/#{private_role}/"
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

  test "the ratchet enforces direction between role folders" do
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

  test "rules may consume capability-local passive reference data" do
    policy = DependencyPolicy.load!("config/architecture_boundaries.exs")

    Enum.each(Map.keys(@capability_roles), fn capability ->
      refute denial?(
               policy,
               "#{@root}/#{capability}/rules/",
               "#{@root}/#{capability}/data/"
             ),
             "#{capability} rules must be able to read passive reference data"
    end)
  end

  test "AI workers can orchestrate through the root facade but not its internals" do
    policy = DependencyPolicy.load!("config/architecture_boundaries.exs")

    assert denial?(policy, "lib/storyarn/workers/ai/", "lib/storyarn/ai/")

    violations =
      "lib/storyarn/workers/ai/**/*.ex"
      |> Path.wildcard()
      |> Enum.flat_map(&internal_ai_references/1)
      |> Enum.sort()

    assert violations == [], "AI workers must call only Storyarn.AI: #{inspect(violations)}"
  end

  defp directories_in(path) do
    path
    |> File.ls!()
    |> Enum.filter(&File.dir?(Path.join(path, &1)))
    |> Enum.sort()
  end

  defp denial?(policy, source_root, target_root) do
    Enum.any?(policy.path_denials, fn denial ->
      denial.source_root == source_root and denial.target_root == target_root and
        denial.kinds == ["runtime", "export", "compile"]
    end)
  end

  defp internal_ai_references(path) do
    source = File.read!(path)
    ast = Code.string_to_quoted!(source, file: path, columns: true)

    {_ast, aliases} =
      Macro.prewalk(ast, [], fn
        {:__aliases__, meta, [:Storyarn, :AI, _internal | _rest] = segments} = node, aliases ->
          {node, ["#{path}:#{meta[:line]}: #{Enum.join(segments, ".")}" | aliases]}

        node, aliases ->
          {node, aliases}
      end)

    Enum.uniq(aliases)
  end
end
