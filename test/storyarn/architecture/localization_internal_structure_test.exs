defmodule Storyarn.Architecture.LocalizationInternalStructureTest do
  use ExUnit.Case, async: true

  alias Storyarn.Architecture.DependencyPolicy

  @root "lib/storyarn/localization"
  @capability_roles %{
    "access" => ~w(commands data queries rules),
    "exchange" => ~w(adapters commands queries rules),
    "glossary" => ~w(commands data entities execution queries),
    "languages" => ~w(adapters commands contracts data entities queries),
    "providers" => ~w(adapters commands contracts data entities queries),
    "reporting" => ~w(data queries),
    "texts" => ~w(adapters commands contracts data entities queries rules),
    "translation" => ~w(adapters commands data entities execution queries)
  }
  @private_roles ~w(adapters commands queries rules data execution)
  @passive_roles ~w(rules contracts entities data)
  @forbidden_role_edges [
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
  ]

  test "Localization has only the agreed capability folders and no loose implementation files" do
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

    assert violations == [], "Localization queries must remain read-only: #{inspect(violations)}"
  end

  test "rules, contracts, entities, and data modules do not perform persistence I/O" do
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
           "Localization passive roles must not perform persistence I/O: #{inspect(violations)}"
  end

  test "every data module documents its projection or reference-data purpose" do
    data_sources = Path.wildcard(Path.join(@root, "*/data/**/*.ex"))

    violations =
      Enum.reject(data_sources, fn path ->
        source = File.read!(path)
        source =~ "@moduledoc" and not (source =~ "@moduledoc false")
      end)

    assert violations == [], "Localization data semantics must be explicit: #{inspect(violations)}"
    assert File.read!(Path.join(@root, "README.md")) =~ "## `data/`"
  end

  test "provider, job, PubSub, and raw-SQL integrations live in adapters" do
    violations =
      @root
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.reject(&String.contains?(&1, "/adapters/"))
      |> Enum.filter(fn path ->
        Regex.match?(~r/\bReq\.|\bOban\.|Phoenix\.PubSub|\bRepo\.query!?\s*\(/, File.read!(path))
      end)

    assert violations == [],
           "Localization technical integrations must live under adapters/: #{inspect(violations)}"
  end

  test "the architecture ratchet blocks cross-capability access to private roles" do
    policy = DependencyPolicy.load!("config/architecture_boundaries.exs")

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

  test "Localization workers enter the context only through its root facade" do
    policy = DependencyPolicy.load!("config/architecture_boundaries.exs")

    assert denial?(
             policy,
             "lib/storyarn/workers/localization/",
             "lib/storyarn/localization/"
           )
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
