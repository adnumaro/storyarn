defmodule Storyarn.Architecture.ProjectsAssetUsageBoundaryTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.SQL
  alias Storyarn.Projects.Assets
  alias Storyarn.Projects.Assets.AssetFamily
  alias Storyarn.Projects.Assets.AssetOperations
  alias Storyarn.Projects.Assets.AssetTrash
  alias Storyarn.Projects.Assets.Queries.AssetUsageQueries
  alias Storyarn.Repo

  @usage_query_path "lib/storyarn/projects/assets/queries/asset_usage_queries.ex"
  @family_rule_path "lib/storyarn/projects/assets/rules/asset_family.ex"
  @allowed_usage_repo_imports [{Repo, :all, 1}]

  @usage_contract [
    get_asset_usages: 2,
    get_asset_family_usages: 2,
    count_asset_usages: 2
  ]

  test "asset usage has one read owner behind the Assets facade" do
    assert Code.ensure_loaded?(Assets)
    assert Code.ensure_loaded?(AssetUsageQueries)
    assert Code.ensure_loaded?(AssetOperations)

    facade_imports = beam_imports(Assets)

    for {function, arity} <- @usage_contract do
      assert function_exported?(AssetUsageQueries, function, arity)
      assert {AssetUsageQueries, function, arity} in facade_imports

      refute function_exported?(AssetOperations, function, arity)
      refute {AssetOperations, function, arity} in facade_imports
    end

    refute Enum.any?(beam_imports(AssetUsageQueries), fn {module, _function, _arity} ->
             module == AssetOperations
           end)
  end

  test "usage and trash share one pure asset-family graph" do
    assert Code.ensure_loaded?(AssetFamily)
    assert function_exported?(AssetFamily, :component_ids, 2)

    assert {AssetFamily, :component_ids, 2} in beam_imports(AssetUsageQueries)
    assert {AssetFamily, :component_ids, 2} in beam_imports(AssetTrash)
    refute function_exported?(AssetTrash, :active_family_ids, 2)

    refute Enum.any?(beam_imports(AssetUsageQueries), fn {module, _function, _arity} ->
             module == AssetTrash
           end)
  end

  test "asset usage remains a read-only query" do
    usage_source = File.read!(@usage_query_path)

    repo_imports =
      AssetUsageQueries
      |> beam_imports()
      |> Enum.filter(fn {module, _function, _arity} ->
        module in [Repo, Ecto.Multi, SQL]
      end)
      |> Enum.sort()

    assert repo_imports == Enum.sort(@allowed_usage_repo_imports)
    refute effectful_query_source?(usage_source)
  end

  test "the asset-family rule remains persistence-free" do
    family_source = File.read!(@family_rule_path)

    forbidden_imports =
      AssetFamily
      |> beam_imports()
      |> Enum.filter(fn {module, _function, _arity} ->
        module in [Repo, Ecto.Query, Ecto.Multi, SQL]
      end)

    assert forbidden_imports == []
    assert AssetFamily.__info__(:functions) == [component_ids: 2]

    refute Regex.match?(
             ~r/\b(?:Storyarn\.Repo|Repo\.|Ecto\.(?:Query|Multi|Adapters\.SQL))\b/,
             family_source
           )
  end

  defp beam_imports(module) do
    {:ok, {_module, [{:imports, imports}]}} =
      module
      |> :code.which()
      |> :beam_lib.chunks([:imports])

    imports
  end

  defp effectful_query_source?(source) do
    Regex.match?(
      ~r/
        \bEcto\.Multi\b |
        \bEcto\.Adapters\.SQL\b |
        \b(?:Kernel\.)?apply\s*\( |
        \bFunction\.capture\s*\( |
        \block\s*:\s*"FOR\s |
        \bFOR\s+(?:UPDATE|NO\s+KEY\s+UPDATE|SHARE|KEY\s+SHARE)\b
      /x,
      source
    )
  end
end
