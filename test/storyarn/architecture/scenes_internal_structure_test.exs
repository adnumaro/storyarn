defmodule Storyarn.Architecture.ScenesInternalStructureTest do
  use ExUnit.Case, async: true

  alias Storyarn.Architecture.DependencyPolicy

  @root "lib/storyarn/scenes"
  @capability_roles %{
    "access" => ~w(projections queries),
    "assets" => ~w(adapters commands entities events projections queries),
    "editor" => ~w(adapters commands contracts projections entities queries rules),
    "exploration" => ~w(commands contracts projections entities events execution queries),
    "health" => ~w(contracts projections queries rules),
    "expressions" => ~w(compatibility contracts projections queries rules),
    "references" => ~w(commands projections queries records),
    "versioning" => ~w(adapters commands contracts projections entities events execution queries rules)
  }
  @private_roles ~w(adapters commands compatibility queries rules projections records execution events)
  @passive_roles ~w(rules contracts entities projections)
  @root_facade_dependencies ~w(
    Storyarn.Scenes.Access
    Storyarn.Scenes.Assets
    Storyarn.Scenes.Editor
    Storyarn.Scenes.Exploration
    Storyarn.Scenes.Health
    Storyarn.Scenes.Expressions
    Storyarn.Scenes.Scene
    Storyarn.Scenes.SceneAmbientFlow
    Storyarn.Scenes.SceneAnnotation
    Storyarn.Scenes.SceneConnection
    Storyarn.Scenes.SceneLayer
    Storyarn.Scenes.ScenePin
    Storyarn.Scenes.SceneZone
    Storyarn.Scenes.Versioning
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

  test "Scenes has exactly the agreed capabilities and no loose implementation files" do
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

  test "the bounded-context facade composes only capability facades and stable entities" do
    dependencies =
      ~r/^\s*alias\s+(Storyarn\.Scenes\.[A-Za-z0-9_.]+)/m
      |> Regex.scan(File.read!("lib/storyarn/scenes.ex"), capture: :all_but_first)
      |> List.flatten()
      |> Enum.sort()

    assert dependencies == Enum.sort(@root_facade_dependencies)
  end

  test "query folders cannot acquire writes, locks, or transaction orchestration" do
    violations =
      @root
      |> Path.join("*/queries/**/*.ex")
      |> Path.wildcard()
      |> Enum.filter(fn path ->
        source = File.read!(path)

        Regex.match?(
          ~r/\bRepo\.(?:insert|insert!|insert_all|update|update!|update_all|delete|delete!|delete_all|transact|transaction|rollback)\b|\bEcto\.Multi\b|lock:\s*"FOR /,
          source
        )
      end)

    assert violations == [], "Scene queries must remain read-only: #{inspect(violations)}"
  end

  test "projections, entities, contracts, and rules do not perform persistence I/O" do
    passive_sources =
      for capability <- Map.keys(@capability_roles),
          role <- @passive_roles,
          path <- Path.wildcard("#{@root}/#{capability}/#{role}/**/*.ex"),
          do: path

    violations =
      Enum.filter(passive_sources, fn path ->
        source = File.read!(path)
        source =~ "Storyarn.Repo" or source =~ "Ecto.Query" or Regex.match?(~r/\bRepo\./, source)
      end)

    assert violations == [],
           "Scene passive roles must not perform persistence I/O: #{inspect(violations)}"
  end

  test "every projection module documents its consumer-owned read purpose" do
    projection_sources = Path.wildcard(Path.join(@root, "*/projections/**/*.ex"))

    violations =
      Enum.reject(projection_sources, fn path ->
        source = File.read!(path)
        source =~ "@moduledoc" and not (source =~ "@moduledoc false")
      end)

    assert projection_sources != []
    assert violations == [], "Scene projections semantics must be explicit: #{inspect(violations)}"
    assert File.read!(Path.join(@root, "README.md")) =~ "## `projections/`"
  end

  test "raw SQL and shared object-storage contracts live only in adapters" do
    violations =
      @root
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.reject(&String.contains?(&1, "/adapters/"))
      |> Enum.filter(fn path ->
        Regex.match?(
          ~r/\bRepo\.query!?\s*\(|\bEcto\.Adapters\.SQL\b|\bStoryarn\.Projects\.Assets\.(?:Storage|StorageHash|StorageKeyLock)\b/,
          File.read!(path)
        )
      end)

    assert violations == [],
           "Scene SQL and storage integrations must live under adapters/: #{inspect(violations)}"
  end

  test "the architecture ratchet blocks cross-capability access to private roles" do
    policy = DependencyPolicy.load!("config/architecture_boundaries.exs")

    Enum.each(Map.keys(@capability_roles), fn target_capability ->
      Enum.each(@private_roles, fn private_role ->
        assert denial?(
                 policy,
                 "lib/storyarn/scenes.ex",
                 "#{@root}/#{target_capability}/#{private_role}/"
               ),
               "missing root-facade denial to #{target_capability}/#{private_role}"
      end)
    end)

    Enum.each(Map.keys(@capability_roles), fn source_capability ->
      Enum.each(Map.keys(@capability_roles) -- [source_capability], fn target_capability ->
        Enum.each(@private_roles, fn private_role ->
          assert denial?(
                   policy,
                   "#{@root}/#{source_capability}/",
                   "#{@root}/#{target_capability}/#{private_role}/"
                 ),
                 "missing private-role denial from #{source_capability} to #{target_capability}/#{private_role}"
        end)
      end)
    end)
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

  defp denial?(policy, source_root, target_root) do
    Enum.any?(policy.path_denials, fn denial ->
      denial.source_root == source_root and denial.target_root == target_root and
        denial.kinds == ["runtime", "export", "compile"]
    end)
  end
end
