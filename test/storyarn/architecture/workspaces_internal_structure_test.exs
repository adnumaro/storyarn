defmodule Storyarn.Architecture.WorkspacesInternalStructureTest do
  use ExUnit.Case, async: true

  alias Storyarn.Architecture.DependencyPolicy

  @root "lib/storyarn/workspaces"
  @capability_roles %{
    "banner" => ~w(adapters commands queries rules),
    "invitations" => ~w(adapters commands delivery entities projections queries rules tokens),
    "lifecycle" => ~w(commands entities events projections queries reference_data rules),
    "memberships" => ~w(commands entities projections queries rules)
  }
  @root_files %{
    "banner" => ~w(banner.ex),
    "invitations" => ~w(invitations.ex),
    "lifecycle" => ~w(lifecycle.ex),
    "memberships" => ~w(memberships.ex)
  }
  @private_roles ~w(adapters commands delivery events projections queries reference_data rules tokens)
  @forbidden_role_edges [
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
  ]
  @query_adapter_denied_capabilities ~w(invitations lifecycle memberships)

  test "Workspaces has only the agreed capability folders and no loose implementation files" do
    assert directories_in(@root) == @capability_roles |> Map.keys() |> Enum.sort()
    assert Path.wildcard(Path.join(@root, "*.ex")) == []
  end

  test "each capability keeps only its facade at the capability root" do
    Enum.each(@capability_roles, fn {capability, expected_roles} ->
      capability_root = Path.join(@root, capability)

      assert directories_in(capability_root) == Enum.sort(expected_roles),
             "#{capability} must use its agreed role folders"

      actual_root_files =
        capability_root
        |> Path.join("*.ex")
        |> Path.wildcard()
        |> Enum.map(&Path.basename/1)
        |> Enum.sort()

      assert actual_root_files == Enum.sort(Map.fetch!(@root_files, capability)),
             "#{capability} may keep only its agreed public entry points outside a role folder"
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

    assert violations == [], "Workspace query modules must remain read-only: #{inspect(violations)}"
  end

  test "rule folders cannot query or mutate persistence" do
    rule_sources = Path.wildcard(Path.join(@root, "*/rules/**/*.ex"))

    violations =
      Enum.filter(rule_sources, fn path ->
        source = File.read!(path)

        source =~ "Storyarn.Repo" or source =~ "Ecto.Query" or
          Regex.match?(~r/\bRepo\./, source)
      end)

    assert violations == [], "Workspace rules must not depend on persistence: #{inspect(violations)}"
  end

  test "projections and reference data remain passive without I/O" do
    passive_data_sources =
      Enum.flat_map(~w(projections reference_data), fn role ->
        Path.wildcard(Path.join(@root, "*/#{role}/**/*.ex"))
      end)

    violations =
      Enum.filter(passive_data_sources, fn path ->
        source = File.read!(path)
        source =~ "Storyarn.Repo" or source =~ "Ecto.Query" or Regex.match?(~r/\bRepo\./, source)
      end)

    assert violations == [],
           "Workspace passive-data modules must not perform persistence I/O: #{inspect(violations)}"
  end

  test "every projection and reference-data module documents its purpose" do
    passive_data_sources =
      Enum.flat_map(~w(projections reference_data), fn role ->
        Path.wildcard(Path.join(@root, "*/#{role}/**/*.ex"))
      end)

    violations =
      Enum.reject(passive_data_sources, fn path ->
        path |> File.read!() |> String.contains?("@moduledoc \"\"\"")
      end)

    assert violations == [],
           "Workspace passive-data semantics must be explicit: #{inspect(violations)}"

    assert File.read!(Path.join(@root, "README.md")) =~ "## Projections and reference data"
  end

  test "the architecture ratchet blocks cross-capability access to private role folders" do
    policy = DependencyPolicy.load!("config/architecture_boundaries.exs")

    Enum.each(Map.keys(@capability_roles), fn source_capability ->
      Enum.each(Map.keys(@capability_roles) -- [source_capability], fn target_capability ->
        Enum.each(@private_roles, fn private_role ->
          assert Enum.any?(policy.path_denials, fn denial ->
                   denial.source_root == "#{@root}/#{source_capability}/" and
                     denial.target_root == "#{@root}/#{target_capability}/#{private_role}/" and
                     denial.kinds == ["runtime", "export", "compile"]
                 end),
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

  test "queries cannot reach effectful adapters" do
    policy = DependencyPolicy.load!("config/architecture_boundaries.exs")

    Enum.each(@query_adapter_denied_capabilities, fn capability ->
      assert denial?(
               policy,
               "#{@root}/#{capability}/queries/",
               "#{@root}/#{capability}/adapters/"
             )
    end)

    assert denial?(
             policy,
             "#{@root}/banner/queries/",
             "#{@root}/banner/adapters/cleanup/"
           )
  end

  test "Workspace workers can enter the context only through its root facade" do
    policy = DependencyPolicy.load!("config/architecture_boundaries.exs")

    assert denial?(
             policy,
             "lib/storyarn/workers/workspaces/",
             "lib/storyarn/workspaces/"
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
