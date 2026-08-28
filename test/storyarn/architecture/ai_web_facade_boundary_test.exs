defmodule Storyarn.Architecture.AIWebFacadeBoundaryTest do
  use ExUnit.Case, async: true

  @ai_web_sources ~w(
    lib/storyarn_web/live/settings_live/ai_team.ex
    lib/storyarn_web/live/settings_live/ai_team_overview.ex
    lib/storyarn_web/live/settings_live/integration_detail.ex
    lib/storyarn_web/live/settings_live/integrations.ex
  )

  @ai_domain_sources [
    "lib/storyarn/ai.ex"
    | Path.wildcard("lib/storyarn/ai/**/*.ex")
  ]

  test "AI-owned Web surfaces enter the bounded context only through Storyarn.AI" do
    violations =
      @ai_web_sources
      |> Enum.flat_map(&internal_ai_references/1)
      |> Enum.sort()

    assert violations == [], """
    AI settings LiveViews may call only the public Storyarn.AI facade.
    Move the operation behind Storyarn.AI instead of importing an AI internal:

    #{Enum.join(violations, "\n")}
    """
  end

  test "AI domain code does not depend on StoryarnWeb" do
    violations =
      @ai_domain_sources
      |> Enum.flat_map(&storyarn_web_references/1)
      |> Enum.sort()

    assert violations == [], """
    Storyarn.AI cannot depend on its Phoenix or LiveVue adapters:

    #{Enum.join(violations, "\n")}
    """
  end

  defp internal_ai_references(path) do
    ast = path |> File.read!() |> Code.string_to_quoted!(file: path, columns: true)
    local_aliases = ai_facade_aliases(ast)

    ast
    |> module_aliases()
    |> Enum.filter(&internal_ai_alias?(&1.segments, local_aliases))
    |> Enum.map(&"#{path}:#{&1.line}: #{Enum.join(&1.segments, ".")}")
    |> Kernel.++(grouped_alias_violations(path))
    |> Enum.uniq()
  end

  defp ai_facade_aliases(ast) do
    {_ast, aliases} =
      Macro.prewalk(ast, MapSet.new([:AI]), fn
        {:alias, _meta, [{:__aliases__, _, [:Storyarn, :AI]}, opts]} = node, aliases
        when is_list(opts) ->
          alias_name =
            case Keyword.get(opts, :as) do
              {:__aliases__, _, [name]} -> name
              _ -> :AI
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

  defp internal_ai_alias?([:Storyarn, :AI, _internal | _rest], _local_aliases), do: true

  defp internal_ai_alias?([local_alias, _internal | _rest], local_aliases), do: MapSet.member?(local_aliases, local_alias)

  defp internal_ai_alias?(_segments, _local_aliases), do: false

  defp grouped_alias_violations(path) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_number} ->
      if Regex.match?(~r/\bStoryarn\.AI\.\{/, line) do
        ["#{path}:#{line_number}: #{String.trim(line)}"]
      else
        []
      end
    end)
  end

  defp storyarn_web_references(path) do
    ast = path |> File.read!() |> Code.string_to_quoted!(file: path, columns: true)

    ast
    |> module_aliases()
    |> Enum.filter(&match?([:StoryarnWeb | _rest], &1.segments))
    |> Enum.map(&"#{path}:#{&1.line}: #{Enum.join(&1.segments, ".")}")
    |> Enum.uniq()
  end
end
