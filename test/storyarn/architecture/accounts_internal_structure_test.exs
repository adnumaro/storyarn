defmodule Storyarn.Architecture.AccountsInternalStructureTest do
  use ExUnit.Case, async: true

  alias Storyarn.Architecture.DependencyPolicy

  @root "lib/storyarn/accounts"
  @capability_roles %{
    "authentication" => ~w(adapters commands contracts delivery entities events queries rules tokens),
    "identity" => ~w(adapters commands entities queries),
    "registration" => ~w(commands events queries rules tokens)
  }
  @private_roles ~w(adapters commands queries rules delivery tokens events)
  @forbidden_role_edges [
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
  ]

  test "Accounts has only the agreed capability folders and no loose implementation files" do
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
    query_sources = Path.wildcard(Path.join(@root, "*/queries/**/*.ex"))

    violations =
      Enum.filter(query_sources, fn path ->
        source = File.read!(path)

        Regex.match?(
          ~r/\bRepo\.(?:insert|insert!|insert_all|update|update!|update_all|delete|delete!|delete_all|transact|transaction|rollback)\b|\bEcto\.Multi\b|lock:\s*"FOR UPDATE"/,
          source
        )
      end)

    assert violations == [], "Account query modules must remain read-only: #{inspect(violations)}"
  end

  test "rule folders cannot query or mutate persistence" do
    rule_sources = Path.wildcard(Path.join(@root, "*/rules/**/*.ex"))

    violations =
      Enum.filter(rule_sources, fn path ->
        source = File.read!(path)

        source =~ "Storyarn.Repo" or source =~ "Ecto.Query" or
          Regex.match?(~r/\bRepo\./, source)
      end)

    assert violations == [], "Account rules must not depend on persistence: #{inspect(violations)}"
  end

  test "the architecture ratchet blocks cross-capability access to private role folders" do
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

  test "Account workers can enter the context only through its root facade" do
    policy = DependencyPolicy.load!("config/architecture_boundaries.exs")

    assert denial?(
             policy,
             "lib/storyarn/workers/accounts/",
             "lib/storyarn/accounts/"
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
