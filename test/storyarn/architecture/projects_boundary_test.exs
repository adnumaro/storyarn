defmodule Storyarn.Architecture.ProjectsBoundaryTest do
  use ExUnit.Case, async: true

  @projects_domain_sources ["lib/storyarn/projects.ex" | Path.wildcard("lib/storyarn/projects/**/*.ex")]

  @projects_business_sources "lib/storyarn/projects/**/*.ex"
                             |> Path.wildcard()
                             |> Enum.reject(&String.contains?(&1, ["/workers/", "/adapter/", "/adapters/"]))

  @projects_web_sources Path.wildcard("lib/storyarn_web/live/project_live/**/*.ex") ++
                          Path.wildcard("lib/storyarn_web/live/project_settings_live/**/*.ex") ++
                          Path.wildcard("lib/storyarn_web/live/asset_live/**/*.ex") ++
                          Path.wildcard("lib/storyarn_web/live/template_live/**/*.ex") ++
                          [
                            "lib/storyarn_web/controllers/export_controller.ex",
                            "lib/storyarn_web/controllers/private_media_controller.ex",
                            "lib/storyarn_web/controllers/snapshot_download_controller.ex",
                            "lib/storyarn_web/controllers/upload_controller.ex"
                          ]

  # Protocol derivation is a presentation adapter that must name the encoded
  # struct at compile time. All executable Web code enters through Projects.
  @projects_web_facade_sources Path.wildcard("lib/storyarn_web/**/*.ex") --
                                 ["lib/storyarn_web/live_vue_encoders.ex"]

  @project_facade_coordinators [
    "lib/storyarn/platform/discovery/queries/global_search/variable_search.ex",
    "lib/storyarn/release.ex"
  ]

  @foreign_domain_roots [
    "lib/storyarn/accounts",
    "lib/storyarn/workspaces",
    "lib/storyarn/flows",
    "lib/storyarn/scenes",
    "lib/storyarn/sheets",
    "lib/storyarn/localization",
    "lib/storyarn/ai",
    "lib/storyarn/commercial",
    "lib/storyarn/platform/notifications",
    "lib/storyarn/platform"
  ]

  test "Projects domain does not depend on StoryarnWeb" do
    violations =
      @projects_domain_sources
      |> Enum.flat_map(&storyarn_web_references/1)
      |> Enum.sort()

    assert violations == [], """
    The Project boundary cannot depend on its Phoenix or LiveVue adapters:

    #{Enum.join(violations, "\n")}
    """
  end

  test "Projects business modules do not re-enter the root facade" do
    violations =
      @projects_business_sources
      |> Enum.flat_map(&projects_facade_references/1)
      |> Enum.sort()

    assert violations == [], """
    Code inside the Projects boundary must collaborate through the exact
    internal module that owns the operation. Calling Storyarn.Projects from a
    Projects business module creates a facade cycle. Workers and technical
    adapters are the only allowed in-boundary facade consumers:

    #{Enum.join(violations, "\n")}
    """
  end

  test "StoryarnWeb enters Projects only through the root facade" do
    violations =
      @projects_web_facade_sources
      |> Enum.flat_map(&internal_projects_references/1)
      |> Enum.sort()

    assert violations == [], """
    StoryarnWeb may call only the public Storyarn.Projects facade. Move the
    operation behind Storyarn.Projects instead of importing a Project internal:

    #{Enum.join(violations, "\n")}
    """
  end

  test "external coordinators enter Projects only through the root facade" do
    violations =
      @project_facade_coordinators
      |> Enum.flat_map(&internal_projects_references/1)
      |> Enum.sort()

    assert violations == [], """
    External coordinators may call only the public Storyarn.Projects facade.
    Move the operation behind Storyarn.Projects instead of importing a Project
    internal:

    #{Enum.join(violations, "\n")}
    """
  end

  test "Project Web cannot publish generic business facts" do
    violations =
      Enum.filter(@projects_web_sources, fn path ->
        File.read!(path) =~ "Projects.Events"
      end)

    refute File.read!("lib/storyarn/projects.ex") =~ "defdelegate emit_event"

    assert violations == [], """
    Web adapters may call typed Project commands, but may not choose an event name
    or construct a domain-event payload themselves:

    #{Enum.join(violations, "\n")}
    """
  end

  test "the ratchet seals baselines with no remaining ENG-107 migration debt" do
    config = File.read!("config/architecture_boundaries.exs")
    {policy, _binding} = Code.eval_file("config/architecture_boundaries.exs")

    for context <- ~w(accounts ai commercial flows localization platform projects scenes sheets workspaces) do
      assert config =~ ~r/zero_debt_consumers:[^\]]*:#{context}/s
      assert config =~ ~r/isolated_contexts:[^\]]*:#{context}/s
    end

    assert config =~ ~r/zero_debt_consumers:[^\]]*:infrastructure/s
    assert config =~ ~r/zero_debt_consumers:[^\]]*:web_infrastructure/s

    for baseline <- Path.wildcard("config/architecture_baselines/*.json") do
      assert %{"edges" => []} = baseline |> File.read!() |> JSON.decode!(),
             "#{baseline} must stay empty: sealed consumers cannot accept hidden debt"
    end

    assert policy.migration_exceptions == [],
           "ENG-107 is complete; storage dependencies must terminate at reviewed public contracts"

    assert policy.durable_contracts != [],
           "reviewed root-facade calls must remain explicit durable contracts"
  end

  test "the dissolved shared namespace stays dissolved" do
    refute File.dir?("lib/storyarn/shared"),
           "lib/storyarn/shared was dissolved by the ENG-92 physical reorganization and must stay deleted"

    violations =
      @foreign_domain_roots
      |> Enum.flat_map(fn root -> Path.wildcard(root <> "*/**/*.ex") ++ Path.wildcard(root <> ".ex") end)
      |> Enum.uniq()
      |> Enum.flat_map(fn path ->
        path
        |> shared_references()
        |> Enum.filter(&match?(%{segments: [:Storyarn, :Shared | _]}, &1))
        |> Enum.map(&"#{path}:#{&1.line}: #{Enum.join(&1.segments, ".")}")
      end)
      |> Enum.sort()

    assert violations == [], """
    Storyarn.Shared no longer exists; utilities live in their owning boundary:

    #{Enum.join(violations, "\n")}
    """
  end

  defp shared_references(path) do
    ast = path |> File.read!() |> Code.string_to_quoted!(file: path, columns: true)

    {_ast, aliases} =
      Macro.prewalk(ast, [], fn
        {:__aliases__, meta, segments} = node, acc ->
          {node, [%{segments: segments, line: meta[:line]} | acc]}

        node, acc ->
          {node, acc}
      end)

    aliases
  end

  defp storyarn_web_references(path) do
    ast = path |> File.read!() |> Code.string_to_quoted!(file: path, columns: true)

    {_ast, aliases} =
      Macro.prewalk(ast, [], fn
        {:__aliases__, meta, segments} = node, acc ->
          {node, [%{segments: segments, line: meta[:line]} | acc]}

        node, acc ->
          {node, acc}
      end)

    aliases
    |> Enum.filter(&match?(%{segments: [:StoryarnWeb | _]}, &1))
    |> Enum.map(&"#{path}:#{&1.line}: #{Enum.join(&1.segments, ".")}")
    |> Enum.uniq()
  end

  defp projects_facade_references(path) do
    source = File.read!(path)
    ast = Code.string_to_quoted!(source, file: path, columns: true)

    {_ast, references} =
      Macro.prewalk(ast, [], fn
        {:__aliases__, meta, [:Storyarn, :Projects]} = node, references ->
          {node, ["#{path}:#{meta[:line]}: Storyarn.Projects" | references]}

        node, references ->
          {node, references}
      end)

    grouped_aliases =
      source
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {line, line_number} ->
        if Regex.match?(~r/\balias\s+Storyarn\.\{[^}]*\bProjects\b/, line) do
          ["#{path}:#{line_number}: #{String.trim(line)}"]
        else
          []
        end
      end)

    Enum.uniq(references ++ grouped_aliases)
  end

  defp internal_projects_references(path) do
    source = File.read!(path)
    ast = Code.string_to_quoted!(source, file: path, columns: true)
    local_aliases = projects_facade_aliases(ast)

    ast
    |> module_aliases()
    |> Enum.filter(&internal_projects_alias?(&1.segments, local_aliases))
    |> Enum.map(&"#{path}:#{&1.line}: #{Enum.join(&1.segments, ".")}")
    |> Kernel.++(grouped_projects_alias_violations(path, source))
    |> Enum.uniq()
  end

  defp projects_facade_aliases(ast) do
    {_ast, aliases} =
      Macro.prewalk(ast, MapSet.new([:Projects]), fn
        {:alias, _meta, [{:__aliases__, _, [:Storyarn, :Projects]}, opts]} = node, aliases
        when is_list(opts) ->
          alias_name =
            case Keyword.get(opts, :as) do
              {:__aliases__, _, [name]} -> name
              _other -> :Projects
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

  defp internal_projects_alias?([:Storyarn, :Projects, _internal | _rest], _local_aliases), do: true

  defp internal_projects_alias?([local_alias, _internal | _rest], local_aliases),
    do: MapSet.member?(local_aliases, local_alias)

  defp internal_projects_alias?(_segments, _local_aliases), do: false

  defp grouped_projects_alias_violations(path, source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_number} ->
      if Regex.match?(~r/\bStoryarn\.Projects\.\{/, line) do
        ["#{path}:#{line_number}: #{String.trim(line)}"]
      else
        []
      end
    end)
  end
end
